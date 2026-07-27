import 'package:nyumba_property_management/core/domain/sync_metadata.dart';

/// What kind of signal this submission carries.
///
/// The split matters because the two behave differently: [nps] is throttled to
/// once a quarter and produces a number to trend, while [freeform] is never
/// throttled because suppressing a bug report to protect a survey cadence is
/// exactly backwards.
enum PlatformFeedbackKind { nps, freeform }

enum PlatformFeedbackCategory {
  easeOfUse,
  valueForMoney,
  support,
  bug,
  featureRequest,
}

final class PlatformFeedback {
  const PlatformFeedback({
    required this.id,
    required this.kind,
    required this.appVersion,
    required this.platform,
    required this.submittedAt,
    required this.syncMetadata,
    this.score,
    this.comment,
    this.category,
  });

  final String id;
  final PlatformFeedbackKind kind;

  /// 0–10 recommendation score. Present only for [PlatformFeedbackKind.nps].
  final int? score;
  final String? comment;
  final PlatformFeedbackCategory? category;

  /// Captured automatically. Feedback without a build and platform is a
  /// sentiment; with them it is a reproducible report.
  final String appVersion;
  final String platform;

  final DateTime submittedAt;
  final SyncMetadata syncMetadata;

  /// Standard NPS banding. Detractors on a paid tier are the churn signal this
  /// whole surface exists to surface.
  bool get isDetractor => score != null && score! <= 6;
  bool get isPromoter => score != null && score! >= 9;
}
