import 'package:flutter/material.dart' hide Text, Tooltip;

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/localization/app_localizations_adapter.dart';
import '../../../../core/localization/localized_material.dart';
import '../../../../core/presentation/cloud_status_badge.dart';
import '../../../../core/presentation/language_menu_button.dart';
import '../../../../core/presentation/nyumba_logo.dart';
import '../../../../core/presentation/responsive.dart';

/// The navy the public page opens on. The top bar and the hero share it so
/// they read as one band rather than a white strip stacked on a coloured box.
const heroGradient = LinearGradient(
  begin: AlignmentDirectional.topStart,
  end: AlignmentDirectional.bottomEnd,
  colors: [NyumbaColors.navyDark, NyumbaColors.midnightNavy],
);

/// Re-resolves the theme for content sitting on the navy band.
///
/// The top bar reuses shared widgets — the cloud badge, the language menu —
/// that colour themselves from the palette and the colour scheme. Rather than
/// teaching each of them about dark backgrounds, this swaps in the on-dark
/// variants of the few tokens they read, so they keep their own logic and
/// simply resolve to legible colours here.
///
/// Every override below has to be unconditional: the band is navy in both
/// themes, so borrowing whatever the dark theme happens to resolve to only
/// looks right half the time. The overrides that were once left out — the
/// app bar's own foreground, the badge fills — read as invisible in light
/// mode, where the underlying tokens are ink on near-white.
class OnHeroSurface extends StatelessWidget {
  const OnHeroSurface({required this.child, super.key});

  final Widget child;

  /// Chip fill and border for badges on the band. Tone stays in the
  /// foreground; the fill is the same faint white wash whatever the tone, so
  /// it sits on the gradient instead of punching a pale hole in it.
  static const _chipFill = Color(0x1FFFFFFF);
  static const _chipBorder = Color(0x59FFFFFF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.nyumba;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          outline: const Color(0x66FFFFFF),
        ),
        iconTheme: theme.iconTheme.copyWith(color: Colors.white),
        // `AppBar` resolves its title, toolbar text and action icons from the
        // app bar theme rather than the ambient icon and text themes, so the
        // white above never reaches them on its own.
        appBarTheme: theme.appBarTheme.copyWith(
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            color: Colors.white,
          ),
          toolbarTextStyle: (theme.appBarTheme.toolbarTextStyle ??
                  theme.textTheme.bodyMedium)
              ?.copyWith(color: Colors.white),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: NyumbaColors.navyOnDark,
            textStyle: theme.textTheme.labelLarge,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0x8CFFFFFF)),
            minimumSize: const Size(44, 46),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        extensions: [
          palette.copyWith(
            ink: Colors.white,
            mutedInk: NyumbaColors.navyOnDark,
            midnightNavy: NyumbaColors.navyOnDark,
            sageDark: NyumbaColors.sageOnDark,
            terracottaDark: const Color(0xFFEBC383),
            danger: const Color(0xFFE58974),
            outline: const Color(0x66FFFFFF),
            navyTint: _chipFill,
            navyBorder: _chipBorder,
            sageTint: _chipFill,
            sageBorder: _chipBorder,
            goldTint: _chipFill,
            goldBorder: _chipBorder,
            dangerTint: _chipFill,
            dangerBorder: _chipBorder,
            neutralTint: _chipFill,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Public navigation: brand, in-page links, and the two ways in — list a space
/// or sign in.
class MarketplaceTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MarketplaceTopBar({
    required this.signedIn,
    required this.accountLabel,
    required this.onAccount,
    required this.onBrowseHomes,
    required this.onForLandlords,
    super.key,
  });

  final bool signedIn;
  final String accountLabel;
  final VoidCallback onAccount;
  final VoidCallback onBrowseHomes;
  final VoidCallback onForLandlords;

  @override
  Size get preferredSize => const Size.fromHeight(78);

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final compact = context.isCompact;
    // The bar lays its actions out in a plain row, so anything that does not
    // fit overflows rather than wrapping. The landlord call to action is the
    // widest item and the last one worth having, so it waits for a window with
    // room for it beside the in-page links.
    final roomForListCta = MediaQuery.sizeOf(context).width >= 1400;
    return OnHeroSurface(
      child: Builder(
        builder: (context) => AppBar(
          toolbarHeight: 78,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: heroGradient),
          ),
          titleSpacing: compact ? 16 : 32,
          title: NyumbaLogo(compact: compact, height: 42, onDarkSurface: true),
          actions: [
            if (context.isExpanded) ...[
              TextButton(
                onPressed: onBrowseHomes,
                child: Text(copy.browseHomesNav),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onForLandlords,
                child: Text(copy.forLandlords),
              ),
              const SizedBox(width: 14),
            ],
            const CloudStatusBadge(),
            SizedBox(width: compact ? 8 : 14),
            const LanguageMenuButton(compact: true),
            SizedBox(width: compact ? 8 : 14),
            if (!signedIn && roomForListCta) ...[
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: NyumbaColors.sageGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(44, 46),
                ),
                onPressed: onAccount,
                child: Text(copy.listYourSpace),
              ),
              const SizedBox(width: 10),
            ],
            Padding(
              padding: EdgeInsetsDirectional.only(end: compact ? 12 : 30),
              child: OutlinedButton(
                onPressed: onAccount,
                child: Text.localized(accountLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
