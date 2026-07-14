// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit_repository.dart';

final class SembastListingRepository implements ListingRepository {
  SembastListingRepository({
    required OfflineDatabase database,
    required PropertyRepository properties,
    required UnitRepository units,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _properties = properties,
       _units = units,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final PropertyRepository _properties;
  final UnitRepository _units;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<Listing> createDraft(CreateListingInput input) async {
    input.validate();
    final unit = await _units.getById(input.unitId);
    if (unit == null) throw EntityNotFoundException('unit', input.unitId);
    final property = await _properties.getById(input.propertyId);
    if (property == null) {
      throw EntityNotFoundException('property', input.propertyId);
    }
    final errors = <String, String>{};
    if (unit.propertyId != input.propertyId) {
      errors['propertyId'] = 'must match the referenced unit';
    }
    if (unit.landlordId != input.landlordId) {
      errors['landlordId'] = 'must own the referenced unit';
    }
    if (property.landlordId != input.landlordId) {
      errors['landlordId'] = 'must own the referenced property';
    }
    if (errors.isNotEmpty) throw DomainValidationException(errors);

    final now = _clock.now().toUtc();
    final listing = Listing(
      id: _idGenerator.generate(),
      unitId: input.unitId,
      propertyId: input.propertyId,
      landlordId: input.landlordId,
      title: input.title.trim(),
      description: input.description.trim(),
      monthlyRentMinor: input.monthlyRentMinor,
      currency: input.currency,
      status: ListingStatus.draft,
      bedrooms: unit.bedrooms,
      bathrooms: unit.bathrooms,
      unitType: unit.type.name,
      floor: unit.floor,
      floorAreaSquareMetres: input.floorAreaSquareMetres,
      furnished: input.furnished,
      parkingSpaces: input.parkingSpaces,
      amenities: unit.amenities.map((item) => item.trim()).toList(),
      accessibilityFeatures: input.accessibilityFeatures
          .map((item) => item.trim())
          .toList(),
      city: input.city.trim(),
      district: _optional(input.district),
      neighborhood: _optional(input.neighborhood),
      approximateLatitude: input.approximateLatitude,
      approximateLongitude: input.approximateLongitude,
      availableFrom: input.availableFrom?.toUtc(),
      minimumLeaseMonths: input.minimumLeaseMonths,
      securityDepositMinor: input.securityDepositMinor,
      serviceChargeMinor: input.serviceChargeMinor,
      utilitiesIncluded: input.utilitiesIncluded
          .map((item) => item.trim())
          .toList(),
      petsPolicy: _optional(input.petsPolicy),
      smokingPolicy: _optional(input.smokingPolicy),
      viewingInstructions: _optional(input.viewingInstructions),
      imageUrls: input.imageUrls.map((item) => item.trim()).toList(),
      videoUrl: _optional(input.videoUrl),
      contactPhone: _optional(input.contactPhone),
      contactEmail: _optional(input.contactEmail),
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _persist(
      listing,
      operation: OutboxOperation.create,
      createOnly: true,
    );
    return listing;
  }

  @override
  Future<List<Listing>> getAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
  }) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.listing,
    )).map(ListingMapper.fromJson),
    landlordId: landlordId,
    propertyId: propertyId,
    publicOnly: publicOnly,
  );

  @override
  Future<Listing?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.listing, id);
    return json == null ? null : ListingMapper.fromJson(json);
  }

  @override
  Future<Listing> publish(String listingId) async {
    final current = await getById(listingId);
    if (current == null) throw EntityNotFoundException('listing', listingId);
    if (current.status == ListingStatus.published) return current;
    final unit = await _units.getById(current.unitId);
    if (unit == null) throw EntityNotFoundException('unit', current.unitId);
    if (!unit.canBeAdvertised) {
      throw DomainValidationException(<String, String>{
        'unit.status': 'only vacant units can be advertised',
      });
    }

    final now = _clock.now().toUtc();
    final published = current
        .publish(at: now)
        .copyWith(syncMetadata: current.syncMetadata.markPending());
    await _persist(published, operation: OutboxOperation.publish);
    return published;
  }

  @override
  Future<Listing> update(Listing listing) async {
    listing.validate();
    final current = await getById(listing.id);
    if (current == null) throw EntityNotFoundException('listing', listing.id);
    final now = _clock.now().toUtc();
    // Status changes have dedicated workflows (publish, pause/close later), so
    // a regular edit cannot accidentally expose a draft.
    final updated = Listing(
      id: current.id,
      unitId: current.unitId,
      propertyId: current.propertyId,
      landlordId: current.landlordId,
      title: listing.title.trim(),
      description: listing.description.trim(),
      monthlyRentMinor: listing.monthlyRentMinor,
      currency: listing.currency,
      status: current.status,
      bedrooms: current.bedrooms,
      bathrooms: current.bathrooms,
      unitType: listing.unitType,
      floor: listing.floor,
      floorAreaSquareMetres: listing.floorAreaSquareMetres,
      furnished: listing.furnished,
      parkingSpaces: listing.parkingSpaces,
      amenities: listing.amenities.map((item) => item.trim()).toList(),
      accessibilityFeatures: listing.accessibilityFeatures
          .map((item) => item.trim())
          .toList(),
      city: listing.city.trim(),
      district: _optional(listing.district),
      neighborhood: _optional(listing.neighborhood),
      approximateLatitude: listing.approximateLatitude,
      approximateLongitude: listing.approximateLongitude,
      availableFrom: listing.availableFrom?.toUtc(),
      minimumLeaseMonths: listing.minimumLeaseMonths,
      securityDepositMinor: listing.securityDepositMinor,
      serviceChargeMinor: listing.serviceChargeMinor,
      utilitiesIncluded: listing.utilitiesIncluded
          .map((item) => item.trim())
          .toList(),
      petsPolicy: _optional(listing.petsPolicy),
      smokingPolicy: _optional(listing.smokingPolicy),
      viewingInstructions: _optional(listing.viewingInstructions),
      imageUrls: listing.imageUrls.map((item) => item.trim()).toList(),
      videoUrl: _optional(listing.videoUrl),
      contactPhone: _optional(listing.contactPhone),
      contactEmail: _optional(listing.contactEmail),
      publicContactToken: current.publicContactToken,
      createdAt: current.createdAt,
      updatedAt: now,
      publishedAt: current.publishedAt,
      expiresAt: current.expiresAt,
      projectionVersion: current.projectionVersion,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _persist(updated, operation: OutboxOperation.update);
    return updated;
  }

  @override
  Stream<List<Listing>> watchAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
  }) => _database
      .watchEntities(OfflineEntityType.listing)
      .map(
        (items) => _filterAndSort(
          items.map(ListingMapper.fromJson),
          landlordId: landlordId,
          propertyId: propertyId,
          publicOnly: publicOnly,
        ),
      );

  @override
  Stream<Listing?> watchById(String id) => _database
      .watchEntity(OfflineEntityType.listing, id)
      .map((json) => json == null ? null : ListingMapper.fromJson(json));

  Future<void> _persist(
    Listing listing, {
    required OutboxOperation operation,
    bool createOnly = false,
  }) => _database
      .putEntityAndEnqueue(
        entityType: OfflineEntityType.listing,
        entityId: listing.id,
        entity: ListingMapper.toJson(listing),
        mutationId: _idGenerator.generate(),
        operation: operation,
        createdAt: _clock.now().toUtc(),
        createOnly: createOnly,
        dependsOn: <AggregateReference>[
          AggregateReference(
            type: OfflineEntityType.property,
            id: listing.propertyId,
          ),
          AggregateReference(type: OfflineEntityType.unit, id: listing.unitId),
        ],
      )
      .then((_) {});

  static List<Listing> _filterAndSort(
    Iterable<Listing> listings, {
    String? landlordId,
    String? propertyId,
    required bool publicOnly,
  }) {
    final result = listings
        .where(
          (listing) =>
              (landlordId == null || listing.landlordId == landlordId) &&
              (propertyId == null || listing.propertyId == propertyId) &&
              (!publicOnly || listing.isPublic),
        )
        .toList(growable: false);
    result.sort((left, right) {
      final leftDate = left.publishedAt ?? left.updatedAt;
      final rightDate = right.publishedAt ?? right.updatedAt;
      return rightDate.compareTo(leftDate);
    });
    return result;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
