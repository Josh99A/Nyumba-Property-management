import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Synchronous authenticated AES-256-GCM codec used by Sembast on mobile.
/// Each record receives a fresh 96-bit nonce and includes its authentication
/// tag in the encoded ciphertext.
final class AesGcmJsonCodec extends Codec<Object?, String> {
  AesGcmJsonCodec(Uint8List key)
    : assert(key.length == 32),
      _key = Uint8List.fromList(key);

  final Uint8List _key;

  @override
  Converter<String, Object?> get decoder => _AesGcmDecoder(_key);

  @override
  Converter<Object?, String> get encoder => _AesGcmEncoder(_key);
}

final class _AesGcmEncoder extends Converter<Object?, String> {
  const _AesGcmEncoder(this.key);

  final Uint8List key;

  @override
  String convert(Object? input) {
    final nonce = Uint8List(12);
    final random = Random.secure();
    for (var index = 0; index < nonce.length; index++) {
      nonce[index] = random.nextInt(256);
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(input)));
    final ciphertext = cipher.process(plaintext);
    return base64UrlEncode(Uint8List.fromList([...nonce, ...ciphertext]));
  }
}

final class _AesGcmDecoder extends Converter<String, Object?> {
  const _AesGcmDecoder(this.key);

  final Uint8List key;

  @override
  Object? convert(String input) {
    final encoded = base64Url.decode(input);
    if (encoded.length < 12 + 16) {
      throw const FormatException('Encrypted Sembast record is truncated.');
    }
    final nonce = Uint8List.sublistView(encoded, 0, 12);
    final ciphertext = Uint8List.sublistView(encoded, 12);
    final cipher = GCMBlockCipher(
      AESEngine(),
    )..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    try {
      return jsonDecode(utf8.decode(cipher.process(ciphertext)));
    } on InvalidCipherTextException catch (error) {
      throw FormatException(
        'Encrypted Sembast record failed authentication.',
        error,
      );
    }
  }
}
