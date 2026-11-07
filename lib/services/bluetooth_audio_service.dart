import 'package:audio_service/audio_service.dart';

import 'bluetooth_audio_handler.dart';

class BluetoothAudioService {
  BluetoothAudioService._();

  static BluetoothAudioHandler? _handler;

  static BluetoothAudioHandler get handler {
    final value = _handler;

    if (value == null) {
      throw StateError('BluetoothAudioService ещё не инициализирован.');
    }

    return value;
  }

  static Future<void> initialize() async {
    if (_handler != null) return;

    _handler = await AudioService.init(
      builder: () => BluetoothAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.soundlanguagestudio.audio',
        androidNotificationChannelName: 'Sound Language Studio',
        androidStopForegroundOnPause: false,
      ),
    );
  }
}
