import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import '../../../core/domain/domain_exception.dart';
import '../../auth/application/session_controller.dart';
import '../domain/rent_payment.dart';

final rentPaymentsProvider = StreamProvider<CloudData<List<RentPayment>>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.payments.watchAll();
});

/// Payments belonging to one tenancy, newest first.
final tenancyPaymentsProvider =
    StreamProvider.family<CloudData<List<RentPayment>>, String>((
      ref,
      tenancyId,
    ) async* {
      final deps = await ref.watch(appDependenciesProvider.future);
      yield* deps.payments.watchAll(tenancyId: tenancyId);
    });

final recordRentPaymentProvider = Provider<RecordRentPayment>(
  RecordRentPayment.new,
);

/// Reports money against a tenancy and waits for the server.
///
/// This used to be two writes: the payment, and a local balance adjustment to
/// make it look settled immediately. Both are now one command, and the balance
/// is not this client's to compute — `payment.recordAgainstTenancy` allocates
/// against open invoices inside a server transaction, and the new figure
/// arrives with the next read of the tenancy.
///
/// The old local adjustment was already careful to skip tenant declarations,
/// because settling one would have let a tenant clear their own arrears by
/// asserting them away. Removing the adjustment entirely removes the whole
/// class of problem rather than one instance of it: there is no longer any
/// path by which a balance on screen reflects work the server has not done.
class RecordRentPayment {
  const RecordRentPayment(this._ref);

  final Ref _ref;

  /// Returns proof the server accepted the report. For a landlord recording
  /// money they hold, that means settled and receipted; for a tenant's report,
  /// it means the claim is now with their landlord — not that anything is paid.
  Future<MutationResult> call(RecordRentPaymentInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    final tenancy = await deps.tenancies.getById(input.tenancyId);
    // A tenancy that could not be read is not a tenancy that does not exist,
    // and money must not be reported against a guess either way.
    if (tenancy.hasFailed) {
      throw DomainValidationException(<String, String>{
        'tenancy': 'could not be loaded; check your connection and try again',
      });
    }
    final record = tenancy.value;
    if (record == null) {
      throw EntityNotFoundException('tenancy', input.tenancyId);
    }
    return deps.payments.record(tenancy: record, input: input);
  }
}

/// One payment a tenant reported that is waiting on the landlord's decision.
final class DeclaredPayment {
  const DeclaredPayment({
    required this.id,
    required this.version,
    required this.amountMinor,
    required this.method,
    required this.period,
    required this.reference,
    required this.declaredAt,
    this.note,
  });

  final String id;

  /// Concurrency token for `payment.confirmDeclared` / `rejectDeclared`.
  final int version;

  final int amountMinor;
  final String method;
  final String period;

  /// The tenant's proof — what the landlord checks before deciding.
  final String reference;

  final DateTime? declaredAt;
  final String? note;
}

/// Payments awaiting this landlord's review, read live from the server-owned
/// `payments` collection.
///
/// Deliberately not mirrored offline: confirming one settles money and issues
/// a receipt, which is an online, server-authoritative act — a queued approval
/// applying hours later is an operational hazard, not a feature.
final declaredPaymentsProvider = StreamProvider<List<DeclaredPayment>>((
  ref,
) async* {
  final session = ref.watch(sessionControllerProvider);
  if (session == null || Firebase.apps.isEmpty) {
    yield const <DeclaredPayment>[];
    return;
  }
  try {
    yield* FirebaseFirestore.instance
        .collection('payments')
        .where('landlordId', isEqualTo: session.userId)
        .where('status', isEqualTo: 'declared')
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => [
            for (final document in snapshot.docs)
              if (document.data() case final data)
                DeclaredPayment(
                  id: document.id,
                  version: (data['version'] as num?)?.toInt() ?? 1,
                  amountMinor: (data['amountMinor'] as num?)?.toInt() ?? 0,
                  method: data['method'] as String? ?? 'cash',
                  period: data['period'] as String? ?? '',
                  reference: data['reference'] as String? ?? '',
                  declaredAt: (data['declaredAt'] as Timestamp?)?.toDate(),
                  note: data['note'] as String?,
                ),
          ],
        );
  } on FirebaseException {
    yield const <DeclaredPayment>[];
  }
});

/// Reason codes `payment.rejectDeclared` accepts.
const declaredPaymentRejectReasons = [
  'PAYMENT_NOT_RECEIVED',
  'AMOUNT_INCORRECT',
  'REFERENCE_INVALID',
  'DUPLICATE_DECLARATION',
  'LANDLORD_CORRECTION',
];

final reviewDeclaredPaymentProvider = Provider<ReviewDeclaredPayment>(
  ReviewDeclaredPayment.new,
);

/// The landlord's decision on a payment their tenant reported. Confirming
/// settles it and issues the receipt; rejecting closes the claim with a
/// reason the tenant sees. Both are audited server commands.
class ReviewDeclaredPayment {
  const ReviewDeclaredPayment(this._ref);

  final Ref _ref;

  Future<void> confirm(DeclaredPayment payment) async {
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'payment.confirmDeclared',
      aggregateId: payment.id,
      expectedVersion: payment.version,
    );
  }

  Future<void> reject(
    DeclaredPayment payment, {
    required String reasonCode,
    String? note,
  }) async {
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'payment.rejectDeclared',
      aggregateId: payment.id,
      expectedVersion: payment.version,
      payload: <String, Object?>{
        'reasonCode': reasonCode,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }
}
