import 'dart:async';

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
    final draft = await deps.listings.createDraft(input);
    _pushOutboxSoon(deps);
    return draft;
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
    final updated = await deps.listings.update(listing);
    _pushOutboxSoon(deps);
    return updated;
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
    final published = await deps.listings.publish(listingId);
    _pushOutboxSoon(deps);
    return published;
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
    final unpublished = await deps.listings.unpublish(listingId);
    _pushOutboxSoon(deps);
    return unpublished;
  }
}

class SubmitRentalApplication {
  const SubmitRentalApplication(this._ref);

  final Ref _ref;

  Future<RentalApplication> call(ApplyForUnitInput input) async {
    _requirePermission(_ref, AppResource.application, CrudOperation.create);
    final deps = await _ref.read(appDependenciesProvider.future);
    final application = await deps.applications.apply(input);
    _pushOutboxSoon(deps);
    return application;
  }
}

/// Pushes the queued command to the server without blocking the caller.
///
/// Marketplace mutations are only visible to other people once the server has
/// acknowledged them — a publish that sits in the outbox until the next manual
/// sync looks like a silent failure, because the listing never reaches the
/// public catalogue. The mutation itself is already durable in the outbox, so
/// this kick is best-effort: offline or failed pushes fall back to the existing
/// retry paths (app open, notifications init, the manual sync button).
void _pushOutboxSoon(AppDependencies deps) {
  unawaited(deps.syncEngine.syncPending());
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
