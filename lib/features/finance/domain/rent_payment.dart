import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

/// One received rent payment. The record itself is authoritative locally;
/// whether the server has confirmed it is carried by [syncMetadata], never
/// by an optimistic status field.
final class RentPayment {
  RentPayment({
    required this.id,
    required this.receiptNumber,
    required this.landlordId,
    required this.tenantName,
    required this.unitLabel,
    required this.propertyName,
    required this.amountMinor,
    required this.method,
    required this.period,
    required this.paidOn,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.tenancyId,
  }) {
    validate();
  }

  final String id;

  /// Human-readable receipt reference such as `NYB-RCP-00842`.
  final String receiptNumber;
  final String landlordId;
  final String? tenancyId;
  final String tenantName;
  final String unitLabel;
  final String propertyName;
  final int amountMinor;
  final String method;

  /// Billing period the payment covers, such as `July 2026`.
  final String period;
  final DateTime paidOn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'receiptNumber': DomainValidation.requiredText(
        receiptNumber,
        maxLength: 40,
      ),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'tenantName': DomainValidation.requiredText(tenantName, maxLength: 120),
      'unitLabel': DomainValidation.requiredText(unitLabel, maxLength: 60),
      'propertyName': DomainValidation.requiredText(
        propertyName,
        maxLength: 120,
      ),
      'amountMinor': DomainValidation.positiveMinorUnits(amountMinor),
      'method': DomainValidation.requiredText(method, maxLength: 60),
      'period': DomainValidation.requiredText(period, maxLength: 40),
    });
  }
}

final class RecordRentPaymentInput {
  const RecordRentPaymentInput({
    required this.tenancyId,
    required this.amountMinor,
    required this.method,
    this.period,
  });

  final String tenancyId;
  final int amountMinor;
  final String method;

  /// Defaults to the month of the recording date when omitted.
  final String? period;
}
