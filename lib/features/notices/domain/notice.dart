import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum NoticeStatus { draft, queued }

enum NoticeAudienceType { allActiveTenants, property, lease }

/// A landlord-to-tenant notice. Local records are drafts or queued sends; the
/// server owns actual delivery, so no local state ever claims `sent`.
final class Notice {
  Notice({
    required this.id,
    required this.reference,
    required this.landlordId,
    required this.title,
    required this.body,
    required this.audience,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.audienceType = NoticeAudienceType.allActiveTenants,
    this.audienceId,
  }) {
    validate();
  }

  final String id;

  /// Human-readable reference such as `NTC-2026-014`.
  final String reference;
  final String landlordId;
  final String title;
  final String body;

  /// Display audience such as `All tenants` or `Sunset Apartments`.
  final String audience;
  final NoticeAudienceType audienceType;
  final String? audienceId;
  final NoticeStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'reference': DomainValidation.requiredText(reference, maxLength: 40),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'title': DomainValidation.requiredText(title, maxLength: 120),
      'body': DomainValidation.requiredText(body, maxLength: 4000),
      'audience': DomainValidation.requiredText(audience, maxLength: 120),
      'audienceId':
          audienceType != NoticeAudienceType.allActiveTenants &&
              (audienceId == null || audienceId!.trim().isEmpty)
          ? 'is required for a scoped audience'
          : null,
    });
  }
}

final class CreateNoticeInput {
  const CreateNoticeInput({
    required this.landlordId,
    required this.title,
    required this.body,
    required this.audience,
    this.audienceType = NoticeAudienceType.allActiveTenants,
    this.audienceId,
    this.queueForSending = true,
  });

  final String landlordId;
  final String title;
  final String body;
  final String audience;
  final NoticeAudienceType audienceType;
  final String? audienceId;
  final bool queueForSending;
}
