import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import '../../../core/domain/domain_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../../marketplace/domain/listing.dart';
import '../domain/property.dart';
import '../domain/unit.dart';

/// Application-layer entry points for portfolio mutations. Presentation
/// invokes these instead of repositories so orchestration, policy checks, and
/// the session lifecycle stay out of widgets.
///
/// Every one of these reaches the server and returns only once it has answered.
/// The permission checks here are user-experience guards that keep a user from
/// composing work the server would refuse; the server re-checks all of them and
/// remains the only authority.
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

  Future<MutationResult> call(CreatePropertyInput input) async {
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
        location: input.location,
        imageUrls: input.imageUrls,
      ),
    );
  }
}

class CreateUnit {
  const CreateUnit(this._ref);

  final Ref _ref;

  Future<MutationResult> call(CreateUnitInput input) async {
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

  Future<MutationResult> call(Property property) async {
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

/// Outcome of a rental-space update.
///
/// [advertWasWithdrawn] reports that the server took a published advert down as
/// part of this change — a space that is no longer vacant cannot stay on the
/// public marketplace. It is derived from what was published *before* the
/// command and only reported once the server confirmed the change, so it
/// describes something that has actually happened rather than something the
/// client hopes will.
final class UpdateUnitResult {
  const UpdateUnitResult({
    required this.outcome,
    this.advertWasWithdrawn = false,
  });

  final MutationResult outcome;
  final bool advertWasWithdrawn;
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
    final current = _require(
      await deps.units.getById(unit.id),
      'unit',
      unit.id,
    );

    if (unit.status != current.status &&
        (unit.status == UnitStatus.occupied ||
            current.status == UnitStatus.occupied)) {
      throw DomainValidationException(<String, String>{
        'unit.status':
            'manage occupied status by adding or ending the active tenancy',
      });
    }

    // Whether an advert is about to come down. Read before the command so the
    // answer describes the state the change acted on; reported after, so it is
    // only ever said about a change the server accepted.
    final losesVacancy =
        unit.status != UnitStatus.vacant && unit.status != current.status;
    final advertised =
        losesVacancy &&
        ((await deps.listings.getAll(propertyId: unit.propertyId)).value ??
                const <Listing>[])
            .any(
              (listing) =>
                  listing.unitId == unit.id &&
                  listing.status == ListingStatus.published,
            );

    // One command, and the client arranges nothing else. The server retires the
    // public projection in the same transaction as the unit change, and both
    // this workspace's adverts and the public catalogue are now read from the
    // server — so the retirement arrives on its own listener rather than being
    // forged locally, which is what the previous interim step had to do.
    final outcome = await deps.units.update(unit);
    return UpdateUnitResult(outcome: outcome, advertWasWithdrawn: advertised);
  }
}

class ArchiveUnit {
  const ArchiveUnit(this._ref);

  final Ref _ref;

  Future<MutationResult> call(String unitId) async {
    final session = _requirePermission(
      _ref,
      AppResource.unit,
      CrudOperation.delete,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    final unit = _require(await deps.units.getById(unitId), 'unit', unitId);
    if (session.role == AppRole.landlord && unit.landlordId != session.userId) {
      throw StateError('Landlords can archive rental spaces they own.');
    }
    if (unit.status != UnitStatus.vacant) {
      throw DomainValidationException(<String, String>{
        'unit.status': 'end the active tenancy before archiving this space',
      });
    }
    // Only a genuinely live advert blocks archiving. The old check also blocked
    // on a paused advert whose retirement had not synced yet — a condition that
    // no longer exists, because an unpublish either reached the server or did
    // not happen at all.
    final listings = await deps.listings.getAll(propertyId: unit.propertyId);
    // A read that failed is not "no adverts". Archiving on that assumption
    // could retire a space that is still being advertised to visitors.
    if (!listings.isValidated) {
      throw DomainValidationException(<String, String>{
        'listing': 'could not confirm this space is not advertised; try again',
      });
    }
    final stillAdvertised = (listings.value ?? const <Listing>[]).any(
      (listing) =>
          listing.unitId == unit.id &&
          listing.status == ListingStatus.published,
    );
    if (stillAdvertised) {
      throw DomainValidationException(<String, String>{
        'listing': 'unpublish the advert before archiving this space',
      });
    }
    return deps.units.archive(unit);
  }
}

class GetPropertyById {
  const GetPropertyById(this._ref);

  final Ref _ref;

  /// Returns the read with its freshness intact so a caller can tell a property
  /// that does not exist from one that could not be loaded.
  Future<CloudData<Property?>> call(
    String propertyId, {
    bool forceRefresh = false,
  }) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.properties.getById(propertyId, forceRefresh: forceRefresh);
  }
}

class ArchiveProperty {
  const ArchiveProperty(this._ref);

  final Ref _ref;

  Future<MutationResult> call(String propertyId) async {
    _requirePermission(_ref, AppResource.property, CrudOperation.delete);
    final deps = await _ref.read(appDependenciesProvider.future);
    final property = _require(
      await deps.properties.getById(propertyId),
      'property',
      propertyId,
    );
    final units = await deps.units.getAll(propertyId: propertyId);
    // A read that failed is not an empty portfolio. Refusing here keeps the
    // command from archiving a property whose remaining spaces simply could
    // not be loaded.
    if (!units.isValidated) {
      throw DomainValidationException(<String, String>{
        'property': 'could not confirm this property is empty; try again',
      });
    }
    if ((units.value ?? const <Unit>[]).isNotEmpty) {
      throw DomainValidationException(<String, String>{
        'property': 'archive every rental space before archiving the property',
      });
    }
    return deps.properties.archive(property);
  }
}

/// Unwraps a single-record read, distinguishing "not there" from "not loaded".
///
/// A failed read must never be mistaken for a missing record: acting on that
/// confusion is how a transient outage turns into a wrong decision about
/// someone's property.
T _require<T>(CloudData<T?> data, String entity, String id) {
  if (data.hasFailed) {
    throw DomainValidationException(<String, String>{
      entity: 'could not be loaded; check your connection and try again',
    });
  }
  final value = data.value;
  if (value == null) throw EntityNotFoundException(entity, id);
  return value;
}

UserSession _requirePermission(
  Ref ref,
  AppResource resource,
  CrudOperation operation,
) {
  final session = ref.read(sessionControllerProvider);
  if (session == null ||
      !AuthorizationPolicy.allowsSession(session, resource, operation)) {
    throw StateError('${operation.name} permission is required.');
  }
  return session;
}
