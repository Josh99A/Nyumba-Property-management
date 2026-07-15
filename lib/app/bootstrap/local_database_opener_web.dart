import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:sembast_web/sembast_web.dart';

Future<OfflineDatabase> openScopedOfflineDatabase(String scope) {
  // Web stores the mirror unencrypted; it is a rebuildable cache, so an
  // undecodable IndexedDB copy is discarded rather than left blocking launch.
  return OfflineDatabase.openRecovering(
    factory: databaseFactoryWeb,
    path: 'nyumba_$scope.db',
  );
}
