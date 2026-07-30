import 'client_platform_stub.dart'
    if (dart.library.io) 'client_platform_io.dart'
    if (dart.library.js_interop) 'client_platform_web.dart'
    as platform;

String get currentClientPlatform => platform.currentClientPlatform;
