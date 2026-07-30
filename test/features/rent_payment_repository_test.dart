import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_cache.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/features/finance/data/cloud_rent_payment_repository.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';

import '../support/fake_cloud.dart';

/// This file used to assert two things that no longer exist: that a payment
/// carried a durable ordering dependency on its tenancy, and that a *local*
/// balance adjustment never fell below zero.
///
/// Both were consequences of recording money on the device. Ordering mattered
/// because writes were queued and could arrive out of sequence; the balance
/// clamp mattered because the client was doing the arithmetic. Neither is true
/// now — there is no queue, and the balance is the server's.
///
/// What replaced them is the distinction that actually protects money: which
/// command a report becomes.
void main() {
  final now = DateTime.utc(2026, 7, 29, 9);
  const partition = CachePartition(
    environment: 'test-project',
    userId: 'landlord-1',
    role: 'landlord',
  );

  Tenancy tenancy() => Tenancy(
    id: 'lease-1',
    landlordId: 'landlord-1',
    tenantName: 'Amina Kamau',
    email: 'amina@example.com',
    phone: '+256700000001',
    unitLabel: 'B4',
    propertyName: 'Sunset Apartments',
    monthlyRentMinor: 120000000,
    balanceMinor: 120000000,
    leaseStart: DateTime.utc(2026),
    leaseEnd: DateTime.utc(2027),
    status: TenancyStatus.active,
    createdAt: now,
    updatedAt: now,
    serverVersion: 2,
  );

  ({CloudRentPaymentRepository repository, RecordingCommandGateway commands})
  build({StubConnection? connection}) {
    final commands = RecordingCommandGateway();
    return (
      repository: CloudRentPaymentRepository(
        reader: CloudReader(
          cache: CloudCache(clock: FixedClock(now)),
          gateway: FakeCloudReadGateway(),
          partition: partition,
          clock: FixedClock(now),
        ),
        commands: CommandDispatcher(
          gateway: commands,
          connection: connection ?? StubConnection(),
          clock: FixedClock(now),
        ),
        scope: const LandlordScope('landlord-1'),
        clock: FixedClock(now),
      ),
      commands: commands,
    );
  }

  group('which command carries the money', () {
    test('a landlord recording money they hold settles it', () async {
      final harness = build();

      await harness.repository.record(
        tenancy: tenancy(),
        input: const RecordRentPaymentInput(
          tenancyId: 'lease-1',
          amountMinor: 120000000,
          method: 'mtn_momo',
          period: 'July 2026',
        ),
      );

      final command = harness.commands.lastCommand;
      // Settles against open invoices and issues a receipt, server-side.
      expect(command.type, 'payment.recordAgainstTenancy');
      expect(command.payload['tenancyId'], 'lease-1');
      expect(command.payload['amountMinor'], 120000000);
    });

    test('a tenant reporting money they sent only makes a claim', () async {
      final harness = build();

      await harness.repository.record(
        tenancy: tenancy(),
        input: const RecordRentPaymentInput(
          tenancyId: 'lease-1',
          amountMinor: 120000000,
          method: 'mtn_momo',
          period: 'July 2026',
          reference: 'MTN-9931',
          declaredByTenant: true,
        ),
      );

      // Allocates nothing and moves no balance until the landlord confirms it.
      // Otherwise a tenant could clear their own arrears by asserting them away.
      expect(harness.commands.lastCommand.type, 'payment.declare');
      expect(harness.commands.lastCommand.payload['reference'], 'MTN-9931');
    });

    test(
      'a tenant declaration without proof is refused before sending',
      () async {
        final harness = build();

        await expectLater(
          harness.repository.record(
            tenancy: tenancy(),
            input: const RecordRentPaymentInput(
              tenancyId: 'lease-1',
              amountMinor: 120000000,
              method: 'mtn_momo',
              declaredByTenant: true,
            ),
          ),
          throwsA(isA<DomainValidationException>()),
        );
        // The landlord is being asked to accept money on the evidence alone, so a
        // declaration with nothing to check never leaves the device.
        expect(harness.commands.sent, isEmpty);
      },
    );
  });

  group('nothing is reported without the server', () {
    test('recording while disconnected never reaches the wire', () async {
      final harness = build(connection: StubConnection(online: false));

      await expectLater(
        harness.repository.record(
          tenancy: tenancy(),
          input: const RecordRentPaymentInput(
            tenancyId: 'lease-1',
            amountMinor: 120000000,
            method: 'cash',
          ),
        ),
        throwsA(
          isA<CommandException>().having(
            (e) => e.kind,
            'kind',
            CommandFailureKind.connection,
          ),
        ),
      );
      // Nothing sent and nothing queued: the payment simply was not recorded,
      // which is what the user is told.
      expect(harness.commands.sent, isEmpty);
    });

    test('a rejected payment reports the server\'s reason', () async {
      final commands = RecordingCommandGateway(
        responder: (_, _) => Future<CommandOutcome>.error(
          const CommandException(
            kind: CommandFailureKind.rejected,
            code: 'VALIDATION_FAILED',
            details: <String, Object?>{'reason': 'tenancyNotActive'},
          ),
        ),
      );
      final repository = CloudRentPaymentRepository(
        reader: CloudReader(
          cache: CloudCache(clock: FixedClock(now)),
          gateway: FakeCloudReadGateway(),
          partition: partition,
          clock: FixedClock(now),
        ),
        commands: CommandDispatcher(
          gateway: commands,
          connection: StubConnection(),
          clock: FixedClock(now),
        ),
        scope: const LandlordScope('landlord-1'),
        clock: FixedClock(now),
      );

      await expectLater(
        repository.record(
          tenancy: tenancy(),
          input: const RecordRentPaymentInput(
            tenancyId: 'lease-1',
            amountMinor: 120000000,
            method: 'cash',
          ),
        ),
        throwsA(
          isA<CommandException>().having(
            (e) => e.reason,
            'reason',
            'tenancyNotActive',
          ),
        ),
      );
    });

    test('a non-positive amount is refused before sending', () async {
      final harness = build();

      await expectLater(
        harness.repository.record(
          tenancy: tenancy(),
          input: const RecordRentPaymentInput(
            tenancyId: 'lease-1',
            amountMinor: 0,
            method: 'cash',
          ),
        ),
        throwsA(isA<DomainValidationException>()),
      );
      expect(harness.commands.sent, isEmpty);
    });
  });
}
