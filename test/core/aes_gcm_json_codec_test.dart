import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/aes_gcm_json_codec.dart';

void main() {
  test('_FastAesGcm matches the NIST AES-256-GCM known-answer vector', () {
    // NIST CAVP gcmEncryptExtIV256.rsp: Count 0 for 96-bit IV,
    // 128-bit plaintext, no AAD, and a 128-bit tag.
    final cipher = FastAesGcmTestHarness(
      _hex('31bdadd96698c204aa9ce1448ea94ae1fb4a9a0b3c9d773b51bb1822666b8f22'),
    );
    final nonce = _hex('0d18e06c7c725ac9e362e1ce');
    final plaintext = _hex('2db5168e932556f8089a0622981d017d');
    final expectedSealed = _hex(
      'fa4362189661d163fcd6a56d8bf0405a'
      'd636ac1bbedd5cc3ee727dc2ab4a9489',
    );

    final sealed = cipher.encrypt(plaintext, nonce);

    expect(sealed, orderedEquals(expectedSealed));
    expect(cipher.decrypt(sealed, nonce), orderedEquals(plaintext));
  });
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);
