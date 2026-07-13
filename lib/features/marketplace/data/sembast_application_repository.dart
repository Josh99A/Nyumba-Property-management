// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/application_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/application.dart';
import 'package:nyumba_property_management/features/marketplace/domain/application_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';

final class SembastApplicationRepository implements ApplicationRepository {
  SembastApplicationRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<RentalApplication> apply(ApplyForUnitInput input) async {
    input.validate();
    final listingJson = await _database.readEntity(
      OfflineEntityType.listing,
      input.listingId,
    );
    if (listingJson == null) {
      throw EntityNotFoundException('listing', input.listingId);
    }
    final listing = ListingMapper.fromJson(listingJson);
    if (listing.status != ListingStatus.published) {
      throw DomainValidationException(<String, String>{
        'listing.status': 'applications require a published listing',
      });
    }
    final existing = await getAll(
      applicantId: input.applicantId,
      listingId: input.listingId,
    );
    if (existing.any(
      (item) =>
          item.status != ApplicationStatus.rejected &&
          item.status != ApplicationStatus.withdrawn,
    )) {
      throw DomainValidationException(<String, String>{
        'listingId': 'an active application already exists for this listing',
      });
    }

    final now = _clock.now().toUtc();
    final application = RentalApplication(
      id: _idGenerator.generate(),
      listingId: listing.id,
      unitId: listing.unitId,
      propertyId: listing.propertyId,
      applicantId: input.applicantId,
      applicantName: input.applicantName.trim(),
      applicantEmail: input.applicantEmail.trim(),
      applicantPhone: input.applicantPhone.trim(),
      message: _optional(input.message),
      desiredMoveIn: input.desiredMoveIn?.toUtc(),
      status: ApplicationStatus.submitted,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _persist(
      application,
      operation: OutboxOperation.apply,
      createOnly: true,
    );
    return application;
  }

  @override
  Future<List<RentalApplication>> getAll({
    String? applicantId,
    String? listingId,
  }) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.application,
    )).map(ApplicationMapper.fromJson),
    applicantId: applicantId,
    listingId: listingId,
  );

  @override
  Future<RentalApplication?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.application, id);
    return json == null ? null : ApplicationMapper.fromJson(json);
  }

  @override
  Future<RentalApplication> update(RentalApplication application) async {
    application.validate();
    final current = await getById(application.id);
    if (current == null) {
      throw EntityNotFoundException('application', application.id);
    }
    if (!_canTransition(current.status, application.status)) {
      throw DomainValidationException(<String, String>{
        'status':
            'cannot change from ${current.status.name} to '
            '${application.status.name}',
      });
    }
    final now = _clock.now().toUtc();
    final updated = RentalApplication(
      id: current.id,
      listingId: current.listingId,
      unitId: current.unitId,
      propertyId: current.propertyId,
      applicantId: current.applicantId,
      applicantName: application.applicantName.trim(),
      applicantEmail: application.applicantEmail.trim(),
      applicantPhone: application.applicantPhone.trim(),
      message: _optional(application.message),
      desiredMoveIn: application.desiredMoveIn?.toUtc(),
      status: application.status,
      createdAt: current.createdAt,
      updatedAt: now,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _persist(updated, operation: OutboxOperation.update);
    return updated;
  }

  @override
  Stream<List<RentalApplication>> watchAll({
    String? applicantId,
    String? listingId,
  }) => _database
      .watchEntities(OfflineEntityType.application)
      .map(
        (items) => _filterAndSort(
          items.map(ApplicationMapper.fromJson),
          applicantId: applicantId,
          listingId: listingId,
        ),
      );

  @override
  Stream<RentalApplication?> watchById(String id) => _database
      .watchEntity(OfflineEntityType.application, id)
      .map((json) => json == null ? null : ApplicationMapper.fromJson(json));

  Future<void> _persist(
    RentalApplication application, {
    required OutboxOperation operation,
    bool createOnly = false,
  }) => _database
      .putEntityAndEnqueue(
        entityType: OfflineEntityType.application,
        entityId: application.id,
        entity: ApplicationMapper.toJson(application),
        mutationId: _idGenerator.generate(),
        operation: operation,
        createdAt: _clock.now().toUtc(),
        createOnly: createOnly,
        dependsOn: <AggregateReference>[
          AggregateReference(
            type: OfflineEntityType.listing,
            id: application.listingId,
          ),
        ],
      )
      .then((_) {});

  static List<RentalApplication> _filterAndSort(
    Iterable<RentalApplication> applications, {
    String? applicantId,
    String? listingId,
  }) {
    final result = applications
        .where(
          (application) =>
              (applicantId == null || application.applicantId == applicantId) &&
              (listingId == null || application.listingId == listingId),
        )
        .toList(growable: false);
    result.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return result;
  }

  static bool _canTransition(ApplicationStatus from, ApplicationStatus to) {
    if (from == to) return true;
    return switch (from) {
      ApplicationStatus.submitted =>
        to == ApplicationStatus.underReview ||
            to == ApplicationStatus.withdrawn,
      ApplicationStatus.underReview =>
        to == ApplicationStatus.approved ||
            to == ApplicationStatus.rejected ||
            to == ApplicationStatus.withdrawn,
      ApplicationStatus.approved ||
      ApplicationStatus.rejected ||
      ApplicationStatus.withdrawn => false,
    };
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
