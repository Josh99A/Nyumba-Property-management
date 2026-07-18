import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/domain/domain_exception.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../../marketplace/domain/listing.dart';
import '../domain/property.dart';
import '../domain/unit.dart';

/// Application-layer entry points for portfolio mutations. Presentation
/// invokes these instead of repositories so orchestration, policy checks,
/// and the workspace lifecycle stay out of widgets.
final createPropertyProvider = Provider<CreateProperty>(CreateProperty.new);
final createUnitProvider = Provider<CreateUnit>(CreateUnit.new);
final updatePropertyProvider = Provider<UpdateProperty>(UpdateProperty.new);
final updateUnitProvider = Provider<UpdateUnit>(UpdateUnit.new);
final archiveUnitProvider = Provider<ArchiveUnit>(ArchiveUnit.new);
final getPropertyByIdProvider = Provider<GetPropertyById>(GetPropertyById.new);
final archivePropertyProvider = Provider<ArchiveProperty>(ArchiveProperty.new);

class CreateProperty {
  const CreateProperty(this._ref);

  final Ref _ref;

  Future<Property> call(CreatePropertyInput input) async {
    final session = _requirePermission(
      _ref,
      AppResource.property,
      CrudOperation.create,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.properties.create(
      CreatePropertyInput(
        landlordId: session.role == AppRole.landlord
            ? session.userId
            : input.landlordId,
        name: input.name,
        addressLine: input.addressLine,
        city: input.city,
        country: input.country,
        description: input.description,
        imageUrls: input.imageUrls,
      ),
    );
  }
}

class CreateUnit {
  const CreateUnit(this._ref);

  final Ref _ref;

  Future<Unit> call(CreateUnitInput input) async {
    final session = _requirePermission(
      _ref,
      AppResource.unit,
      CrudOperation.create,
    );
    if (session.role == AppRole.landlord &&
        input.landlordId != session.userId) {
      throw StateError('Landlords can create rental spaces they own.');
    }
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.units.create(input);
  }
}

class UpdateProperty {
  const UpdateProperty(this._ref);

  final Ref _ref;

  Future<Property> call(Property property) async {
    final session = _requirePermission(
      _ref,
      AppResource.property,
      CrudOperation.update,
    );
    if (session.role == AppRole.landlord &&
        property.landlordId != session.userId) {
      throw StateError('Landlords can update properties they own.');
    }
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.properties.update(property);
  }
}

/// Outcome of a rental-space update, including whether the change forced a
/// published advert off the public marketplace.
final class UpdateUnitResult {
  const UpdateUnitResult({required this.unit, this.unpublishedListing});

  final Unit unit;
  final Listing? unpublishedListing;
}

class UpdateUnit {
  const UpdateUnit(this._ref);

  final Ref _ref;

  Future<UpdateUnitResult> call(Unit unit) async {
    final session = _requirePermission(
      _ref,
      AppResource.unit,
      CrudOperation.update,
    );
    if (session.role == AppRole.landlord && unit.landlordId != session.userId) {
      throw StateError('Landlords can update rental spaces they own.');
    }
    final deps = await _ref.read(appDependenciesProvider.future);
    final current = await deps.units.getById(unit.id);
    if (current == null) throw EntityNotFoundException('unit', unit.id);
    if (unit.status != current.status &&
        (unit.status == UnitStatus.occupied ||
            current.status == UnitStatus.occupied)) {
      throw DomainValidationException(<String, String>{
        'unit.status':
            'manage occupied status by adding or ending the active tenancy',
      });
    }

    // A space that is no longer vacant must not stay advertised. Pause the
    // local listing before the unit change so this device hides it at once;
    // the server retires the public projection atomically with unit.update.
    Listing? unpublished;
    if (unit.status != UnitStatus.vacant && unit.status != current.status) {
      final listings = await deps.listings.getAll(propertyId: unit.propertyId);
      for (final listing in listings) {
        if (listing.unitId == unit.id &&
            listing.status == ListingStatus.published) {
          unpublished = await deps.listings.unpublish(listing.id);
        }
      }
    }
    final updated = await deps.units.update(unit);
    // Occupancy drives what the public marketplace shows, so push promptly
    // instead of waiting for the next app-open or manual sync.
    unawaited(deps.syncEngine.syncPending());
    return UpdateUnitResult(unit: updated, unpublishedListing: unpublished);
  }
}

class ArchiveUnit {
  const ArchiveUnit(this._ref);

  final Ref _ref;

  Future<Unit> call(String unitId) async {
    final session = _requirePermission(
      _ref,
      AppResource.unit,
      CrudOperation.delete,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    final unit = await deps.units.getById(unitId);
    if (unit == null) throw EntityNotFoundException('unit', unitId);
    if (session.role == AppRole.landlord && unit.landlordId != session.userId) {
      throw StateError('Landlords can archive rental spaces they own.');
    }
    if (unit.status != UnitStatus.vacant) {
      throw DomainValidationException(<String, String>{
        'unit.status': 'end the active tenancy before archiving this space',
      });
    }
    final listings = await deps.listings.getAll(propertyId: unit.propertyId);
    final blockingListing = listings.any(
      (listing) =>
          listing.unitId == unit.id &&
          (listing.status == ListingStatus.published ||
              (listing.status == ListingStatus.paused &&
                  listing.syncMetadata.state != EntitySyncState.synced)),
    );
    if (blockingListing) {
      throw DomainValidationException(<String, String>{
        'listing': 'unpublish the listing and wait for confirmation first',
      });
    }
    return deps.units.archive(unitId);
  }
}

class GetPropertyById {
  const GetPropertyById(this._ref);

  final Ref _ref;

  Future<Property?> call(String propertyId) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.properties.getById(propertyId);
  }
}

class ArchiveProperty {
  const ArchiveProperty(this._ref);

  final Ref _ref;

  Future<Property> call(String propertyId) async {
    _requirePermission(_ref, AppResource.property, CrudOperation.delete);
    final deps = await _ref.read(appDependenciesProvider.future);
    final activeUnits = await deps.units.getAll(propertyId: propertyId);
    if (activeUnits.isNotEmpty) {
      throw DomainValidationException(<String, String>{
        'property': 'archive every rental space before archiving the property',
      });
    }
    return deps.properties.archive(propertyId);
  }
}

UserSession _requirePermission(
  Ref ref,
  AppResource resource,
  CrudOperation operation,
) {
  final session = ref.read(sessionControllerProvider);
  if (session == null ||
      !AuthorizationPolicy.allows(session.role, resource, operation)) {
    throw StateError('${operation.name} permission is required.');
  }
  return session;
}
