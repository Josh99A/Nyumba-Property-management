import 'listing.dart';

abstract interface class ListingRepository {
  Stream<List<Listing>> watchAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
  });
  Stream<Listing?> watchById(String id);
  Future<List<Listing>> getAll({
    String? landlordId,
    String? propertyId,
    bool publicOnly = false,
  });
  Future<Listing?> getById(String id);
  Future<Listing> createDraft(CreateListingInput input);
  Future<Listing> update(Listing listing);
  Future<Listing> publish(String listingId);
  Future<Listing> unpublish(String listingId);
}
