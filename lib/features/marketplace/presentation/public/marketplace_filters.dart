import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' hide Text, Tooltip;

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/localization/app_localizations_adapter.dart';
import '../../../../core/localization/localized_material.dart';
import '../../../../core/localization/nyumba_localizations.dart';
import '../../../../core/presentation/responsive.dart';
import '../../domain/listing.dart';
import '../listing_visuals.dart';
import 'listing_query.dart';

/// Width below which the three dropdowns stop fitting beside a usable search
/// field, and move into the filter sheet instead.
const double _inlineFiltersMinWidth = 900;

/// How a search field is framed by whatever is hosting it.
enum ListingSearchStyle {
  /// Standard outlined field.
  standard,

  /// Shorter outlined field, sized for the pinned bar's fixed extent.
  dense,

  /// No frame of its own; the hero pill draws the border and background.
  bare,
}

InputDecoration _fieldDecoration({required bool dense}) => InputDecoration(
  isDense: dense,
  contentPadding: dense
      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
      : null,
);

/// Search box that mirrors [value] instead of owning the text.
///
/// The hero panel and the pinned bar both show the same search, so neither can
/// be the source of truth. Each field keeps a private controller synchronised
/// with the query; the field being typed into sees its own value come back
/// unchanged and so never loses its cursor position.
class ListingSearchField extends StatefulWidget {
  const ListingSearchField({
    required this.value,
    required this.onChanged,
    super.key,
    this.onSubmitted,
    this.style = ListingSearchStyle.standard,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final ListingSearchStyle style;

  @override
  State<ListingSearchField> createState() => _ListingSearchFieldState();
}

class _ListingSearchFieldState extends State<ListingSearchField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant ListingSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _controller.text) return;
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bare = widget.style == ListingSearchStyle.bare;
    final clear = widget.value.isEmpty
        ? null
        : IconButton(
            tooltip: context.tr('Clear search'),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => widget.onChanged(''),
          );
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      textInputAction: TextInputAction.search,
      decoration: bare
          ? InputDecoration(
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: context.tr('Search by neighborhood or property'),
              suffixIcon: clear,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 34,
              ),
            )
          : _fieldDecoration(
              dense: widget.style == ListingSearchStyle.dense,
            ).copyWith(
              hintText: context.tr('Search by neighborhood or property'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: clear,
            ),
    );
  }
}

/// The hero's single rounded search control: a location field and the search
/// action inside one pill, which is what a visitor arrives looking for.
class HeroSearchBar extends StatelessWidget {
  const HeroSearchBar({
    required this.value,
    required this.onChanged,
    required this.onSearch,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final palette = context.nyumba;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 7, 7, 7),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33061B34),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelled = constraints.maxWidth >= 380;
            return Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 22,
                  color: palette.mutedInk,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ListingSearchField(
                    value: value,
                    onChanged: onChanged,
                    onSubmitted: onSearch,
                    style: ListingSearchStyle.bare,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onSearch,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(labelled ? 108 : 52, 52),
                    padding: EdgeInsets.symmetric(
                      horizontal: labelled ? 22 : 0,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  child: labelled
                      ? Text(copy.searchAction)
                      : Icon(
                          Icons.search_rounded,
                          size: 22,
                          semanticLabel: copy.searchAction,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.icon,
    required this.items,
    required this.onChanged,
    required this.dense,
  });

  final T value;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: _fieldDecoration(
        dense: dense,
      ).copyWith(prefixIcon: Icon(icon, size: dense ? 20 : 24)),
      items: items,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}

/// The three catalogue filters as separate widgets, so the hero grid, the
/// pinned row, and the sheet column can each size them their own way.
List<Widget> listingFilterFields({
  required ListingQuery query,
  required List<String> availableUnitTypes,
  required ValueChanged<ListingQuery> onChanged,
  bool dense = false,
}) => [
  _FilterDropdown<PriceBand>(
    value: query.price,
    icon: Icons.payments_outlined,
    dense: dense,
    items: [
      for (final band in PriceBand.values)
        DropdownMenuItem(value: band, child: Text.localized(band.label)),
    ],
    onChanged: (band) => onChanged(query.copyWith(price: band)),
  ),
  _FilterDropdown<BedroomsFilter>(
    value: query.bedrooms,
    icon: Icons.bed_outlined,
    dense: dense,
    items: [
      for (final option in BedroomsFilter.values)
        DropdownMenuItem(value: option, child: Text.localized(option.label)),
    ],
    onChanged: (option) => onChanged(query.copyWith(bedrooms: option)),
  ),
  _FilterDropdown<String>(
    value: query.unitType,
    icon: Icons.home_work_outlined,
    dense: dense,
    items: [
      const DropdownMenuItem(
        value: anyUnitType,
        child: Text.localized('All types'),
      ),
      for (final type in availableUnitTypes)
        DropdownMenuItem(value: type, child: Text(listingUnitTypeLabel(type))),
    ],
    onChanged: (type) => onChanged(query.copyWith(unitType: type)),
  ),
];

/// Search, filters, and sort pinned above the results while the grid scrolls.
///
/// Without this a visitor has to scroll back to the hero to change a single
/// filter, which on a phone means losing their place in the list entirely.
class MarketplaceFilterBar extends SliverPersistentHeaderDelegate {
  const MarketplaceFilterBar({
    required this.query,
    required this.searchText,
    required this.listings,
    required this.availableUnitTypes,
    required this.onChanged,
    required this.onSearchChanged,
    required this.extent,
  });

  final ListingQuery query;

  /// What the search field shows, which runs ahead of [query] while a visitor
  /// is still typing.
  final String searchText;

  /// The unfiltered catalogue, so the filter sheet can preview how many homes
  /// a draft selection would leave.
  final List<Listing> listings;
  final List<String> availableUnitTypes;
  final ValueChanged<ListingQuery> onChanged;
  final ValueChanged<String> onSearchChanged;
  final double extent;

  static double extentFor(BuildContext context) => context.isCompact ? 76 : 82;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final palette = context.nyumba;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: BorderDirectional(bottom: BorderSide(color: palette.divider)),
        boxShadow: overlapsContent
            ? const [
                BoxShadow(
                  color: Color(0x14123A6F),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.pageGutter,
              vertical: 12,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final search = ListingSearchField(
                  value: searchText,
                  style: ListingSearchStyle.dense,
                  onChanged: onSearchChanged,
                );
                if (constraints.maxWidth < _inlineFiltersMinWidth) {
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 8),
                      _FilterSheetButton(
                        query: query,
                        listings: listings,
                        availableUnitTypes: availableUnitTypes,
                        onChanged: onChanged,
                      ),
                      const SizedBox(width: 6),
                      _SortMenuButton(query: query, onChanged: onChanged),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    for (final field in listingFilterFields(
                      query: query,
                      availableUnitTypes: availableUnitTypes,
                      onChanged: onChanged,
                      dense: true,
                    )) ...[
                      const SizedBox(width: 10),
                      SizedBox(width: 178, child: field),
                    ],
                    const SizedBox(width: 10),
                    _SortMenuButton(query: query, onChanged: onChanged),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant MarketplaceFilterBar oldDelegate) =>
      oldDelegate.query != query ||
      oldDelegate.searchText != searchText ||
      oldDelegate.extent != extent ||
      !identical(oldDelegate.listings, listings) ||
      !listEquals(oldDelegate.availableUnitTypes, availableUnitTypes);
}

class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton({required this.query, required this.onChanged});

  final ListingQuery query;
  final ValueChanged<ListingQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ListingSort>(
      tooltip: context.tr('Sort results'),
      initialValue: query.sort,
      position: PopupMenuPosition.under,
      onSelected: (sort) => onChanged(query.copyWith(sort: sort)),
      itemBuilder: (context) => [
        for (final order in ListingSort.values)
          PopupMenuItem(value: order, child: Text.localized(order.label)),
      ],
      child: _BarButtonShell(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert_rounded, size: 20),
            if (context.isExpanded) ...[
              const SizedBox(width: 8),
              Text.localized(
                query.sort.label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterSheetButton extends StatelessWidget {
  const _FilterSheetButton({
    required this.query,
    required this.listings,
    required this.availableUnitTypes,
    required this.onChanged,
  });

  final ListingQuery query;
  final List<Listing> listings;
  final List<String> availableUnitTypes;
  final ValueChanged<ListingQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    // The search text has its own always-visible field, so counting it here
    // would badge the button for a filter the sheet does not contain.
    final count = query.activeFilterCount - (query.text.trim().isEmpty ? 0 : 1);
    final button = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final result = await showListingFilterSheet(
          context,
          query: query,
          listings: listings,
          availableUnitTypes: availableUnitTypes,
        );
        if (result != null) onChanged(result);
      },
      child: const _BarButtonShell(child: Icon(Icons.tune_rounded, size: 20)),
    );
    return Tooltip(
      message: 'Filters',
      child: count == 0 ? button : Badge.count(count: count, child: button),
    );
  }
}

class _BarButtonShell extends StatelessWidget {
  const _BarButtonShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: context.nyumba.outline),
        borderRadius: BorderRadius.circular(12),
        color: context.nyumba.surface,
      ),
      child: child,
    );
  }
}

/// Full-width filter sheet for phones, where a draft selection is only applied
/// once the visitor confirms and can see how many homes would remain.
Future<ListingQuery?> showListingFilterSheet(
  BuildContext context, {
  required ListingQuery query,
  required List<Listing> listings,
  required List<String> availableUnitTypes,
}) => showModalBottomSheet<ListingQuery>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _ListingFilterSheet(
    query: query,
    listings: listings,
    availableUnitTypes: availableUnitTypes,
  ),
);

class _ListingFilterSheet extends StatefulWidget {
  const _ListingFilterSheet({
    required this.query,
    required this.listings,
    required this.availableUnitTypes,
  });

  final ListingQuery query;
  final List<Listing> listings;
  final List<String> availableUnitTypes;

  @override
  State<_ListingFilterSheet> createState() => _ListingFilterSheetState();
}

class _ListingFilterSheetState extends State<_ListingFilterSheet> {
  late ListingQuery _draft = widget.query;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.localized(
                    'Filters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: _draft.hasFilters
                      ? () => setState(() => _draft = _draft.cleared())
                      : null,
                  child: const Text.localized('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final field in listingFilterFields(
              query: _draft,
              availableUnitTypes: widget.availableUnitTypes,
              onChanged: (updated) => setState(() => _draft = updated),
            )) ...[field, const SizedBox(height: 12)],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, _draft),
              child: Text(
                copy.showHomesCount(_draft.apply(widget.listings).length),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The filters currently narrowing the list, each removable on its own.
class ActiveFilterChips extends StatelessWidget {
  const ActiveFilterChips({
    required this.query,
    required this.onChanged,
    super.key,
  });

  final ListingQuery query;
  final ValueChanged<ListingQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = query.activeChips;
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final chip in chips)
            InputChip(
              label: chip.localize
                  ? Text.localized(chip.label)
                  : Text(chip.label),
              onDeleted: () => onChanged(chip.removed),
              deleteIcon: const Icon(Icons.close_rounded, size: 16),
              deleteButtonTooltipMessage: context.tr('Remove filter'),
              visualDensity: VisualDensity.compact,
            ),
          TextButton(
            onPressed: () => onChanged(query.cleared()),
            child: const Text.localized('Clear all'),
          ),
        ],
      ),
    );
  }
}
