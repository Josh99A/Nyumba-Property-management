import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/domain/domain_exception.dart';
import '../domain/rent_payment.dart';

final rentPaymentsProvider = StreamProvider<List<RentPayment>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.payments.watchAll();
});

/// Payments belonging to one tenancy, newest first.
final tenancyPaymentsProvider = StreamProvider
    .family<List<RentPayment>, String>((ref, tenancyId) async* {
      final deps = await ref.watch(appDependenciesProvider.future);
      yield* deps.payments.watchAll(tenancyId: tenancyId);
    });

final recordRentPaymentProvider = Provider<RecordRentPayment>(
  RecordRentPayment.new,
);

/// Records a payment and reduces the tenancy balance as two ordered offline
/// mutations. Each write is individually atomic with its outbox command; the
/// payment carries a durable dependency on the tenancy aggregate so remote
/// delivery preserves tenancy-before-payment ordering.
class RecordRentPayment {
  const RecordRentPayment(this._ref);

  final Ref _ref;

  Future<RentPayment> call(RecordRentPaymentInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    final tenancy = await deps.tenancies.getById(input.tenancyId);
    if (tenancy == null) {
      throw EntityNotFoundException('tenancy', input.tenancyId);
    }
    final payment = await deps.payments.record(
      tenancy: tenancy,
      input: input,
    );
    await deps.tenancies.adjustBalance(
      tenancyId: tenancy.id,
      deltaMinor: -input.amountMinor,
    );
    return payment;
  }
}
