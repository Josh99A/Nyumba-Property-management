// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit_repository.dart';

/// Adverts read from the server and written through the command router.
///
/// Use [CloudListingRepository.publicCatalog] for anonymous browsing: it reads
/// the world-readable projection and refuses every mutation outright rather
/// than letting one fail deeper down.
final class CloudListingRepository implements ListingRepository {
  CloudListingRepository({
    required CloudReader reader,
    required CommandDispatcher commands,
    required CloudScope scope,
    required UnitRepository units,
    required PropertyRepository properties,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _reader = reader,
       _commands = commands,
       _scope = scope,
       _units = units,
       _properties = properties,
       _idGenerator = idGenerator ?? const UuidIdGenerator(),
       _clock = clock,
       _aggregate = CommandAggregate.listing,
       _readOnly = false;

  /// The public marketplace: `publicListings`, no writes.
  CloudListingRepository.publicCatalog({
    required CloudReader reader,
    Clock clock = const SystemClock(),
  }) : _reader = reader,
       _commands = null,
       _scope = const PublicScope(),
       _units = null,
       _properties = null,
       _idGenerator = const UuidIdGenerator(),
       _clock = clock,
       _aggregate = CommandAggregate.publicListing,
       _readOnly = true;

  final CloudReader _reader;
  final CommandDispatcher? _commands;
  final CloudScope _scope;
  final UnitRepository? _units;
  final PropertyRepository? _properties;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Which projection this instance reads. The private and public shapes share
  /// document ids but deliberately differ, so they are kept in separate cache
  /// namespaces — merging them would let whichever arrived last erase the
  /// other's fields.
  final CommandAggregate _aggregate;

  final bool _readOnly;

  @override
  Stream<CloudData<List<Listing>>> watchAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
  }) => _reader
      .watch(_aggregate, _scope, decode: ListingMapper.fromJson)
      .map(
        (data) => data.map(
          (items) => _filterAndSort(
            items,
            landlordId: landlordId,
            propertyId: propertyId,
            publicOnly: publicOnly,
          ),
        ),
      );

  @override
  Stream<CloudData<Listing?>> watchById(String id) =>
      watchAll().map((data) => data.map((items) => _firstOrNull(items, id)));

  @override
  Future<CloudData<List<Listing>>> getAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
    bool forceRefresh = false,
  }) async {
    final data = await _reader.fetch(
      _aggregate,
      _scope,
      decode: ListingMapper.fromJson,
      allowCached: !forceRefresh,
    );
    return data.map(
      (items) => _filterAndSort(
        items,
        landlordId: landlordId,
        propertyId: propertyId,
        publicOnly: publicOnly,
      ),
    );
  }

  @override
  Future<CloudData<Listing?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async {
    final data = await getAll(forceRefresh: forceRefresh);
    return data.map((items) => _firstOrNull(items, id));
  }

  @override
  Future<MutationResult> createDraft(CreateListingInput input) async {
    _ensureWritable();
    input.validate();

    // An advert describes a rental space, so its shape comes from the space
    // rather than from whatever the form happened to collect: bedroom and
    // bathroom counts, the unit type, and the amenities are all the unit's
    // facts. A failed read is refused rather than defaulted, because a listing
    // silently advertising "0 bedrooms" is worse than one that would not save.
    final unit = _require(
      await _units!.getById(input.unitId),
      'unit',
      input.unitId,
    );
    // A pin the landlord placed explicitly wins; otherwise the advert starts
    // from where its property is. Pinning a property once is what makes this
    // usable — asking for a pin per unit is how the field ends up empty.
    final property = _require(
      await _properties!.getById(input.propertyId),
      'property',
      input.propertyId,
    );
    final pin =
        Coordinates.tryFrom(
          input.approximateLatitude,
          input.approximateLongitude,
        ) ??
        property.location;
    // An advert may override the property's gallery, but an empty selection
    // inherits it. Without this the marketplace cover for a photo-less advert
    // falls back to the same generic placeholder for every listing, when the
    // property's own primary image was right there.
    final imageUrls = input.imageUrls.isEmpty
        ? property.imageUrls
        : input.imageUrls;

    return _send(
      type: 'listing.saveDraft',
      aggregateId: _idGenerator.generate(),
      operation: CommandOperation.create,
      expectedVersion: 0,
      payload: <String, Object?>{
        'unitId': input.unitId.trim(),
        ..._editableFields(
          title: input.title,
          description: input.description,
          monthlyRentMinor: input.monthlyRentMinor,
          unitType: unit.type.name,
          city: input.city,
          neighborhood: input.neighborhood,
          district: input.district,
          bedrooms: unit.bedrooms,
          bathrooms: unit.bathrooms,
          amenities: unit.amenities,
          latitude: pin?.latitude,
          longitude: pin?.longitude,
          clearablePin: false,
        ),
        'imageUrls': imageUrls
            .map((item) => item.trim())
            .toList(growable: false),
      },
    );
  }

  /// Unwraps a single-record read that a write depends on.
  ///
  /// A read that failed is not a record that is missing, and acting on that
  /// confusion here would reject a perfectly valid advert because the network
  /// blinked.
  static T _require<T>(CloudData<T?> data, String entity, String id) {
    if (data.hasFailed) {
      throw DomainValidationException(<String, String>{
        entity: 'could not be loaded; check your connection and try again',
      });
    }
    final value = data.value;
    if (value == null) throw EntityNotFoundException(entity, id);
    return value;
  }

  @override
  Future<MutationResult> update(Listing listing) async {
    _ensureWritable();
    listing.validate();
    return _send(
      type: 'listing.saveDraft',
      aggregateId: listing.id,
      operation: CommandOperation.update,
      expectedVersion: _requireVersion(
        listing.serverVersion,
        'listing.saveDraft',
      ),
      payload: <String, Object?>{
        'unitId': listing.unitId,
        ..._editableFields(
          title: listing.title,
          description: listing.description,
          monthlyRentMinor: listing.monthlyRentMinor,
          unitType: listing.unitType,
          city: listing.city,
          neighborhood: listing.neighborhood,
          district: listing.district,
          bedrooms: listing.bedrooms,
          bathrooms: listing.bathrooms,
          amenities: listing.amenities,
          latitude: listing.approximateLatitude,
          longitude: listing.approximateLongitude,
          // An edit must be able to take a pin back, which an omitted key
          // cannot express: `listing.saveDraft` spreads the payload onto the
          // draft, so an absent key leaves the stored pin untouched.
          clearablePin: true,
        ),
        'imageUrls': listing.imageUrls
            .map((item) => item.trim())
            .toList(growable: false),
      },
    );
  }

  @override
  Future<MutationResult> publish(Listing listing) async {
    _ensureWritable();
    // Checked here so a landlord gets a precise, immediate reason rather than a
    // generic rejection — the server enforces the same rule and remains the
    // authority. A read that failed is not a vacant space: refusing on an
    // unreadable unit is safer than advertising one that may be occupied.
    final unit = await _units!.getById(listing.unitId);
    if (unit.hasFailed) {
      throw DomainValidationException(<String, String>{
        'unit': 'could not be checked; try again when you are connected',
      });
    }
    final space = unit.value;
    if (space == null) {
      throw EntityNotFoundException('unit', listing.unitId);
    }
    if (!space.canBeAdvertised) {
      throw DomainValidationException(<String, String>{
        'unit.status': 'only vacant rental spaces can be advertised',
      });
    }
    if (!listing.hasPhotos) {
      throw DomainValidationException(<String, String>{
        'imageUrls': 'add at least one photo of the rental space to publish',
      });
    }
    return _send(
      type: 'listing.publish',
      aggregateId: listing.id,
      operation: CommandOperation.publish,
      expectedVersion: _requireVersion(
        listing.serverVersion,
        'listing.publish',
      ),
      payload: const <String, Object?>{},
    );
  }

  @override
  Future<MutationResult> unpublish(Listing listing) async {
    _ensureWritable();
    return _send(
      type: 'listing.unpublish',
      aggregateId: listing.id,
      operation: CommandOperation.delete,
      expectedVersion: _requireVersion(
        listing.serverVersion,
        'listing.unpublish',
      ),
      payload: const <String, Object?>{},
    );
  }

  /// The fields `listing.saveDraft` accepts, shared by create and edit.
  ///
  /// The server's schema is strict, so anything not named here is rejected
  /// outright — which is why the client-only fields on `Listing` (furnished,
  /// utilities, policies, contact details) are deliberately absent.
  Map<String, Object?> _editableFields({
    required String title,
    required String description,
    required int monthlyRentMinor,
    required String? unitType,
    required String city,
    required String? neighborhood,
    required String? district,
    required int? bedrooms,
    required int? bathrooms,
    required List<String> amenities,
    required double? latitude,
    required double? longitude,
    required bool clearablePin,
  }) => <String, Object?>{
    'title': title.trim(),
    'description': description.trim(),
    'monthlyRentMinor': monthlyRentMinor,
    'unitType': unitType ?? 'other',
    'city': city.trim(),
    'neighborhood': (neighborhood ?? city).trim(),
    if (district != null && district.trim().isNotEmpty)
      'district': district.trim(),
    'bedrooms': bedrooms ?? 0,
    'bathrooms': bathrooms ?? 0,
    'amenities': amenities
        .map((amenity) => amenity.trim())
        .where((amenity) => amenity.isNotEmpty)
        .toList(growable: false),
    if (latitude != null && longitude != null)
      'approximateLocation': <String, Object?>{
        'lat': latitude,
        'lng': longitude,
      }
    else if (clearablePin)
      'approximateLocation': null,
  };

  Future<MutationResult> _send({
    required String type,
    required String aggregateId,
    required CommandOperation operation,
    required Map<String, Object?> payload,
    int? expectedVersion,
  }) async {
    final outcome = await _commands!.submit(
      CloudCommand(
        commandId: _idGenerator.generate(),
        type: type,
        aggregate: CommandAggregate.listing,
        aggregateId: aggregateId,
        operation: operation,
        payload: payload,
        issuedAt: _clock.now().toUtc(),
        expectedVersion: expectedVersion,
      ),
    );
    _reader.invalidate(CommandAggregate.listing);
    // Publishing and retiring both change what visitors see, so the public
    // catalogue this session may also be holding is stale the moment this lands.
    _reader.invalidate(CommandAggregate.publicListing);
    return MutationResult(aggregateId: aggregateId, outcome: outcome);
  }

  /// Refuses a write on the public catalogue before it can reach anything.
  ///
  /// An anonymous visitor has no command the server would accept, so failing
  /// here is both honest and immediate — the alternative is a request that
  /// travels to Firebase only to be denied.
  void _ensureWritable() {
    if (!_readOnly) return;
    throw const CommandException(
      kind: CommandFailureKind.permissionDenied,
      code: 'PUBLIC_CATALOGUE_IS_READ_ONLY',
      details: <String, Object?>{'reason': 'signInRequired'},
    );
  }

  static int _requireVersion(int? version, String commandType) {
    if (version == null || version < 1) {
      throw DomainValidationException(<String, String>{
        'expectedVersion':
            '$commandType needs an advert loaded from the server first',
      });
    }
    return version;
  }

  static Listing? _firstOrNull(List<Listing> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<Listing> _filterAndSort(
    List<Listing> items, {
    String? landlordId,
    String? propertyId,
    required bool publicOnly,
  }) {
    final result = items
        .where(
          (listing) =>
              (!publicOnly || listing.isPublic) &&
              (landlordId == null || listing.landlordId == landlordId) &&
              (propertyId == null || listing.propertyId == propertyId),
        )
        .toList(growable: false);
    result.sort((left, right) {
      final published = (right.publishedAt ?? right.createdAt).compareTo(
        left.publishedAt ?? left.createdAt,
      );
      return published != 0 ? published : left.title.compareTo(right.title);
    });
    return result;
  }
}
