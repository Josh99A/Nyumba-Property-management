import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import 'listing.dart';

/// Adverts, read from the server and written through the command router.
///
/// Two instances of this exist at runtime and they are not interchangeable. A
/// landlord's repository reads `privateListings` scoped to their workspace and
/// can mutate. The public catalogue reads the world-readable `publicListings`
/// projection and refuses every mutation — an anonymous visitor has no command
/// they are permitted to send, and pretending otherwise is exactly what used to
/// produce locally "successful" writes that reached nothing.
abstract interface class ListingRepository {
  Stream<CloudData<List<Listing>>> watchAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
  });

  Stream<CloudData<Listing?>> watchById(String id);

  Future<CloudData<List<Listing>>> getAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
    bool forceRefresh = false,
  });

  Future<CloudData<Listing?>> getById(String id, {bool forceRefresh = false});

  /// Sends `listing.saveDraft`, which the router treats as an upsert of the
  /// draft's editable fields.
  Future<MutationResult> createDraft(CreateListingInput input);

  Future<MutationResult> update(Listing listing);

  /// Sends `listing.publish`. The advert is live only once this returns.
  Future<MutationResult> publish(Listing listing);

  Future<MutationResult> unpublish(Listing listing);

  /// Sends `listing.discard`: the owner permanently removing their own
  /// off-market advert. The server refuses while it is still published, so a
  /// live advert must be unpublished first.
  Future<MutationResult> remove(Listing listing);
}
