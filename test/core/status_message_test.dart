import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations_en.dart';
import 'package:nyumba_property_management/core/presentation/status_message.dart';

void main() {
  final copy = AppLocalizationsEn();

  test('classifies only the secure-storage plugin as a storage failure', () {
    final message = NyumbaStatusMessage.fromError(
      const MissingPluginException(
        'No implementation found for method read on channel '
        'plugins.it_nomads.com/flutter_secure_storage',
      ),
      localizations: copy,
      subject: copy.statusSubjectDocuments,
    );

    expect(message.title, copy.statusMessageSecureStorageTitle);
    expect(message.severity, NyumbaMessageSeverity.critical);
  });

  test('keeps unrelated missing plugins on the generic failure path', () {
    final message = NyumbaStatusMessage.fromError(
      const MissingPluginException(
        'No implementation found for method scan on channel camera_plugin',
      ),
      localizations: copy,
      subject: copy.statusSubjectDocuments,
    );

    expect(
      message.title,
      copy.statusMessageLoadFailedTitle(copy.statusSubjectDocuments),
    );
    expect(message.title, isNot(copy.statusMessageSecureStorageTitle));
  });
}
