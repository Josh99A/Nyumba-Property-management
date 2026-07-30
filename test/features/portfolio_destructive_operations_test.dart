import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_cache.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/features/portfolio/data/cloud_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/unit_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';

import '../support/fake_cloud.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 12);
  const partition = CachePartition(
    environment: 'test-project',
    userId: 'landlord-1',
    role: 'landlord',
  );

  Unit unitRecord({int version = 4, bool archived = false}) => Unit(
    id: 'unit-1',
    propertyId: 'property-1',
    landlordId: 'landlord-1',
    label: 'A1',
    type: UnitType.apartment,
    status: UnitStatus.vacant,
    monthlyRentMinor: 150000000,
    currency: 'UGX',
    createdAt: now,
    updatedAt: now,
    serverVersion: version,
    isArchived: archived,
    archivedAt: archived ? now : null,
  );

  ({
    CloudUnitRepository repository,
    FakeCloudReadGateway reads,
    RecordingCommandGateway commands,
    StubConnection connection,
  })
  build({RecordingCommandGateway? commandGateway}) {
    final reads = FakeCloudReadGateway();
    final commands = commandGateway ?? RecordingCommandGateway();
    final connection = StubConnection();
    return (
      repository: CloudUnitRepository(
        reader: CloudReader(
          cache: CloudCache(clock: FixedClock(now)),
          gateway: reads,
          partition: partition,
          clock: FixedClock(now),
        ),
        commands: CommandDispatcher(
          gateway: commands,
          connection: connection,
          clock: FixedClock(now),
        ),
        scope: const LandlordScope('landlord-1'),
        clock: FixedClock(now),
      ),
      reads: reads,
      commands: commands,
      connection: connection,
    );
  }

  group('archiving a rental space', () {
    test('sends unit.archive guarded by the version it was read at', () async {
      final harness = build();
      harness.reads.seed(CommandAggregate.unit, [
        UnitMapper.toJson(unitRecord(version: 4)),
      ]);

      final unit = (await harness.repository.getAll()).value!.single;
      await harness.repository.archive(unit);

      final command = harness.commands.lastCommand;
      expect(command.type, 'unit.archive');
      expect(command.aggregateId, 'unit-1');
      // The guard is what stops an archive composed against a stale read from
      // silently overwriting someone else's concurrent change.
      expect(command.expectedVersion, 4);
      expect(command.payload, isEmpty);
    });

    test('refuses to send when the record carries no server version', () async {
      final harness = build();
      // A unit with no version never came from the server, so there is nothing
      // to guard against and the safe move is to refuse rather than send an
      // unguarded write.
      await expectLater(
        harness.repository.archive(unitRecord(version: 0)),
        throwsA(isA<DomainValidationException>()),
      );
      expect(harness.commands.sent, isEmpty);
    });

    test('a rejected archive leaves the space exactly as it was', () async {
      final harness = build(
        commandGateway: RecordingCommandGateway(
          responder: (_, _) => Future<CommandOutcome>.error(
            const CommandException(
              kind: CommandFailureKind.rejected,
              code: 'VALIDATION_FAILED',
              details: <String, Object?>{'reason': 'unitOccupied'},
            ),
          ),
        ),
      );
      harness.reads.seed(CommandAggregate.unit, [
        UnitMapper.toJson(unitRecord()),
      ]);
      final unit = (await harness.repository.getAll()).value!.single;

      await expectLater(
        harness.repository.archive(unit),
        throwsA(
          isA<CommandException>().having(
            (e) => e.reason,
            'reason',
            'unitOccupied',
          ),
        ),
      );

      // The server said no, so the space is still active — nothing local
      // pretended otherwise.
      final after = (await harness.repository.getAll()).value!.single;
      expect(after.isArchived, isFalse);
    });

    test('archiving while disconnected never reaches the wire', () async {
      final harness = build();
      harness.reads.seed(CommandAggregate.unit, [
        UnitMapper.toJson(unitRecord()),
      ]);
      final unit = (await harness.repository.getAll()).value!.single;
      harness.connection.online = false;

      await expectLater(
        harness.repository.archive(unit),
        throwsA(
          isA<CommandException>().having(
            (e) => e.kind,
            'kind',
            CommandFailureKind.connection,
          ),
        ),
      );
      // Nothing was sent and nothing was stored for later: the archive simply
      // did not happen, which is what the user is told.
      expect(harness.commands.sent, isEmpty);
    });

    test('the archived space leaves the active list once confirmed', () async {
      final harness = build();
      harness.reads.seed(CommandAggregate.unit, [
        UnitMapper.toJson(unitRecord()),
      ]);
      final unit = (await harness.repository.getAll()).value!.single;

      await harness.repository.archive(unit);
      // The server is the one that decides what the list contains; the next
      // snapshot is what removes it, not a local edit.
      harness.reads.emitUpdate(CommandAggregate.unit, [
        UnitMapper.toJson(unitRecord(version: 5, archived: true)),
      ]);

      expect((await harness.repository.getAll()).value, isEmpty);
      expect(
        (await harness.repository.getAll(
          includeArchived: true,
        )).value!.single.isArchived,
        isTrue,
      );
    });
  });
}
