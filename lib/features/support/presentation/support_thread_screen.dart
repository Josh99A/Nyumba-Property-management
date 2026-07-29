import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/surface.dart';
import '../../tenant_portal/presentation/widgets/tenant_components.dart';
import '../application/support_providers.dart';
import 'support_composer_sheet.dart';
import 'support_thread_view.dart';

/// One landlord-side conversation, as a page.
class SupportThreadScreen extends ConsumerWidget {
  const SupportThreadScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(supportTicketProvider(ticketId));

    return TenantPage(
      title: 'Conversation',
      secondaryAction: AsyncActionButton(
        style: AsyncActionStyle.text,
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        showBusyIndicator: false,
        onPressed: () async => context.go('/support'),
        child: const Text.localized('All conversations'),
      ),
      children: [
        ticket.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => NyumbaSurface(
            child: Text.localized(
              'This conversation could not be opened.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          data: (value) => value == null
              // Reachable from a push notification that arrived before the pull
              // did, so this is a wait rather than an error — and the way out is
              // an action, not a dead end.
              ? NyumbaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.localized(
                        'This conversation is not on this device yet.',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text.localized(
                        'It will appear once your workspace finishes syncing.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      AsyncActionButton(
                        style: AsyncActionStyle.outlined,
                        showBusyIndicator: false,
                        onPressed: () async => showSupportComposer(context),
                        child: const Text.localized('Message support'),
                      ),
                    ],
                  ),
                )
              : SupportThreadView(ticket: value, asSupportAgent: false),
        ),
      ],
    );
  }
}
