import 'dart:math' as math;

/// A point on a map.
///
/// Shared by `Property` and `Listing` so the two cannot drift into different
/// spellings of the same idea, and pure Dart so the domain layer stays free of
/// Flutter, Firestore, and the maps SDK — a `Coordinates` is a fact about a
/// place, not a marker on a widget.
final class Coordinates {
  Coordinates({required this.latitude, required this.longitude}) {
    final error = latitudeError(latitude) ?? longitudeError(longitude);
    if (error != null) {
      throw ArgumentError.value('$latitude, $longitude', 'coordinates', error);
    }
  }

  /// The pair, or null when either axis is missing or unusable.
  ///
  /// Both or neither on purpose: a lone axis cannot be placed on a map, and a
  /// half-pair that decoded cleanly would render an empty map rather than an
  /// honest "no location".
  static Coordinates? tryFrom(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return null;
    if (latitudeError(latitude) != null || longitudeError(longitude) != null) {
      return null;
    }
    return Coordinates(latitude: latitude, longitude: longitude);
  }

  final double latitude;
  final double longitude;

  static String? latitudeError(double? value) =>
      _axisError(value, minimum: -90, maximum: 90);

  static String? longitudeError(double? value) =>
      _axisError(value, minimum: -180, maximum: 180);

  static String? _axisError(
    double? value, {
    required double minimum,
    required double maximum,
  }) {
    if (value == null) return null;
    if (!value.isFinite || value < minimum || value > maximum) {
      return 'must be between $minimum and $maximum';
    }
    return null;
  }

  /// The point as the public catalogue would carry it.
  ///
  /// Mirrors the rounding `listingPublish` applies before writing
  /// `publicListings`, so a landlord's "this is what tenants see" preview shows
  /// the same coarsened point the server will actually publish rather than a
  /// flattering approximation of it. Three decimal places is roughly 110 m.
  ///
  /// This is a display aid only. The server coarsens independently and remains
  /// the authority; never treat a client-coarsened value as the published one.
  Coordinates coarsened({int decimalPlaces = 3}) {
    final factor = math.pow(10, decimalPlaces).toDouble();
    return Coordinates(
      latitude: (latitude * factor).roundToDouble() / factor,
      longitude: (longitude * factor).roundToDouble() / factor,
    );
  }

  /// Great-circle distance to [other], in metres.
  ///
  /// A haversine on a spherical earth, which is wrong by about 0.3% at worst
  /// and entirely irrelevant at the scale this is used for: ranking adverts
  /// across one city. Computed on-device precisely so that "nearest to me"
  /// costs nothing — a Distance Matrix call per listing per sort would be
  /// billable, slower, and no more useful for ordering a list.
  ///
  /// This is straight-line distance, not travel distance. Ordering by it is
  /// honest for "what is near me"; it must never be presented as a journey.
  double distanceMetresTo(Coordinates other) {
    final latitudeDelta = _radians(other.latitude - latitude);
    final longitudeDelta = _radians(other.longitude - longitude);
    final a =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_radians(latitude)) *
            math.cos(_radians(other.latitude)) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return _earthRadiusMetres * 2 * math.asin(math.min(1, math.sqrt(a)));
  }

  static const double _earthRadiusMetres = 6371000;

  static double _radians(double degrees) => degrees * math.pi / 180;

  @override
  bool operator ==(Object other) =>
      other is Coordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'Coordinates($latitude, $longitude)';
}
