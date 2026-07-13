import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<OfflineDatabase> openScopedOfflineDatabase(String scope) async {
  final directory = await getApplicationSupportDirectory();
  return OfflineDatabase.open(
    factory: databaseFactoryIo,
    path: path.join(directory.path, 'nyumba_$scope.db'),
  );
}
