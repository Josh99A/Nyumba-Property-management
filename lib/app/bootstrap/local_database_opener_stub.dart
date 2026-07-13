import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:sembast/sembast_memory.dart';

Future<OfflineDatabase> openScopedOfflineDatabase(String scope) {
  return OfflineDatabase.open(
    factory: databaseFactoryMemory,
    path: 'nyumba_$scope.db',
  );
}
