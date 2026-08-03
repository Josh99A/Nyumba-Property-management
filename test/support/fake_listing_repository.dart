// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit_repository.dart';

/// An in-memory advert repository for tests whose subject is something else.
///
/// Tests *about* advert reads and writes drive the real `CloudListingRepository`
/// against `FakeCloudReadGateway`/`RecordingCommandGateway`. This exists for the
/// cases where a listing merely has to be there — a unit going unavailable, a
/// property archive being blocked — so the test can say what it means without
/// standing up a gateway.
///
/// It mirrors the real repository's behaviour where it matters: a draft takes
/// its shape from the unit, an advert inherits the property's pin, and every
/// stored record carries a `serverVersion`, because everything here represents
/// something the server has already accepted.
final class FakeListingRepository implements ListingRepository {
  FakeListingRepository({UnitRepository? units, PropertyRepository? properties})
    : _units = units,
      _properties = properties;

  final UnitRepository? _units;
  final PropertyRepository? _properties;
  final Map<String, Listing> records = <String, Listing>{};
  final _ids = const UuidIdGenerator();

  DateTime retrievedAt = DateTime.utc(2026, 7, 29, 9);
  CloudReadError? readError;

  /// Commands this repository was asked to send, in order, as `type` strings.
  final List<String> sent = <String>[];

  Listing put(Listing listing) => records[listing.id] = listing;

  /// Creates and hands back the stored record. Test-only convenience; the real
  /// repository returns proof of commit rather than an entity.
  Future<Listing> createReturning(CreateListingInput input) async {
    final result = await createDraft(input);
    return records[result.aggregateId]!;
  }

  @override
  Future<MutationResult> createDraft(CreateListingInput input) async {
    input.validate();
    final unit = (await _units?.getById(input.unitId))?.value;
    final property = (await _properties?.getById(input.propertyId))?.value;
    final pin =
        Coordinates.tryFrom(
          input.approximateLatitude,
          input.approximateLongitude,
        ) ??
        property?.location;
    final listing = Listing(
      id: _ids.generate(),
      unitId: input.unitId,
      propertyId: input.propertyId,
      landlordId: input.landlordId,
      title: input.title.trim(),
      description: input.description.trim(),
      monthlyRentMinor: input.monthlyRentMinor,
      currency: input.currency,
      status: ListingStatus.draft,
      bedrooms: unit?.bedrooms,
      bathrooms: unit?.bathrooms,
      unitType: unit?.type.name,
      amenities: unit?.amenities ?? const <String>[],
      city: input.city.trim(),
      district: input.district,
      // Mirrors the real repository: the advert falls back to the city when no
      // neighbourhood was given. Photos belong to the exact rental space and
      // are never silently copied from the property's building gallery.
      neighborhood: input.neighborhood ?? input.city.trim(),
      approximateLatitude: pin?.latitude,
      approximateLongitude: pin?.longitude,
      // Trimmed exactly as `CloudListingRepository.createDraft` trims before it
      // sends the command, so a test cannot accept a payload production would
      // never produce.
      imageUrls: input.imageUrls
          .map((item) => item.trim())
          .toList(growable: false),
      contactPhone: input.contactPhone,
      createdAt: retrievedAt,
      updatedAt: retrievedAt,
      serverVersion: 1,
    );
    records[listing.id] = listing;
    return _result(listing.id, 'listing.saveDraft');
  }

  @override
  Future<MutationResult> update(Listing listing) async {
    records[listing.id] = listing;
    return _result(listing.id, 'listing.saveDraft');
  }

  @override
  Future<MutationResult> publish(Listing listing) async {
    records[listing.id] = listing.copyWith(
      status: ListingStatus.published,
      publishedAt: retrievedAt,
      updatedAt: retrievedAt,
      serverVersion: (listing.serverVersion ?? 1) + 1,
    );
    return _result(listing.id, 'listing.publish');
  }

  @override
  Future<MutationResult> unpublish(Listing listing) async {
    records[listing.id] = listing.copyWith(
      status: ListingStatus.paused,
      updatedAt: retrievedAt,
      serverVersion: (listing.serverVersion ?? 1) + 1,
    );
    return _result(listing.id, 'listing.unpublish');
  }

  @override
  Future<MutationResult> remove(Listing listing) async {
    records.remove(listing.id);
    return _result(listing.id, 'listing.discard');
  }

  MutationResult _result(String id, String type) {
    sent.add(type);
    return MutationResult(
      aggregateId: id,
      outcome: CommandOutcome(committedAt: retrievedAt),
    );
  }

  CloudData<T> _wrap<T>(T value, {required bool isEmpty}) {
    final error = readError;
    if (error != null) return CloudData<T>.failure(error);
    return isEmpty
        ? CloudData<T>.empty(value, retrievedAt: retrievedAt)
        : CloudData<T>.live(value, retrievedAt: retrievedAt);
  }

  @override
  Future<CloudData<List<Listing>>> getAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
    bool forceRefresh = false,
  }) async {
    final items = records.values
        .where(
          (listing) =>
              (!publicOnly || listing.isPublic) &&
              (landlordId == null || listing.landlordId == landlordId) &&
              (propertyId == null || listing.propertyId == propertyId),
        )
        .toList(growable: false);
    return _wrap(items, isEmpty: items.isEmpty);
  }

  @override
  Future<CloudData<Listing?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async => _wrap(records[id], isEmpty: !records.containsKey(id));

  @override
  Stream<CloudData<List<Listing>>> watchAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
  }) async* {
    yield await getAll(
      landlordId: landlordId,
      propertyId: propertyId,
      publicOnly: publicOnly,
    );
  }

  @override
  Stream<CloudData<Listing?>> watchById(String id) async* {
    yield await getById(id);
  }
}
