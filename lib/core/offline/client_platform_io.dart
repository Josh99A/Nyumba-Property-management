import 'dart:io';

String get currentClientPlatform {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  // Callable contracts support only shipped mobile/web platforms. Desktop
  // development uses the web identifier and is not a production target.
  return 'web';
}
