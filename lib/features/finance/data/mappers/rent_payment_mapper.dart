import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment.dart';

final class RentPaymentMapper {
  const RentPaymentMapper._();

  static Map<String, Object?> toJson(RentPayment payment) => <String, Object?>{
    'id': payment.id,
    'receiptNumber': payment.receiptNumber,
    'landlordId': payment.landlordId,
    'tenancyId': payment.tenancyId,
    'tenantName': payment.tenantName,
    'unitLabel': payment.unitLabel,
    'propertyName': payment.propertyName,
    'amountMinor': payment.amountMinor,
    'method': payment.method,
    'period': payment.period,
    'paidOn': payment.paidOn.toUtc().toIso8601String(),
    'createdAt': payment.createdAt.toUtc().toIso8601String(),
    'updatedAt': payment.updatedAt.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(payment.syncMetadata),
  };

  static RentPayment fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return RentPayment(
      id: reader.requiredString('id'),
      receiptNumber: reader.optionalString('receiptNumber'),
      landlordId: reader.requiredString('landlordId'),
      tenancyId: reader.optionalString('tenancyId'),
      tenantName: reader.requiredString('tenantName'),
      unitLabel: reader.requiredString('unitLabel'),
      propertyName: reader.requiredString('propertyName'),
      amountMinor: reader.requiredInt('amountMinor'),
      method: reader.requiredString('method'),
      period: reader.requiredString('period'),
      paidOn: reader.requiredDate('paidOn'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
