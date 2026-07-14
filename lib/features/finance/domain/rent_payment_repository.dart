import '../../tenants/domain/tenancy.dart';
import 'rent_payment.dart';

abstract interface class RentPaymentRepository {
  Stream<List<RentPayment>> watchAll({String? landlordId, String? tenancyId});
  Future<List<RentPayment>> getAll({String? landlordId, String? tenancyId});
  Future<RentPayment?> getById(String id);

  /// Persists the payment against [tenancy] with a durable ordering
  /// dependency on that tenancy aggregate, so the payment can never reach
  /// the server before the tenancy it belongs to.
  Future<RentPayment> record({
    required Tenancy tenancy,
    required RecordRentPaymentInput input,
  });
}
