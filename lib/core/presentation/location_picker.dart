import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../app/theme/nyumba_colors.dart';
import '../config/maps_config.dart';
import '../domain/coordinates.dart';
import '../localization/app_localizations_adapter.dart';
import 'async_action_button.dart';
import 'surface.dart';

/// A form row for placing a property or advert on the map.
///
/// Replaces the pair of raw latitude/longitude text fields this app used to
/// ask landlords to fill in. Nobody types a correct coordinate into a text box,
/// which is why that field was empty on essentially every record.
class LocationPickerField extends StatelessWidget {
  const LocationPickerField({
    required this.value,
    required this.onChanged,
    super.key,
    this.showPublicPrivacyNotice = false,
  });

  final Coordinates? value;
  final ValueChanged<Coordinates?> onChanged;

  /// Whether this pin will end up on a public advert, in which case the picker
  /// shows the landlord the coarsened circle a visitor will actually see.
  final bool showPublicPrivacyNotice;

  @override
  Widget build(BuildContext context) {
    final pin = value;
    return NyumbaSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 20,
                color: context.nyumba.midnightNavy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.localized(
                  'Location on map',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.localized(
            pin == null
                ? 'Tenants use this to see the area and get directions.'
                : 'Published location is approximate',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.nyumba.mutedInk),
          ),
          const SizedBox(height: 14),
          if (pin != null) ...[
            _PinSummary(pin: pin),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AsyncActionButton.outlined(
                showBusyIndicator: false,
                icon: Icon(
                  pin == null
                      ? Icons.add_location_alt_outlined
                      : Icons.edit_location_alt_outlined,
                ),
                onPressed: () async {
                  final picked = await showLocationPicker(
                    context,
                    initial: pin,
                    showPrivacyCircle: showPublicPrivacyNotice,
                  );
                  if (picked != null) onChanged(picked);
                },
                child: Text.localized(
                  pin == null ? 'Set location on map' : 'Change location',
                ),
              ),
              if (pin != null)
                TextButton.icon(
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.location_off_outlined, size: 18),
                  label: const Text.localized('Remove location'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinSummary extends StatelessWidget {
  const _PinSummary({required this.pin});

  final Coordinates pin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.nyumba.sageTint,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: context.nyumba.sageDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            // Coordinates are data, not copy: they are never translated, and
            // four decimal places (~11 m) is as much precision as a human
            // reading a confirmation line can use.
            child: Text(
              '${pin.latitude.toStringAsFixed(4)}, '
              '${pin.longitude.toStringAsFixed(4)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the full-screen pin picker. Returns null when the landlord backed out.
Future<Coordinates?> showLocationPicker(
  BuildContext context, {
  Coordinates? initial,
  bool showPrivacyCircle = false,
}) {
  return showDialog<Coordinates>(
    context: context,
    useSafeArea: false,
    builder: (context) => Dialog.fullscreen(
      child: _LocationPickerSheet(
        initial: initial,
        showPrivacyCircle: showPrivacyCircle,
      ),
    ),
  );
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.initial,
    required this.showPrivacyCircle,
  });

  final Coordinates? initial;
  final bool showPrivacyCircle;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  GoogleMapController? _controller;
  late Coordinates _target;

  /// Null until the landlord has actually placed something, which is what the
  /// keyless fallback gates its confirm button on — there is no map to read a
  /// centre from there, so a default would confirm a pin nobody chose.
  Coordinates? _captured;
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _target =
        widget.initial ??
        Coordinates(
          latitude: NyumbaMaps.defaultLatitude,
          longitude: NyumbaMaps.defaultLongitude,
        );
    _captured = widget.initial;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return Scaffold(
      backgroundColor: context.nyumba.softIvory,
      appBar: AppBar(
        backgroundColor: context.nyumba.surface,
        leading: IconButton(
          tooltip: copy.cancel,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text.localized(copy.pinTheLocation),
      ),
      body: Column(
        children: [
          Expanded(
            child: NyumbaMaps.isConfigured ? _buildMap() : _buildFallback(),
          ),
          _Footer(
            showPrivacyCircle: widget.showPrivacyCircle,
            error: _error,
            locating: _locating,
            onLocate: _useCurrentLocation,
            // With a map on screen the centre is always a real choice, so
            // confirm is live from the start. Without one there is nothing to
            // confirm until the device has reported a position.
            onConfirm: NyumbaMaps.isConfigured
                ? () async => Navigator.pop(context, _target)
                : _captured == null
                ? null
                : () async => Navigator.pop(context, _captured),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final coarsened = _target.coarsened();
    return Stack(
      alignment: Alignment.center,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_target.latitude, _target.longitude),
            zoom: widget.initial == null ? 12 : 16,
          ),
          onMapCreated: (controller) => _controller = controller,
          onCameraMove: (position) => _target = Coordinates(
            latitude: position.target.latitude,
            longitude: position.target.longitude,
          ),
          // Only repaint at rest. Rebuilding the privacy circle on every frame
          // of a drag makes the map stutter on the low-end Android hardware
          // most Nyumba landlords are using.
          onCameraIdle: () => setState(() {}),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          circles: widget.showPrivacyCircle
              ? <Circle>{
                  Circle(
                    circleId: const CircleId('privacy'),
                    center: LatLng(coarsened.latitude, coarsened.longitude),
                    radius: NyumbaMaps.publicPrivacyRadiusMetres,
                    fillColor: context.nyumba.navyTint.withValues(alpha: 0.35),
                    strokeColor: context.nyumba.midnightNavy,
                    strokeWidth: 2,
                  ),
                }
              : const <Circle>{},
        ),
        // A fixed crosshair rather than a draggable marker: the landlord moves
        // the map under it, so the point they are placing is never hidden
        // beneath their own finger.
        IgnorePointer(
          child: Icon(
            Icons.add_location,
            size: 46,
            color: context.nyumba.terracottaDark,
          ),
        ),
        PositionedDirectional(
          top: 12,
          start: 12,
          end: 12,
          child: _Hint(
            text: widget.showPrivacyCircle
                ? appLocalizationsOf(context).tenantsSeeApproximateArea(
                    NyumbaMaps.publicPrivacyRadiusMetres.round() * 2,
                  )
                : appLocalizationsOf(context).dragMapToPosition,
          ),
        ),
      ],
    );
  }

  /// What a build with no Maps key shows.
  ///
  /// Not a dead end: `geolocator` needs no Maps key, so a landlord standing at
  /// the property can still capture its position. That is also the most
  /// accurate way to place a pin, map or no map.
  Widget _buildFallback() {
    final captured = _captured;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 48,
                color: context.nyumba.mutedInk,
              ),
              const SizedBox(height: 16),
              Text.localized(
                'The map is not available in this build',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text.localized(
                'You can still capture the location while standing at the property.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (captured != null) ...[
                const SizedBox(height: 20),
                _PinSummary(pin: captured),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final copy = appLocalizationsOf(context);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationFailure.unavailable();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationFailure.denied();
      }
      final position = await Geolocator.getCurrentPosition();
      final here = Coordinates.tryFrom(position.latitude, position.longitude);
      if (here == null) throw const _LocationFailure.unavailable();
      if (!mounted) return;
      setState(() {
        _target = here;
        _captured = here;
      });
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(here.latitude, here.longitude), 17),
      );
    } on _LocationFailure catch (failure) {
      if (mounted) {
        setState(
          () => _error = failure.denied
              ? copy.locationPermissionDenied
              : copy.locationUnavailable,
        );
      }
    } on Object {
      // Platform channels fail in their own ways — an unregistered plugin on
      // web, a revoked permission mid-call, a device with no GPS. None of them
      // should take the picker down when panning the map still works.
      if (mounted) setState(() => _error = copy.locationUnavailable);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }
}

class _LocationFailure implements Exception {
  const _LocationFailure.denied() : denied = true;
  const _LocationFailure.unavailable() : denied = false;

  final bool denied;
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      backgroundColor: context.nyumba.surface,
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: context.nyumba.midnightNavy,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.localized(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.showPrivacyCircle,
    required this.error,
    required this.locating,
    required this.onLocate,
    required this.onConfirm,
  });

  final bool showPrivacyCircle;
  final String? error;
  final bool locating;
  final Future<void> Function() onLocate;
  final Future<void> Function()? onConfirm;

  @override
  Widget build(BuildContext context) {
    final message = error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        border: BorderDirectional(
          top: BorderSide(color: context.nyumba.outline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: context.nyumba.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.nyumba.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              AsyncActionButton.outlined(
                onPressed: onLocate,
                busy: locating,
                icon: const Icon(Icons.my_location_rounded),
                child: Text.localized(
                  locating
                      ? 'Finding your location…'
                      : 'Use my current location',
                ),
              ),
              const SizedBox(height: 10),
              AsyncActionButton.filled(
                onPressed: onConfirm,
                showBusyIndicator: false,
                child: const Text.localized('Confirm location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
