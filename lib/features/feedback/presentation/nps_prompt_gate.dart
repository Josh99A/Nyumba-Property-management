import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../application/feedback_providers.dart';
import '../data/feedback_prompt_store.dart';
import 'feedback_sheet.dart';

/// Raises the NPS prompt after a milestone, or renders nothing.
///
/// Placed on the landlord dashboard rather than triggered at launch. The
/// distinction is the whole design:
///
///  - **Never on launch.** A prompt that fires while someone is on their way to
///    do something is the pattern people learn to dismiss without reading, and
///    it attaches the question to nothing.
///  - **Only after a success.** Ten payments recorded, or a listing's first
///    application, means the product has demonstrably done the job they pay for.
///    A score collected right after something went wrong measures the incident,
///    not the product.
///  - **Never after an error**, and never on the subscription or billing
///    screens, where the answer would be about price rather than the product.
///
/// Everything after "is this a milestone" — the 30-day snooze, the opt-out, the
/// server's 90-day cooldown — belongs to [FeedbackPromptEligibility] and the
/// `feedback.submit` handler.
class NpsPromptGate extends ConsumerStatefulWidget {
  const NpsPromptGate({
    required this.paymentsRecorded,
    required this.hasApplications,
    required this.accountAgeDays,
    super.key,
  });

  final int paymentsRecorded;
  final bool hasApplications;
  final int accountAgeDays;

  @override
  ConsumerState<NpsPromptGate> createState() => _NpsPromptGateState();
}

class _NpsPromptGateState extends ConsumerState<NpsPromptGate> {
  bool _checked = false;

  FeedbackPromptMilestone? get _milestone {
    if (widget.paymentsRecorded >= 10) {
      return FeedbackPromptMilestone.paymentsRecorded;
    }
    if (widget.hasApplications) return FeedbackPromptMilestone.firstApplication;
    if (widget.accountAgeDays >= 30) {
      return FeedbackPromptMilestone.establishedSubscription;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      _checked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
    }
    return const SizedBox.shrink();
  }

  Future<void> _maybeAsk() async {
    if (!mounted) return;
    final milestone = _milestone;
    final userId = ref.read(sessionControllerProvider)?.userId;
    final version = ref.read(appVersionProvider).value;
    if (milestone == null || userId == null || version == null) return;

    const store = FeedbackPromptStore();
    final state = await store.read(userId);
    if (!state.allows(DateTime.now().toUtc())) return;
    if (!mounted) return;

    // Recorded before the sheet opens: if the app is killed mid-prompt the ask
    // still counts as made, so a crash loop cannot become a nag loop.
    await store.write(
      userId,
      FeedbackPromptEligibility(
        optedOut: state.optedOut,
        lastPromptedAt: DateTime.now().toUtc(),
        lastSubmittedAt: state.lastSubmittedAt,
      ),
    );
    if (!mounted) return;

    await showNpsSheet(
      context,
      appVersion: version,
      milestone: milestone,
      onDismissed: ({required permanent}) async {
        final current = await store.read(userId);
        await store.write(
          userId,
          FeedbackPromptEligibility(
            // Two declines is an answer. Honouring it costs one boolean and
            // buys the difference between a prompt people tolerate and one
            // they uninstall over.
            optedOut: permanent || current.lastPromptedAt != null,
            lastPromptedAt: current.lastPromptedAt,
            lastSubmittedAt: current.lastSubmittedAt,
          ),
        );
      },
    );
  }
}
