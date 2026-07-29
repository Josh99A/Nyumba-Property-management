import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:url_launcher/url_launcher.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../config/maps_config.dart';
import '../domain/coordinates.dart';
import '../localization/app_localizations_adapter.dart';
import 'async_action_button.dart';

/// Hands a private, **exact** coordinate to whatever maps app the user has.
///
/// Private surfaces only. Staff are dispatched to a site and a tenant is going
/// to their own front door, so both want the precise point the landlord placed
/// — the coarsened coordinate the public marketplace shows would send someone
/// to the wrong end of the road. Public surfaces use
/// [ListingLocationSection], which is fed the coarsened copy instead.
///
/// Deep-link only, and deliberately so: this needs no Maps SDK, no API key, and
/// costs nothing per tap. It also arrives in the user's own app with their
/// traffic data, saved places, and offline maps — strictly better than anything
/// an embedded map could offer for the "take me there" job.
class DirectionsButton extends StatelessWidget {
  const DirectionsButton({
    required this.destination,
    this.label,
    this.filled = false,
    super.key,
  });

  /// Where to navigate, or null when nobody has placed a pin yet.
  final Coordinates? destination;

  /// Overrides the default "Get directions" wording.
  final String? label;

  /// Whether this is the surface's primary action.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final destination = this.destination;
    // Nothing at all rather than a disabled control. A greyed-out button
    // invites a tap and then explains nothing; the surrounding screen already
    // says where the property is in words.
    if (destination == null) return const SizedBox.shrink();
    final copy = appLocalizationsOf(context);
    final child = Text.localized(label ?? copy.getDirections);
    const icon = Icon(Icons.directions_outlined);
    // Enabled offline on purpose: the Maps app carries its own offline maps,
    // so refusing the tap would be worse than handing over.
    Future<void> open() => _open(destination);
    return filled
        ? AsyncActionButton(onPressed: open, icon: icon, child: child)
        : AsyncActionButton.outlined(onPressed: open, icon: icon, child: child);
  }

  Future<void> _open(Coordinates destination) async {
    await launchUrl(
      NyumbaMaps.directionsTo(destination.latitude, destination.longitude),
      mode: LaunchMode.externalApplication,
    );
  }
}
