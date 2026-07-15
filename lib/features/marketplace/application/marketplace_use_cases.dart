import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../domain/application.dart';
import '../domain/listing.dart';

/// Application-layer entry points for marketplace mutations.
final createListingDraftProvider = Provider<CreateListingDraft>(
  CreateListingDraft.new,
);
final updateListingProvider = Provider<UpdateListing>(UpdateListing.new);
final publishListingProvider = Provider<PublishListing>(PublishListing.new);
final unpublishListingProvider = Provider<UnpublishListing>(
  UnpublishListing.new,
);
final submitRentalApplicationProvider = Provider<SubmitRentalApplication>(
  SubmitRentalApplication.new,
);

class CreateListingDraft {
  const CreateListingDraft(this._ref);

  final Ref _ref;

  Future<Listing> call(CreateListingInput input) async {
    final session = _requirePermission(
      _ref,
      AppResource.privateListing,
      CrudOperation.create,
    );
    if (session.role == AppRole.landlord &&
        input.landlordId != session.userId) {
      throw StateError('Landlords can create listings only for their account.');
    }
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.listings.createDraft(input);
  }
}

class UpdateListing {
  const UpdateListing(this._ref);

  final Ref _ref;

  Future<Listing> call(Listing listing) async {
    final session = _requirePermission(
      _ref,
      AppResource.privateListing,
      CrudOperation.update,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    final current = await deps.listings.getById(listing.id);
    if (current == null) throw StateError('Listing not found.');
    if (session.role == AppRole.landlord &&
        current.landlordId != session.userId) {
      throw StateError('Landlords can edit only their own listings.');
    }
    if (current.status == ListingStatus.published) {
      throw StateError('Unpublish this listing before editing it.');
    }
    return deps.listings.update(listing);
  }
}

class PublishListing {
  const PublishListing(this._ref);

  final Ref _ref;

  Future<Listing> call(String listingId) async {
    final session = _requirePermission(
      _ref,
      AppResource.privateListing,
      CrudOperation.update,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    await _requireListingOwnership(deps.listings.getById, session, listingId);
    return deps.listings.publish(listingId);
  }
}

class UnpublishListing {
  const UnpublishListing(this._ref);

  final Ref _ref;

  Future<Listing> call(String listingId) async {
    final session = _requirePermission(
      _ref,
      AppResource.privateListing,
      CrudOperation.delete,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    await _requireListingOwnership(deps.listings.getById, session, listingId);
    return deps.listings.unpublish(listingId);
  }
}

class SubmitRentalApplication {
  const SubmitRentalApplication(this._ref);

  final Ref _ref;

  Future<RentalApplication> call(ApplyForUnitInput input) async {
    _requirePermission(_ref, AppResource.application, CrudOperation.create);
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.applications.apply(input);
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

Future<void> _requireListingOwnership(
  Future<Listing?> Function(String id) getById,
  UserSession session,
  String listingId,
) async {
  final listing = await getById(listingId);
  if (listing == null) throw StateError('Listing not found.');
  if (session.role == AppRole.landlord &&
      listing.landlordId != session.userId) {
    throw StateError('Landlords can manage only their own listings.');
  }
}
