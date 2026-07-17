import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/locale_controller.dart';
import '../localization/app_language.dart';
import '../localization/localized_material.dart';
import '../localization/nyumba_localizations.dart';

class LanguageMenuButton extends ConsumerWidget {
  const LanguageMenuButton({
    super.key,
    this.expanded = false,
    this.compact = false,
  });

  final bool expanded;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(localePreferenceProvider);
    return PopupMenuButton<AppLanguage>(
      tooltip: context.l10n.key('chooseLanguage'),
      initialValue: selected,
      onSelected: (language) async {
        try {
          await ref.read(localePreferenceProvider.notifier).select(language);
        } on Object {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text.localized(context.l10n.key('languageSaveFailed')),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        for (final language in AppLanguage.values)
          PopupMenuItem(
            value: language,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: language == selected
                      ? const Icon(Icons.check_rounded, size: 19)
                      : null,
                ),
                const SizedBox(width: 10),
                Text.localized(language.nativeName),
              ],
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: context.l10n.key('chooseLanguage'),
        child: Container(
          width: expanded ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 11,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              const Icon(Icons.translate_rounded, size: 20),
              if (!compact) ...[
                const SizedBox(width: 9),
                if (expanded)
                  Expanded(child: Text.localized(selected.nativeName))
                else
                  Text.localized(selected.nativeName),
              ],
              if (!compact) const Icon(Icons.arrow_drop_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
