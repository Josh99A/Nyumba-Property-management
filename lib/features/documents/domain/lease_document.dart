import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum LeaseDocumentType { invoice, receipt, lease, notice }

extension LeaseDocumentTypeX on LeaseDocumentType {
  String get label => switch (this) {
    LeaseDocumentType.invoice => 'Invoice',
    LeaseDocumentType.receipt => 'Receipt',
    LeaseDocumentType.lease => 'Lease',
    LeaseDocumentType.notice => 'Notice',
  };
}

/// A generated or received document belonging to the landlord's workspace.
/// The file itself is rendered on demand from this record's data; only the
/// metadata is synchronized.
final class LeaseDocument {
  LeaseDocument({
    required this.id,
    required this.number,
    required this.landlordId,
    required this.type,
    required this.recipient,
    required this.propertyName,
    required this.unitLabel,
    required this.amountMinor,
    required this.statusLabel,
    required this.issuedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.tenantId,
  }) {
    validate();
  }

  final String id;

  /// Human-readable document number such as `RCT-2026-0184`.
  final String number;
  final String landlordId;
  final String? tenantId;
  final LeaseDocumentType type;
  final String recipient;
  final String propertyName;
  final String unitLabel;
  final int amountMinor;

  /// Display status such as `Paid`, `Due`, or `Queued to send`.
  final String statusLabel;
  final DateTime issuedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'number': DomainValidation.requiredText(number, maxLength: 40),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'recipient': DomainValidation.requiredText(recipient, maxLength: 120),
      'propertyName': DomainValidation.requiredText(
        propertyName,
        maxLength: 120,
      ),
      'unitLabel': DomainValidation.requiredText(unitLabel, maxLength: 60),
      'amountMinor': DomainValidation.positiveMinorUnits(
        amountMinor,
        allowZero: true,
      ),
      'statusLabel': DomainValidation.requiredText(statusLabel, maxLength: 40),
    });
  }
}

final class CreateLeaseDocumentInput {
  const CreateLeaseDocumentInput({
    required this.landlordId,
    required this.type,
    required this.recipient,
    required this.propertyName,
    required this.unitLabel,
    required this.statusLabel,
    this.amountMinor = 0,
    this.tenantId,
  });

  final String landlordId;
  final LeaseDocumentType type;
  final String recipient;
  final String propertyName;
  final String unitLabel;
  final String statusLabel;
  final int amountMinor;
  final String? tenantId;
}
