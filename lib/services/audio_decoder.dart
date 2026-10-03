import 'package:flutter/services.dart';

class AudioDecoder {
  static const _channel = MethodChannel('io.siirsuite.siir/convert');
  static Future<String> convertToWav(String path) async {
    final wavPath = await _channel.invokeMethod<String>('decode', {
      'path': path,
    });
    return wavPath!;
  }
}
