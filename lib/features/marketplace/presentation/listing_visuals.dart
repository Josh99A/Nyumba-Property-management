import '../domain/listing.dart';

String listingAssetFor(Listing listing) {
  final title = listing.title.toLowerCase();
  if (title.contains('sunset')) {
    return 'assets/listings/sunset-apartments.png';
  }
  if (title.contains('riverside')) {
    return 'assets/listings/riverside-heights.png';
  }
  if (title.contains('nyumbani')) {
    return 'assets/listings/nyumbani-gardens.png';
  }
  return 'assets/listings/kilimani-garden-court.png';
}

String listingLocationFor(Listing listing) {
  final title = listing.title.toLowerCase();
  if (title.contains('sunset')) return 'Ntinda, Kampala';
  if (title.contains('riverside')) return 'Riverside, Kampala';
  if (title.contains('nyumbani')) return 'Ggaba Road, Kampala';
  return 'Kololo, Kampala';
}
