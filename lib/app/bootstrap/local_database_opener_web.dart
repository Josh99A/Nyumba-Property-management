import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:sembast_web/sembast_web.dart';

Future<OfflineDatabase> openScopedOfflineDatabase(String scope) {
  return OfflineDatabase.open(
    factory: databaseFactoryWeb,
    path: 'nyumba_$scope.db',
  );
}
