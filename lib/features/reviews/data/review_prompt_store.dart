import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/review_prompt_policy.dart';

/// Device-local record of when a review prompt was last raised, per lease.
///
/// Deliberately not server state, unlike the landlord NPS cadence. That one has
/// to survive a reinstall because a landlord is a long-lived paying account
/// being asked a recurring survey question; this one governs a single
/// interruption about a single tenancy, and losing it on a new device costs at
/// most one extra prompt. Paying a Firestore write per dismissal to prevent that
/// would be worse than the problem.
final class ReviewPromptStore {
  const ReviewPromptStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _keyFor(String leaseId) => 'nyumba.review-prompt.v1.$leaseId';

  Future<ReviewPromptState> read(String leaseId) async {
    try {
      final raw = await _storage.read(key: _keyFor(leaseId));
      if (raw == null) return const ReviewPromptState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const ReviewPromptState();
      final lastPrompted = decoded['lastPromptedAt'];
      return ReviewPromptState(
        lastPromptedAt: lastPrompted is String
            ? DateTime.tryParse(lastPrompted)?.toUtc()
            : null,
        dismissals: decoded['dismissals'] is int
            ? decoded['dismissals']! as int
            : 0,
        optedOut: decoded['optedOut'] == true,
      );
    } on Object {
      // Unreadable prompt history must never break a screen. The cost of
      // guessing wrong is one extra prompt, so fail toward the default.
      return const ReviewPromptState();
    }
  }

  Future<void> write(String leaseId, ReviewPromptState state) async {
    try {
      await _storage.write(
        key: _keyFor(leaseId),
        value: jsonEncode(<String, Object?>{
          'lastPromptedAt': state.lastPromptedAt?.toUtc().toIso8601String(),
          'dismissals': state.dismissals,
          'optedOut': state.optedOut,
        }),
      );
    } on Object {
      // Secure storage is unavailable in some restricted browser contexts.
      // Losing the record is non-fatal for the same reason as above.
    }
  }
}
