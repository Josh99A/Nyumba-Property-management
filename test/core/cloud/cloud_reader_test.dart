import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_cache.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';

import '../../support/fake_cloud.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1, 10);
  const partition = CachePartition(
    environment: 'test-project',
    userId: 'landlord-1',
    role: 'landlord',
  );

  CloudReader readerFor(FakeCloudReadGateway gateway) => CloudReader(
    cache: CloudCache(clock: FixedClock(now)),
    gateway: gateway,
    partition: partition,
    clock: FixedClock(now),
  );

  String decodeName(Map<String, Object?> record) => record['name'] as String;

  test('keeps readable records and reports every discarded record', () async {
    final gateway = FakeCloudReadGateway()
      ..retrievedAt = now
      ..seed(CommandAggregate.property, const [
        <String, Object?>{'name': 'Acacia Court'},
        <String, Object?>{'unexpected': 'shape'},
      ]);

    final result = await readerFor(gateway).fetch(
      CommandAggregate.property,
      const LandlordScope('landlord-1'),
      decode: decodeName,
      allowCached: false,
    );

    expect(result.status, CloudDataStatus.live);
    expect(result.value, const ['Acacia Court']);
    expect(result.discardedRecordCount, 1);
  });

  test('an all-invalid server answer is partial data, not empty', () async {
    final gateway = FakeCloudReadGateway()
      ..retrievedAt = now
      ..seed(CommandAggregate.property, const [
        <String, Object?>{'unexpected': 'shape'},
      ]);

    final result = await readerFor(gateway).fetch(
      CommandAggregate.property,
      const LandlordScope('landlord-1'),
      decode: decodeName,
      allowCached: false,
    );

    expect(result.status, CloudDataStatus.live);
    expect(result.value, isEmpty);
    expect(result.discardedRecordCount, 1);
  });

  // A partial live result followed by a failed refresh used to keep the
  // incomplete list on screen while dropping the count that justifies its
  // warning, so the list looked complete exactly when it was least verifiable.
  test(
    'a failed refresh keeps the discarded count with the stale rows',
    () async {
      final gateway = FakeCloudReadGateway()
        ..retrievedAt = now
        ..seed(CommandAggregate.property, const [
          <String, Object?>{'name': 'Acacia Court'},
          <String, Object?>{'unexpected': 'shape'},
        ]);
      final states = <CloudData<List<String>>>[];
      final subscription = readerFor(gateway)
          .watch(
            CommandAggregate.property,
            const LandlordScope('landlord-1'),
            decode: decodeName,
          )
          .listen(states.add);
      await pumpEventQueue();

      gateway.fail(
        CommandAggregate.property,
        const CloudReadError(
          kind: CloudErrorKind.connection,
          code: 'UNAVAILABLE',
        ),
      );
      await pumpEventQueue();
      await subscription.cancel();

      final stale = states.last;
      expect(stale.status, CloudDataStatus.cachedPotentiallyOutdated);
      expect(stale.value, const ['Acacia Court']);
      expect(stale.discardedRecordCount, 1);
    },
  );
}
