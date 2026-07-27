import 'package:flutter/material.dart' hide Text, Tooltip;

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/localization/app_localizations_adapter.dart';
import '../../../../core/localization/localized_material.dart';
import '../../../../core/presentation/motion.dart';
import '../../../../core/presentation/nyumba_logo.dart';
import '../../../../core/presentation/responsive.dart';
import '../../../../core/presentation/surface.dart';
import 'marketplace_top_bar.dart';

/// Full-bleed section band: brand background, centred column, page gutters.
///
/// Every public section repeats this shape, so it lives once here instead of
/// being spelled out with a slightly different max width in each one.
class MarketplaceBand extends StatelessWidget {
  const MarketplaceBand({
    required this.child,
    super.key,
    this.color,
    this.gradient,
    this.background,
    this.maxWidth = 1240,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color? color;
  final Gradient? gradient;

  /// Painted behind the band's content, sized to it.
  final Widget? background;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: context.pageGutter,
            end: context.pageGutter,
          ).add(padding),
          child: child,
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color ?? context.nyumba.surface : null,
        gradient: gradient,
      ),
      child: background == null
          ? content
          : Stack(
              children: [
                Positioned.fill(child: background!),
                content,
              ],
            ),
    );
  }
}

/// Horizontal inset that lines a bare sliver up with [MarketplaceBand]'s
/// content column.
///
/// The results grid has to be a lazy sliver rather than a box inside a band,
/// so it needs the band's centring arithmetic without the band itself.
double marketplaceBandInset(BuildContext context, {double maxWidth = 1240}) {
  final overflow = (MediaQuery.sizeOf(context).width - maxWidth) / 2;
  return context.pageGutter + (overflow > 0 ? overflow : 0);
}

/// Eyebrow, headline, and optional lead-in — the rhythm every marketing
/// section on the page shares.
class MarketplaceSectionHeading extends StatelessWidget {
  const MarketplaceSectionHeading({
    required this.eyebrow,
    required this.title,
    super.key,
    this.subtitle,
    this.centered = false,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          eyebrow,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: context.nyumba.sageDark,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: context.isCompact ? 30 : 38,
            height: 1.15,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              subtitle!,
              textAlign: textAlign,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ],
    );
  }
}

/// The opening band: one promise, one search, and the shortcuts most visitors
/// actually want.
class MarketplaceHero extends StatelessWidget {
  const MarketplaceHero({
    required this.searchBar,
    required this.assurances,
    required this.quickLocations,
    required this.onLocationSelected,
    super.key,
  });

  final Widget searchBar;

  /// Short, factual lines shown under the search — result counts and the
  /// promises the product actually keeps.
  final List<String> assurances;

  /// Neighbourhoods drawn from the live catalogue, so a tap always lands on
  /// homes that exist.
  final List<String> quickLocations;
  final ValueChanged<String> onLocationSelected;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final compact = context.isCompact;
    return MarketplaceBand(
      maxWidth: 1320,
      gradient: heroGradient,
      // A photograph under a near-opaque navy wash: enough to give the band
      // depth, never enough to put white text near the contrast floor.
      background: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/listings/generated-modern-apartment-exterior.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF20B294F), Color(0xE8123A6F)],
              ),
            ),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: compact ? 44 : 84,
        bottom: compact ? 44 : 84,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FadeSlideIn(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Text.localized(
                'Find a place that feels like home.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontSize: compact ? 36 : 56,
                  height: 1.06,
                  letterSpacing: compact ? -.9 : -1.6,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 14 : 18),
          FadeSlideIn(
            delay: NyumbaMotion.stagger(1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Text(
                copy.browseVerifiedHomes,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: NyumbaColors.navyOnDark,
                  fontSize: compact ? 17 : 19,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 26 : 34),
          FadeSlideIn(delay: NyumbaMotion.stagger(2), child: searchBar),
          if (assurances.isNotEmpty) ...[
            const SizedBox(height: 20),
            _HeroAssurances(items: assurances),
          ],
          if (quickLocations.isNotEmpty) ...[
            SizedBox(height: compact ? 26 : 34),
            _HeroLocations(
              label: copy.popularLocations,
              locations: quickLocations,
              onSelected: onLocationSelected,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroAssurances extends StatelessWidget {
  const _HeroAssurances({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: NyumbaColors.navyOnDark);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0)
            Text('·', style: style?.copyWith(color: const Color(0x8CDCE7F4))),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: NyumbaColors.sageOnDark,
              ),
              const SizedBox(width: 6),
              Text(item, style: style),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroLocations extends StatelessWidget {
  const _HeroLocations({
    required this.label,
    required this.locations,
    required this.onSelected,
  });

  final String label;
  final List<String> locations;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xB3DCE7F4),
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final location in locations)
              _HeroLocationChip(
                label: location,
                onTap: () => onSelected(location),
              ),
          ],
        ),
      ],
    );
  }
}

class _HeroLocationChip extends StatelessWidget {
  const _HeroLocationChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x1FFFFFFF),
      shape: const StadiumBorder(side: BorderSide(color: Color(0x4DDCE7F4))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Three promises, stated once, directly under the hero.
class MarketplaceAssuranceBand extends StatelessWidget {
  const MarketplaceAssuranceBand({super.key});

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final items = <(IconData, String, String)>[
      (
        Icons.verified_user_outlined,
        copy.trustActiveListings,
        copy.benefitVerifiedLandlords,
      ),
      (
        Icons.forum_outlined,
        copy.trustDirectLandlordContact,
        copy.benefitNoAgentFees,
      ),
      (
        Icons.offline_pin_outlined,
        copy.trustWorksOffline,
        copy.benefitBrowseOffline,
      ),
    ];

    return MarketplaceBand(
      color: context.nyumba.softIvory,
      maxWidth: 1180,
      padding: EdgeInsets.only(
        top: context.isCompact ? 44 : 68,
        bottom: context.isCompact ? 44 : 68,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 820 ? 3 : 1;
          const gap = 20.0;
          final width = gridItemWidth(
            constraints.maxWidth,
            columns: columns,
            gap: gap,
          );
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: context.nyumba.sageTint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.$1,
                          color: context.nyumba.sageDark,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.$3,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Heading above the results grid: what is being shown, and how many.
class MarketplaceResultsHeader extends StatelessWidget {
  const MarketplaceResultsHeader({required this.resultSummary, super.key});

  final String? resultSummary;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MarketplaceSectionHeading(
              eyebrow: copy.availableHomes,
              title: copy.publicFreshSpaces,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  size: 20,
                  color: context.nyumba.sageDark,
                ),
                const SizedBox(width: 8),
                Text(
                  copy.savedForOfflineBrowsing,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.nyumba.sageDark,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (resultSummary != null) ...[
          const SizedBox(height: 12),
          Text(
            resultSummary!,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: context.nyumba.sageDark),
          ),
        ],
      ],
    );
  }
}

/// Image on one side, the pitch on the other — alternated down the page so
/// the tenant and landlord stories read as a pair rather than a wall.
class MarketplaceFeatureRow extends StatelessWidget {
  const MarketplaceFeatureRow({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.bullets,
    required this.action,
    required this.imageAsset,
    required this.imageFirst,
    super.key,
    this.background,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<String> bullets;
  final Widget action;
  final String imageAsset;

  /// True places the photograph before the copy in reading order.
  final bool imageFirst;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        MarketplaceSectionHeading(
          eyebrow: eyebrow,
          title: title,
          subtitle: description,
        ),
        const SizedBox(height: 20),
        for (final bullet in bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: context.nyumba.sageGreen,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bullet,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        Align(alignment: AlignmentDirectional.centerStart, child: action),
      ],
    );

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.asset(
          imageAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
    );

    return MarketplaceBand(
      color: background,
      padding: EdgeInsets.only(
        top: context.isCompact ? 48 : 76,
        bottom: context.isCompact ? 48 : 76,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 880) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [image, const SizedBox(height: 28), text],
            );
          }
          final columns = imageFirst
              ? [
                  Expanded(child: image),
                  const SizedBox(width: 64),
                  Expanded(child: text),
                ]
              : [
                  Expanded(child: text),
                  const SizedBox(width: 64),
                  Expanded(child: image),
                ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: columns,
          );
        },
      ),
    );
  }
}

class MarketplaceFooter extends StatelessWidget {
  const MarketplaceFooter({
    required this.onBrowseHomes,
    required this.onAccount,
    required this.accountLabel,
    super.key,
  });

  final VoidCallback onBrowseHomes;
  final VoidCallback onAccount;
  final String accountLabel;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final footerText = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: NyumbaColors.navyOnDark);
    return MarketplaceBand(
      gradient: const LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [NyumbaColors.midnightNavy, NyumbaColors.navyDark],
      ),
      padding: const EdgeInsets.only(top: 56, bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 64,
            runSpacing: 32,
            alignment: WrapAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const NyumbaLogo(height: 42, onDarkSurface: true),
                    const SizedBox(height: 16),
                    Text(copy.publicFooterDescription, style: footerText),
                  ],
                ),
              ),
              _FooterLinkGroup(
                title: copy.forTenants,
                children: [
                  TextButton(
                    onPressed: onBrowseHomes,
                    child: Text(copy.browseHomesNav),
                  ),
                ],
              ),
              _FooterLinkGroup(
                title: copy.forLandlords,
                children: [
                  TextButton(onPressed: onAccount, child: Text(accountLabel)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: NyumbaColors.sageOnDark,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text.localized('Kampala, Uganda', style: footerText),
                ],
              ),
            ],
          ),
          const SizedBox(height: 34),
          const Divider(color: Color(0x4DDCE7F4)),
          const SizedBox(height: 18),
          Text.localized(
            'Nyumba Property Management · Kampala, Uganda',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFFAFC0D5)),
          ),
        ],
      ),
    );
  }
}

class _FooterLinkGroup extends StatelessWidget {
  const _FooterLinkGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style:
          Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.white) ??
          const TextStyle(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          for (final child in children)
            TextButtonTheme(
              data: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: NyumbaColors.navyOnDark,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: const Size(0, 36),
                ),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

class MarketplaceEmptyState extends StatelessWidget {
  const MarketplaceEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: [
            Icon(icon, size: 44, color: context.nyumba.mutedInk),
            const SizedBox(height: 14),
            Text.localized(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text.localized(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
