import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

/// One append-only audit record of an administrative operation. Records are
/// never edited or deleted locally; the server-side audit log remains the
/// authority and this local copy is a queued intent plus history view.
final class AdminActionRecord {
  AdminActionRecord({
    required this.id,
    required this.reference,
    required this.action,
    required this.targetUserId,
    required this.targetName,
    required this.performedBy,
    required this.performedAt,
    required this.createdAt,
    required this.syncMetadata,
  }) {
    validate();
  }

  final String id;

  /// Human-readable audit reference such as `AUD-2026-0042`.
  final String reference;
  final String action;
  final String targetUserId;
  final String targetName;
  final String performedBy;
  final DateTime performedAt;
  final DateTime createdAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'reference': DomainValidation.requiredText(reference, maxLength: 40),
      'action': DomainValidation.requiredText(action, maxLength: 120),
      'targetUserId': DomainValidation.requiredText(
        targetUserId,
        maxLength: 100,
      ),
      'targetName': DomainValidation.requiredText(targetName, maxLength: 120),
      'performedBy': DomainValidation.requiredText(performedBy, maxLength: 120),
    });
  }
}
