/// Guards the workspace cloud-link indicator against a single failing
/// collection reporting the whole workspace offline.
///
/// The badge in the top bar reads [RemotePullCoordinator.linkState]. A landlord
/// watches several collections at once, some of which can legitimately error
/// (a projection that is not provisioned yet, a rule that denies one type)
/// while others stream live data. The link state must aggregate: live wins as
/// soon as any collection delivers, and offline shows only when none is live.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/remote_pull_gateway.dart';
import 'package:sembast/sembast_memory.dart';

class _FakeGateway implements RemotePullGateway {
  final Map<OfflineEntityType, StreamController<List<RemoteRecord>>>
  controllers = {};

  @override
  Stream<List<RemoteRecord>> watchCollection(
    OfflineEntityType entityType, {
    String? landlordId,
    String? tenantUid,
    String? clientUid,
    String? userUid,
    bool publicOnly = false,
    bool administrativeScope = false,
  }) {
    final controller = StreamController<List<RemoteRecord>>();
    controllers[entityType] = controller;
    return controller.stream;
  }
}

void main() {
  late OfflineDatabase database;
  late _FakeGateway gateway;
  late RemotePullCoordinator coordinator;

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'nyumba-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await database.initialize();
    gateway = _FakeGateway();
    coordinator = RemotePullCoordinator(database: database, gateway: gateway);
  });

  tearDown(() async {
    await coordinator.close();
    await database.close();
  });

  test('starts connecting before any snapshot arrives', () {
    coordinator.watch(OfflineEntityType.property, landlordId: 'landlord-1');
    expect(coordinator.linkState, CloudLinkState.connecting);
  });

  test('a live collection outweighs a failing one', () async {
    coordinator.watch(OfflineEntityType.property, landlordId: 'landlord-1');
    coordinator.watch(OfflineEntityType.payment, landlordId: 'landlord-1');

    // The payments projection errors, but properties deliver a snapshot.
    gateway.controllers[OfflineEntityType.payment]!.addError('permission');
    gateway.controllers[OfflineEntityType.property]!.add(const []);
    await pumpEventQueue();

    expect(coordinator.linkState, CloudLinkState.live);
  });

  test('a later failure on one collection does not drop a live workspace', () async {
    coordinator.watch(OfflineEntityType.property, landlordId: 'landlord-1');
    coordinator.watch(OfflineEntityType.payment, landlordId: 'landlord-1');

    gateway.controllers[OfflineEntityType.property]!.add(const []);
    await pumpEventQueue();
    expect(coordinator.linkState, CloudLinkState.live);

    gateway.controllers[OfflineEntityType.payment]!.addError('permission');
    await pumpEventQueue();
    expect(coordinator.linkState, CloudLinkState.live);
  });

  test('offline shows only when every collection has failed', () async {
    coordinator.watch(OfflineEntityType.property, landlordId: 'landlord-1');
    coordinator.watch(OfflineEntityType.payment, landlordId: 'landlord-1');

    gateway.controllers[OfflineEntityType.property]!.addError('permission');
    await pumpEventQueue();
    // One failure while the other is still connecting is not yet offline.
    expect(coordinator.linkState, CloudLinkState.connecting);

    gateway.controllers[OfflineEntityType.payment]!.addError('permission');
    await pumpEventQueue();
    expect(coordinator.linkState, CloudLinkState.failed);
  });

  test('link state changes are emitted on the stream', () async {
    final emitted = <CloudLinkState>[];
    final sub = coordinator.linkStates.listen(emitted.add);

    coordinator.watch(OfflineEntityType.property, landlordId: 'landlord-1');
    gateway.controllers[OfflineEntityType.property]!.add(const []);
    await pumpEventQueue();

    expect(emitted, contains(CloudLinkState.live));
    await sub.cancel();
  });
}
