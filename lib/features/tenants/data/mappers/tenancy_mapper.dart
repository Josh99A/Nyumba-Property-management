import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';

final class TenancyMapper {
  const TenancyMapper._();

  static Map<String, Object?> toJson(Tenancy tenancy) => <String, Object?>{
    'id': tenancy.id,
    'landlordId': tenancy.landlordId,
    'tenantUserId': tenancy.tenantUserId,
    'propertyId': tenancy.propertyId,
    'unitId': tenancy.unitId,
    'tenantName': tenancy.tenantName,
    'email': tenancy.email,
    'phone': tenancy.phone,
    'unitLabel': tenancy.unitLabel,
    'propertyName': tenancy.propertyName,
    'monthlyRentMinor': tenancy.monthlyRentMinor,
    'balanceMinor': tenancy.balanceMinor,
    'leaseStart': tenancy.leaseStart.toUtc().toIso8601String(),
    'leaseEnd': tenancy.leaseEnd.toUtc().toIso8601String(),
    'status': tenancy.status.name,
    'createdAt': tenancy.createdAt.toUtc().toIso8601String(),
    'updatedAt': tenancy.updatedAt.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(tenancy.syncMetadata),
  };

  static Tenancy fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return Tenancy(
      id: reader.requiredString('id'),
      landlordId: reader.requiredString('landlordId'),
      tenantUserId: reader.optionalString('tenantUserId'),
      propertyId: reader.optionalString('propertyId'),
      unitId: reader.optionalString('unitId'),
      tenantName: reader.requiredString('tenantName'),
      email: reader.requiredString('email'),
      phone: reader.requiredString('phone'),
      unitLabel: reader.requiredString('unitLabel'),
      propertyName: reader.requiredString('propertyName'),
      monthlyRentMinor: reader.requiredInt('monthlyRentMinor'),
      balanceMinor: reader.requiredInt('balanceMinor'),
      leaseStart: reader.requiredDate('leaseStart'),
      leaseEnd: reader.requiredDate('leaseEnd'),
      status: reader.enumValue('status', TenancyStatus.values),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
