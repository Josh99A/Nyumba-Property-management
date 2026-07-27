import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/feedback_providers.dart';

/// Device-local NPS prompt history for the signed-in landlord.
///
/// Only the *snooze* lives here. The rule that actually protects people — a
/// landlord may not be asked again within 90 days of answering — is enforced by
/// the server against `lastNpsSubmittedAt`, where no reinstall can reset it and
/// no client can bypass it. What a device tracks is the shorter "you already
/// declined this once, leave them alone for a month" window, which is not worth
/// a Firestore write per dismissal.
final class FeedbackPromptStore {
  const FeedbackPromptStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _keyFor(String userId) => 'nyumba.feedback-prompt.v1.$userId';

  Future<FeedbackPromptEligibility> read(String userId) async {
    try {
      final raw = await _storage.read(key: _keyFor(userId));
      if (raw == null) {
        return const FeedbackPromptEligibility(
          optedOut: false,
          lastPromptedAt: null,
          lastSubmittedAt: null,
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return const FeedbackPromptEligibility(
          optedOut: false,
          lastPromptedAt: null,
          lastSubmittedAt: null,
        );
      }
      return FeedbackPromptEligibility(
        optedOut: decoded['optedOut'] == true,
        lastPromptedAt: _date(decoded['lastPromptedAt']),
        lastSubmittedAt: _date(decoded['lastSubmittedAt']),
      );
    } on Object {
      // Worst case of failing open here is one extra prompt, against the
      // certainty of a broken dashboard if this threw. Fail toward the default.
      return const FeedbackPromptEligibility(
        optedOut: false,
        lastPromptedAt: null,
        lastSubmittedAt: null,
      );
    }
  }

  Future<void> write(String userId, FeedbackPromptEligibility state) async {
    try {
      await _storage.write(
        key: _keyFor(userId),
        value: jsonEncode(<String, Object?>{
          'optedOut': state.optedOut,
          'lastPromptedAt': state.lastPromptedAt?.toUtc().toIso8601String(),
          'lastSubmittedAt': state.lastSubmittedAt?.toUtc().toIso8601String(),
        }),
      );
    } on Object {
      // Secure storage is unavailable in restricted browser contexts.
    }
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
}
