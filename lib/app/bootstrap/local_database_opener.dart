import 'package:nyumba_property_management/core/offline/offline_database.dart';

import 'local_database_opener_stub.dart'
    if (dart.library.io) 'local_database_opener_io.dart'
    if (dart.library.js_interop) 'local_database_opener_web.dart'
    as platform;

Future<OfflineDatabase> openScopedOfflineDatabase(String scope) =>
    platform.openScopedOfflineDatabase(scope);
