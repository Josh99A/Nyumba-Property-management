import 'package:flutter/material.dart' hide Text, Tooltip;

import '../../../../core/presentation/motion.dart';
import '../../domain/listing.dart';
import 'listing_result_card.dart';

/// Gap between result cards, both across a row and between rows.
const double listingResultsGap = 22.0;

/// Cards per row at [width].
///
/// Three is the most a 1240px content column seats before cards get too narrow
/// to read a title in two lines; one is the only honest answer on a phone.
int listingGridColumns(double width) => width >= 1000
    ? 3
    : width >= 620
    ? 2
    : 1;

/// One row of the results grid.
///
/// Extracted because the lazy sliver, the bounded featured grid, and the
/// loading skeleton must produce identical geometry — a row that sizes its
/// cards differently in any one of them shows up as the grid twitching when
/// results load.
class _ListingRow extends StatelessWidget {
  const _ListingRow({
    required this.children,
    required this.columns,
    required this.last,
  });

  final List<Widget> children;
  final int columns;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : listingResultsGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(width: listingResultsGap),
            Expanded(child: child),
          ],
          // Keeps the cards in a part-filled row the same width as every full
          // row above it, instead of stretching them across the gap.
          for (var slot = children.length; slot < columns; slot++) ...[
            const SizedBox(width: listingResultsGap),
            const Expanded(child: SizedBox.shrink()),
          ],
        ],
      ),
    );
  }
}

/// The results grid, built a row at a time.
///
/// A single [Wrap] would lay out every card on first paint, which starts a
/// photo download for homes the visitor has not scrolled anywhere near. Rows
/// in a [SliverList] keep the same layout and only build what is on screen.
class ListingResultsSliver extends StatelessWidget {
  const ListingResultsSliver({
    required this.listings,
    required this.onOpen,
    super.key,
  });

  final List<Listing> listings;
  final ValueChanged<Listing> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = listingGridColumns(constraints.crossAxisExtent);
        final rows = (listings.length + columns - 1) ~/ columns;
        return SliverList.builder(
          itemCount: rows,
          itemBuilder: (context, row) {
            final first = row * columns;
            final last = (first + columns).clamp(0, listings.length);
            return _ListingRow(
              columns: columns,
              last: row == rows - 1,
              children: [
                for (var index = first; index < last; index++)
                  FadeSlideIn(
                    delay: NyumbaMotion.stagger(index - first),
                    child: ListingResultCard(
                      listing: listings[index],
                      onOpen: () => onOpen(listings[index]),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A bounded grid for a fixed handful of listings.
///
/// Used where the count is known small and the whole section is meant to be
/// seen at once — the home page's featured strip — so laziness would buy
/// nothing and a box widget composes more easily than a sliver.
class ListingResultsGrid extends StatelessWidget {
  const ListingResultsGrid({
    required this.listings,
    required this.onOpen,
    super.key,
  });

  final List<Listing> listings;
  final ValueChanged<Listing> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = listingGridColumns(constraints.maxWidth);
        final rows = (listings.length + columns - 1) ~/ columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < rows; row++)
              _ListingRow(
                columns: columns,
                last: row == rows - 1,
                children: [
                  for (
                    var index = row * columns;
                    index < (row * columns + columns).clamp(0, listings.length);
                    index++
                  )
                    FadeSlideIn(
                      delay: NyumbaMotion.stagger(index),
                      child: ListingResultCard(
                        listing: listings[index],
                        onOpen: () => onOpen(listings[index]),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Grid-shaped stand-in while the catalogue loads, so the results area keeps
/// its final layout instead of collapsing to a spinner and jumping.
class ListingResultsSkeleton extends StatelessWidget {
  const ListingResultsSkeleton({super.key, this.rows = 1});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = listingGridColumns(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < rows; row++)
              _ListingRow(
                columns: columns,
                last: row == rows - 1,
                children: [
                  for (var index = 0; index < columns; index++)
                    const ListingCardSkeleton(),
                ],
              ),
          ],
        );
      },
    );
  }
}
