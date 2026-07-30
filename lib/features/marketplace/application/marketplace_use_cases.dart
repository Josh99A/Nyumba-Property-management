import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../domain/application.dart';
import '../domain/listing.dart';

/// Application-layer entry points for marketplace mutations.
///
/// Advert changes now reach the server on the spot and return only once it has
/// answered. That removes the failure mode the previous design had to work
/// around: a publish would sit in the outbox until some later sync, so the
/// advert never appeared publicly and the landlord had no way to tell that from
/// success.
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

  Future<MutationResult> call(CreateListingInput input) async {
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

  Future<MutationResult> call(Listing listing) async {
    final session = _requirePermission(
      _ref,
      AppResource.privateListing,
      CrudOperation.update,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    final current = _requireListing(
      await deps.listings.getById(listing.id),
      listing.id,
    );
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

  Future<MutationResult> call(String listingId) async {
    final session = _requirePermission(
      _ref,
      AppResource.privateListing,
      CrudOperation.update,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    final listing = _requireOwnedListing(
      await deps.listings.getById(listingId),
      session,
      listingId,
    );
    return deps.listings.publish(listing);
  }
}

class UnpublishListing {
  const UnpublishListing(this._ref);

  final Ref _ref;

  Future<MutationResult> call(String listingId) async {
    final session = _requirePermission(
      _ref,
      AppResource.privateListing,
      CrudOperation.delete,
    );
    final deps = await _ref.read(appDependenciesProvider.future);
    final listing = _requireOwnedListing(
      await deps.listings.getById(listingId),
      session,
      listingId,
    );
    return deps.listings.unpublish(listing);
  }
}

class SubmitRentalApplication {
  const SubmitRentalApplication(this._ref);

  final Ref _ref;

  Future<RentalApplication> call(ApplyForUnitInput input) async {
    _requirePermission(_ref, AppResource.application, CrudOperation.create);
    final deps = await _ref.read(appDependenciesProvider.future);
    final application = await deps.applications.apply(input);
    // Applications are still held in the local mirror, so their command still
    // travels by outbox and still needs the nudge. Retires with that slice.
    unawaited(deps.syncEngine.syncPending());
    return application;
  }
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

/// Unwraps an advert a mutation depends on.
///
/// A read that failed is not a listing that has been deleted. Telling a
/// landlord their advert is "not found" because the connection dropped would
/// send them looking for a problem that does not exist.
Listing _requireListing(CloudData<Listing?> data, String listingId) {
  if (data.hasFailed) {
    throw StateError(
      'This advert could not be loaded. Check your connection and try again.',
    );
  }
  final listing = data.value;
  if (listing == null) throw StateError('Listing not found.');
  return listing;
}

/// The ownership guard. A user-experience check that keeps a landlord from
/// composing work the server would refuse; Firestore Rules and the command
/// handlers enforce the same thing and remain the authority.
Listing _requireOwnedListing(
  CloudData<Listing?> data,
  UserSession session,
  String listingId,
) {
  final listing = _requireListing(data, listingId);
  if (session.role == AppRole.landlord &&
      listing.landlordId != session.userId) {
    throw StateError('Landlords can manage only their own listings.');
  }
  return listing;
}
