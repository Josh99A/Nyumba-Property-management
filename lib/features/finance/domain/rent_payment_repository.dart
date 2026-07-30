import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import '../../tenants/domain/tenancy.dart';
import 'rent_payment.dart';

/// Rent payments, read from the server-owned `landlordPortals` projection.
abstract interface class RentPaymentRepository {
  Stream<CloudData<List<RentPayment>>> watchAll({
    String? landlordId,
    String? tenancyId,
  });

  Future<CloudData<List<RentPayment>>> getAll({
    String? landlordId,
    String? tenancyId,
    bool forceRefresh = false,
  });

  Future<CloudData<RentPayment?>> getById(
    String id, {
    bool forceRefresh = false,
  });

  /// Reports money against [tenancy] and waits for the server.
  ///
  /// Which command this sends is the whole difference between settling money
  /// and merely claiming it:
  ///
  /// - a landlord recording money they are holding sends
  ///   `payment.recordAgainstTenancy`, which settles it and issues a receipt;
  /// - a tenant reporting money they sent sends `payment.declare`, which
  ///   allocates nothing and moves no balance until the landlord confirms it.
  ///   Otherwise a tenant could clear their own arrears by asserting them away.
  ///
  /// The durable ordering dependency the old signature carried is gone with the
  /// queue. There is no delivery left to sequence, and the server rejects a
  /// payment against a tenancy it does not hold.
  Future<MutationResult> record({
    required Tenancy tenancy,
    required RecordRentPaymentInput input,
  });
}
