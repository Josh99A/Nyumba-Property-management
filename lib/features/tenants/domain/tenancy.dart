import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum TenancyStatus { active, noticeGiven, ended }

/// One tenancy aggregate: the tenant identity plus their current lease and
/// running balance. Unit and property labels are denormalized projections so
/// the directory renders without cross-aggregate lookups.
final class Tenancy {
  Tenancy({
    required this.id,
    required this.landlordId,
    required this.tenantName,
    required this.email,
    required this.phone,
    required this.unitLabel,
    required this.propertyName,
    required this.monthlyRentMinor,
    required this.balanceMinor,
    required this.leaseStart,
    required this.leaseEnd,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.tenantUserId,
    this.propertyId,
    this.unitId,
  }) {
    validate();
  }

  final String id;
  final String landlordId;
  final String? tenantUserId;
  final String? propertyId;
  final String? unitId;
  final String tenantName;
  final String email;
  final String phone;
  final String unitLabel;
  final String propertyName;
  final int monthlyRentMinor;

  /// Outstanding amount the tenant owes, in minor units. Never negative;
  /// prepayments are represented server-side as credits, not local negatives.
  final int balanceMinor;
  final DateTime leaseStart;
  final DateTime leaseEnd;
  final TenancyStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  bool get balanceDue => balanceMinor > 0;

  void validate() {
    DomainValidation.check(<String, String?>{
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'tenantName': DomainValidation.requiredText(tenantName, maxLength: 120),
      'email': DomainValidation.email(email),
      'phone': DomainValidation.requiredText(phone, maxLength: 40),
      'unitLabel': DomainValidation.requiredText(unitLabel, maxLength: 60),
      'propertyName': DomainValidation.requiredText(
        propertyName,
        maxLength: 120,
      ),
      'monthlyRentMinor': DomainValidation.positiveMinorUnits(monthlyRentMinor),
      'balanceMinor': DomainValidation.positiveMinorUnits(
        balanceMinor,
        allowZero: true,
      ),
      'leaseEnd': leaseEnd.isAfter(leaseStart)
          ? null
          : 'must be after the lease start',
    });
  }

  Tenancy copyWith({
    int? balanceMinor,
    TenancyStatus? status,
    DateTime? leaseEnd,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => Tenancy(
    id: id,
    landlordId: landlordId,
    tenantUserId: tenantUserId,
    propertyId: propertyId,
    unitId: unitId,
    tenantName: tenantName,
    email: email,
    phone: phone,
    unitLabel: unitLabel,
    propertyName: propertyName,
    monthlyRentMinor: monthlyRentMinor,
    balanceMinor: balanceMinor ?? this.balanceMinor,
    leaseStart: leaseStart,
    leaseEnd: leaseEnd ?? this.leaseEnd,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class CreateTenancyInput {
  const CreateTenancyInput({
    required this.landlordId,
    required this.tenantName,
    required this.email,
    required this.unitLabel,
    required this.propertyName,
    required this.monthlyRentMinor,
    required this.leaseStart,
    required this.leaseEnd,
    this.phone = 'Not provided',
    this.tenantUserId,
    this.propertyId,
    this.unitId,
    this.openingBalanceMinor = 0,
  });

  final String landlordId;
  final String tenantName;
  final String email;
  final String phone;
  final String unitLabel;
  final String propertyName;
  final int monthlyRentMinor;
  final DateTime leaseStart;
  final DateTime leaseEnd;
  final String? tenantUserId;
  final String? propertyId;
  final String? unitId;
  final int openingBalanceMinor;
}
