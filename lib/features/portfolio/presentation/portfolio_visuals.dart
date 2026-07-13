String propertyAssetForName(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('sunset')) {
    return 'assets/listings/sunset-apartments.png';
  }
  if (normalized.contains('riverside')) {
    return 'assets/listings/riverside-heights.png';
  }
  if (normalized.contains('nyumbani')) {
    return 'assets/listings/nyumbani-gardens.png';
  }
  return 'assets/listings/kilimani-garden-court.png';
}
