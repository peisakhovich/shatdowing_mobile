import 'package:flutter/services.dart';

class DeviceWakeLock {
  static const MethodChannel _channel = MethodChannel(
    'com.example.shadowing_mobile/wake_lock',
  );

  static int _activeUsers = 0;

  /// Удерживает процессор активным.
  static Future<void> acquire() async {
    if (_activeUsers == 0) {
      try {
        await _channel.invokeMethod('acquire');
      } on PlatformException catch (e) {
        throw Exception('Не удалось включить Wake Lock: ${e.message}');
      }
    }

    _activeUsers++;
  }

  /// Освобождает блокировку, когда завершились все активные операции.
  static Future<void> release() async {
    if (_activeUsers == 0) return;

    _activeUsers--;

    if (_activeUsers == 0) {
      try {
        await _channel.invokeMethod('release');
      } on PlatformException catch (e) {
        throw Exception('Не удалось выключить Wake Lock: ${e.message}');
      }
    }
  }
}
