import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/config/maps_config.dart';
import '../../../../core/domain/coordinates.dart';
import '../../../../core/localization/app_localizations_adapter.dart';
import '../../domain/listing.dart';
import 'listing_map.dart';
import 'listing_query.dart';
import 'listing_result_card.dart';

/// The marketplace results drawn on a map.
///
/// The most expensive surface in the product to render — an interactive map is
/// billed per load — so it is deliberately opt-in behind the List/Map control
/// rather than the default view, and it never re-queries on its own.
class ListingMapView extends StatefulWidget {
  const ListingMapView({
    required this.listings,
    required this.query,
    required this.onQueryChanged,
    required this.onOpen,
    super.key,
  });

  final List<Listing> listings;
  final ListingQuery query;
  final ValueChanged<ListingQuery> onQueryChanged;
  final ValueChanged<Listing> onOpen;

  @override
  State<ListingMapView> createState() => _ListingMapViewState();
}

class _ListingMapViewState extends State<ListingMapView> {
  GoogleMapController? _controller;

  /// Where the camera is now, updated as the visitor drags.
  Coordinates? _camera;
  double _zoom = 12;
  double _visibleSpan = 0.1;

  /// Where the camera was when the results on screen were last committed.
  /// The gap between this and [_camera] is what "Search this area" reacts to.
  Coordinates? _searchedAt;

  @override
  void initState() {
    super.initState();
    _searchedAt = widget.query.centre ?? _initialCentre();
    _camera = _searchedAt;
    _zoom = widget.query.zoom ?? _initialZoom();
  }

  Coordinates _initialCentre() =>
      boundsOf(widget.listings)?.centre ??
      Coordinates(
        latitude: NyumbaMaps.defaultLatitude,
        longitude: NyumbaMaps.defaultLongitude,
      );

  /// Frames the results on a first visit rather than opening on a fixed
  /// viewport, so the map arrives showing the homes that were searched for.
  double _initialZoom() {
    final bounds = boundsOf(widget.listings);
    if (bounds == null) return 12;
    final span = bounds.latitudeSpan > bounds.longitudeSpan
        ? bounds.latitudeSpan
        : bounds.longitudeSpan;
    if (span > 1) return 8;
    if (span > 0.3) return 10;
    if (span > 0.1) return 11;
    if (span > 0.03) return 13;
    return 14;
  }

  bool get _hasDrifted {
    final camera = _camera;
    final searchedAt = _searchedAt;
    if (camera == null || searchedAt == null) return false;
    return viewportDrift(
          from: searchedAt,
          to: camera,
          visibleSpanDegrees: _visibleSpan,
        ) >
        searchThisAreaDriftThreshold;
  }

  @override
  Widget build(BuildContext context) {
    // An unkeyed build cannot construct a map at all — on iOS the SDK throws
    // and on web the JS bundle is absent — so this check has to come before
    // the widget, not inside an error handler.
    if (!NyumbaMaps.isConfigured) return const _MapUnavailable();
    final clusters = clusterListings(widget.listings, zoom: _zoom);
    final unpinned = widget.listings.length - _pinnedCount(clusters);
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(_searchedAt!.latitude, _searchedAt!.longitude),
              zoom: _zoom,
            ),
            markers: _markersFor(clusters),
            onMapCreated: (controller) => _controller = controller,
            onCameraMove: (position) {
              _camera = Coordinates(
                latitude: position.target.latitude,
                longitude: position.target.longitude,
              );
              _zoom = position.zoom;
            },
            // Rebuilds only when the drag ends, not on every frame of it.
            onCameraIdle: () => setState(_recomputeVisibleSpan),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
        ),
        // Never fires on its own. Auto-search on pan is the single most
        // disliked interaction in map search, because the results move while
        // the visitor is still looking at them.
        if (_hasDrifted)
          PositionedDirectional(
            top: 12,
            start: 0,
            end: 0,
            child: Center(child: _SearchThisAreaButton(onPressed: _searchHere)),
          ),
        // A searched area with nothing in it. Said plainly and over a live map,
        // because the way out is to pan and search again — not to leave.
        if (widget.listings.isEmpty)
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: 24,
            end: 24,
            child: Center(child: _EmptyAreaNotice()),
          )
        // The map can only show adverts that carry a pin, so it must say when
        // it is not showing everything the list would.
        else if (unpinned > 0)
          PositionedDirectional(
            bottom: 12,
            start: 12,
            end: 12,
            child: _UnpinnedNotice(count: unpinned),
          ),
      ],
    );
  }

  int _pinnedCount(List<ListingCluster> clusters) =>
      clusters.fold(0, (total, cluster) => total + cluster.count);

  void _recomputeVisibleSpan() {
    // Degrees visible at this zoom, near enough for a drift ratio: the map
    // halves its span with each zoom step from a whole-world view.
    _visibleSpan = 360 / (1 << _zoom.round().clamp(1, 21));
  }

  /// Narrows the results to what the map is showing, and writes the viewport to
  /// the URL so the map someone shares opens where they left it.
  ///
  /// The rectangle comes from the SDK rather than from the camera centre and
  /// zoom: those two describe the same viewport only if you also know the
  /// widget's aspect ratio, and searching a different area than the one on
  /// screen is the failure this button is supposed to avoid.
  Future<void> _searchHere() async {
    final camera = _camera;
    if (camera == null) return;
    final region = await _controller?.getVisibleRegion();
    if (!mounted) return;
    // A null region means the platform view has not laid out yet, so there is
    // no honest area to commit and nothing is narrowed. Leaving the button up
    // is the point: marking the viewport as searched would hide it as though
    // the search had worked, with no way back until the visitor pans.
    if (region == null) return;
    setState(() => _searchedAt = camera);
    widget.onQueryChanged(
      widget.query.copyWith(
        centre: camera,
        zoom: _zoom,
        searchedArea: ListingViewport(
          south: region.southwest.latitude,
          west: region.southwest.longitude,
          north: region.northeast.latitude,
          east: region.northeast.longitude,
        ),
      ),
    );
  }

  Set<Marker> _markersFor(List<ListingCluster> clusters) => {
    for (final cluster in clusters)
      Marker(
        markerId: MarkerId(
          cluster.isGroup
              ? 'group-${cluster.centre.latitude}-${cluster.centre.longitude}'
              : cluster.only.id,
        ),
        position: LatLng(cluster.centre.latitude, cluster.centre.longitude),
        infoWindow: InfoWindow(title: _labelFor(cluster)),
        onTap: () =>
            cluster.isGroup ? _zoomInto(cluster) : _showCard(cluster.only),
      ),
  };

  /// A group pin zooms in rather than opening a list of ten cards: the map
  /// already knows how to separate them, and one more zoom step is a cheaper
  /// interaction than a sheet the visitor has to dismiss.
  Future<void> _zoomInto(ListingCluster cluster) async {
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(cluster.centre.latitude, cluster.centre.longitude),
        (_zoom + 2).clamp(1, 21),
      ),
    );
  }

  String _labelFor(ListingCluster cluster) {
    final rent = NumberFormat.compactCurrency(
      symbol: 'UGX ',
      decimalDigits: 0,
    ).format(cluster.lowestRentMinor / 100);
    return cluster.isGroup ? '$rent+ · ${cluster.count}' : rent;
  }

  /// Tapping a pin opens the same card the list uses, so the two views never
  /// drift into showing different things about the same advert.
  void _showCard(Listing listing) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(sheetContext).padding.bottom + 16,
        ),
        child: ListingResultCard(
          listing: listing,
          onOpen: () {
            Navigator.of(sheetContext).pop();
            widget.onOpen(listing);
          },
        ),
      ),
    );
  }
}

class _SearchThisAreaButton extends StatelessWidget {
  const _SearchThisAreaButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: Text.localized(appLocalizationsOf(context).searchThisArea),
    );
  }
}

/// Shown over the map when the searched area holds nothing.
///
/// Deliberately not the marketplace's full empty state: that one replaces the
/// results entirely, and replacing the map would take away the only control
/// that can undo a searched area.
class _EmptyAreaNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.localized(
              appLocalizationsOf(context).noHomesMatch,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text.localized(
              appLocalizationsOf(context).tryBroaderSearch,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnpinnedNotice extends StatelessWidget {
  const _UnpinnedNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          appLocalizationsOf(context).homesNotOnMap(count),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// What a build with no Maps key shows instead of a map.
///
/// An explicit state, never an indefinite spinner: this is the one part of the
/// product that genuinely cannot work without a network and a key, and saying
/// so is better than pretending to load.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.nyumba.sageTint,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 32,
                color: context.nyumba.mutedInk,
              ),
              const SizedBox(height: 10),
              Text.localized(
                appLocalizationsOf(context).mapUnavailableOffline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
