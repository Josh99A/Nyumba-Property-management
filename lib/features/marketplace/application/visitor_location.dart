import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/domain/coordinates.dart';

/// Whether "Nearest to me" can be offered, and where the visitor is if so.
///
/// Three states rather than a nullable coordinate, because "we have not asked
/// yet" and "they said no" call for different interfaces: the first still
/// offers the option, the second must stop offering it.
enum VisitorLocationStatus {
  /// Offerable, but nothing has been requested yet. The permission prompt is
  /// deliberately deferred until a visitor actually picks the sort — a
  /// marketplace that asks for your location on arrival gets denied.
  available,

  /// A position is known.
  resolved,

  /// Unavailable for good: permission denied forever, or location services
  /// switched off. The sort option is withdrawn rather than left to fail.
  unavailable,
}

@immutable
class VisitorLocation {
  const VisitorLocation({required this.status, this.position});

  const VisitorLocation.initial()
    : status = VisitorLocationStatus.available,
      position = null;

  final VisitorLocationStatus status;
  final Coordinates? position;

  /// Whether the marketplace should show the "Nearest to me" option at all.
  bool get canOfferNearest => status != VisitorLocationStatus.unavailable;

  @override
  bool operator ==(Object other) =>
      other is VisitorLocation &&
      other.status == status &&
      other.position == position;

  @override
  int get hashCode => Object.hash(status, position);
}

/// Reads the visitor's position, on demand and never on arrival.
///
/// Deliberately not persisted and never sent anywhere: the position is used
/// on-device to order a list and nothing else. It is passed to
/// `ListingQuery.apply` as an argument rather than living on the query,
/// precisely so it cannot end up inside a shareable URL.
class VisitorLocationController extends Notifier<VisitorLocation> {
  @override
  VisitorLocation build() => const VisitorLocation.initial();

  /// Checks permission *without* prompting, so a visitor who has already
  /// refused is not offered a sort that cannot work.
  Future<void> refreshAvailability() async {
    if (!await _geolocator.isLocationServiceEnabled()) {
      state = const VisitorLocation(status: VisitorLocationStatus.unavailable);
      return;
    }
    final permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      state = const VisitorLocation(status: VisitorLocationStatus.unavailable);
    }
  }

  /// Asks for a position, prompting for permission if that has not happened.
  ///
  /// Returns null when the visitor declines, and marks the sort unavailable so
  /// the option withdraws itself instead of failing again on the next tap.
  Future<Coordinates?> resolve() async {
    if (state.position != null) return state.position;
    if (!await _geolocator.isLocationServiceEnabled()) {
      state = const VisitorLocation(status: VisitorLocationStatus.unavailable);
      return null;
    }
    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      state = const VisitorLocation(status: VisitorLocationStatus.unavailable);
      return null;
    }
    try {
      final position = await _geolocator.currentPosition();
      final resolved = Coordinates.tryFrom(
        position?.latitude,
        position?.longitude,
      );
      if (resolved == null) {
        state = const VisitorLocation(
          status: VisitorLocationStatus.unavailable,
        );
        return null;
      }
      state = VisitorLocation(
        status: VisitorLocationStatus.resolved,
        position: resolved,
      );
      return resolved;
    } on Object {
      // A timeout or a hardware failure is not a permission refusal, so the
      // option stays available for another try.
      return null;
    }
  }

  VisitorGeolocator get _geolocator => ref.read(visitorGeolocatorProvider);
}

/// The slice of `geolocator` this feature uses, behind an interface so the
/// marketplace's ordering rules can be tested without a device.
abstract interface class VisitorGeolocator {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<({double latitude, double longitude})?> currentPosition();
}

final class PlatformVisitorGeolocator implements VisitorGeolocator {
  const PlatformVisitorGeolocator();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<({double latitude, double longitude})?> currentPosition() async {
    // Low accuracy on purpose: this orders a list of neighbourhoods, so a
    // coarse fix is both sufficient and considerably faster and cheaper on
    // battery than a GPS lock.
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (latitude: position.latitude, longitude: position.longitude);
  }
}

final visitorGeolocatorProvider = Provider<VisitorGeolocator>(
  (ref) => const PlatformVisitorGeolocator(),
);

final visitorLocationProvider =
    NotifierProvider<VisitorLocationController, VisitorLocation>(
      VisitorLocationController.new,
    );
