// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/finance/data/mappers/rent_payment_mapper.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment_repository.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';

/// Rent payments read from the server and reported through the command router.
///
/// This repository moves money, so it is the one place in the client where
/// "the server said yes" and "we wrote it down" must never be confused. It
/// returns proof of commit and nothing else: no locally-constructed payment,
/// no balance arithmetic, no optimistic receipt.
final class CloudRentPaymentRepository implements RentPaymentRepository {
  CloudRentPaymentRepository({
    required CloudReader reader,
    required CommandDispatcher commands,
    required CloudScope scope,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _reader = reader,
       _commands = commands,
       _scope = scope,
       _idGenerator = idGenerator ?? const UuidIdGenerator(),
       _clock = clock;

  final CloudReader _reader;
  final CommandDispatcher _commands;
  final CloudScope _scope;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Stream<CloudData<List<RentPayment>>> watchAll({
    String? landlordId,
    String? tenancyId,
  }) => _reader
      .watch(
        CommandAggregate.payment,
        _scope,
        decode: RentPaymentMapper.fromJson,
      )
      .map(
        (data) =>
            data.map((items) => _filterAndSort(items, landlordId, tenancyId)),
      );

  @override
  Future<CloudData<List<RentPayment>>> getAll({
    String? landlordId,
    String? tenancyId,
    bool forceRefresh = false,
  }) async {
    final data = await _reader.fetch(
      CommandAggregate.payment,
      _scope,
      decode: RentPaymentMapper.fromJson,
      allowCached: !forceRefresh,
    );
    return data.map((items) => _filterAndSort(items, landlordId, tenancyId));
  }

  @override
  Future<CloudData<RentPayment?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async {
    final data = await getAll(forceRefresh: forceRefresh);
    return data.map((items) => _firstOrNull(items, id));
  }

  @override
  Future<MutationResult> record({
    required Tenancy tenancy,
    required RecordRentPaymentInput input,
  }) async {
    if (input.amountMinor <= 0) {
      throw DomainValidationException(<String, String>{
        'amountMinor': 'must be a positive amount',
      });
    }
    final reference = _optional(input.reference);
    // A declaration is the landlord being asked to accept money on this
    // evidence alone, so one with nothing to check would just move the
    // guesswork onto them. The server enforces this too.
    if (input.declaredByTenant && reference == null) {
      throw DomainValidationException(<String, String>{
        'reference': 'a payment you report needs proof the landlord can check',
      });
    }

    final paymentId = _idGenerator.generate();
    final outcome = await _commands.submit(
      CloudCommand(
        commandId: _idGenerator.generate(),
        // The one branch that matters. `declare` allocates nothing and moves no
        // balance; `recordAgainstTenancy` settles and issues a receipt. Chosen
        // from who is speaking, never from anything the client computed.
        type: input.declaredByTenant
            ? 'payment.declare'
            : 'payment.recordAgainstTenancy',
        aggregate: CommandAggregate.payment,
        aggregateId: paymentId,
        operation: CommandOperation.create,
        payload: <String, Object?>{
          'tenancyId': tenancy.id,
          'amountMinor': input.amountMinor,
          'method': input.method,
          'period': _optional(input.period) ?? _currentPeriod(),
          // Optional when a landlord records money they are holding; mandatory
          // above when a tenant is claiming they sent it.
          'reference': ?reference,
        },
        issuedAt: _clock.now().toUtc(),
        expectedVersion: 0,
      ),
    );

    _reader.invalidate(CommandAggregate.payment);
    // A settled payment changes what the tenancy owes, and that arithmetic is
    // the server's. Dropping the cached tenancy is how the new balance gets
    // read back rather than guessed at here.
    _reader.invalidate(CommandAggregate.tenancy);
    return MutationResult(aggregateId: paymentId, outcome: outcome);
  }

  /// The month a payment defaults to, as `YYYY-MM`.
  String _currentPeriod() {
    final now = _clock.now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
  }

  static RentPayment? _firstOrNull(List<RentPayment> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<RentPayment> _filterAndSort(
    List<RentPayment> items,
    String? landlordId,
    String? tenancyId,
  ) {
    final result = items
        .where(
          (payment) =>
              (landlordId == null || payment.landlordId == landlordId) &&
              (tenancyId == null || payment.tenancyId == tenancyId),
        )
        .toList(growable: false);
    // Newest first: a payments list is read to answer "what just happened".
    result.sort((left, right) => right.paidOn.compareTo(left.paidOn));
    return result;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
