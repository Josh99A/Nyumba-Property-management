import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/platform_feedback.dart';

/// What the landlord just accomplished that makes this a good moment to ask.
///
/// NPS is asked after a *success*, never after an error and never on launch. A
/// score collected the moment something went wrong measures the incident; a
/// score collected right after the product did its job measures the product.
enum FeedbackPromptMilestone {
  /// The landlord has recorded ten rent payments. The product has demonstrably
  /// done the thing they subscribed for.
  paymentsRecorded,

  /// A listing they published received its first application.
  firstApplication,

  /// Thirty days on a paid plan, as the catch-all for accounts that reach
  /// neither milestone but are clearly getting value.
  establishedSubscription,
}

/// Device-side view of the server-owned NPS cadence.
///
/// The counters live on `landlordAccounts` because a cadence tracked only on the
/// device resets on reinstall and on every new device, so the same landlord gets
/// asked again and again — the fastest way to make people resent a prompt. This
/// mirrors what the server already decided.
final class FeedbackPromptEligibility {
  const FeedbackPromptEligibility({
    required this.optedOut,
    required this.lastPromptedAt,
    required this.lastSubmittedAt,
  });

  final bool optedOut;
  final DateTime? lastPromptedAt;
  final DateTime? lastSubmittedAt;

  /// Mirrors FEEDBACK_NPS_COOLDOWN_DAYS on the server.
  static const Duration cooldown = Duration(days: 90);

  /// A declined prompt earns a shorter rest than an answered one; the landlord
  /// may simply have been mid-task.
  static const Duration snooze = Duration(days: 30);

  bool allows(DateTime now) {
    if (optedOut) return false;
    if (lastSubmittedAt != null &&
        now.difference(lastSubmittedAt!) < cooldown) {
      return false;
    }
    if (lastPromptedAt != null && now.difference(lastPromptedAt!) < snooze) {
      return false;
    }
    return true;
  }
}

final submitFeedbackProvider = Provider<SubmitFeedback>(SubmitFeedback.new);

class SubmitFeedback {
  const SubmitFeedback(this._ref);

  final Ref _ref;

  Future<PlatformFeedback> call({
    required PlatformFeedbackKind kind,
    required String appVersion,
    required String platform,
    int? score,
    String? comment,
    PlatformFeedbackCategory? category,
  }) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.feedback.submit(
      kind: kind,
      appVersion: appVersion,
      platform: platform,
      score: score,
      comment: comment,
      category: category,
    );
  }
}

/// This build's version string, for attaching to feedback.
///
/// A report without a build number is a sentiment; with one it is reproducible.
/// Cached by Riverpod so the platform channel is hit once per session rather
/// than once per sheet.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final package = await PackageInfo.fromPlatform();
    return '${package.version}+${package.buildNumber}';
  } on Object {
    // Never block the feedback form on a platform channel. An unknown version
    // is far better than a form that will not open.
    return 'unknown';
  }
});
