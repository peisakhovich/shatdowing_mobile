import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playFile(String filePath) async {
    debugPrint('[AUDIO] Opening: $filePath');

    await _player.setFilePath(filePath);

    // Подписываемся до запуска, чтобы не пропустить завершение.
    final completed = _player.processingStateStream.firstWhere(
      (state) =>
          state == ProcessingState.completed || state == ProcessingState.idle,
    );

    try {
      await _player.play();

      // play() сам по себе не гарантирует, что аудио уже завершилось.
      // Ожидаем completed или idle (например, после остановки).
      await completed;
    } catch (_) {
      // Не оставляем необработанное ожидание при ошибке воспроизведения.
      rethrow;
    }
  }

  Future<void> playAsset(String assetPath) async {
    await _player.setAsset(assetPath);
    await _player.play();
  }

  Future<void> playBytes(List<int> audioBytes) async {
    if (audioBytes.isEmpty) {
      throw ArgumentError('Аудиоданные не должны быть пустыми.');
    }

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}audio_preview.mp3',
    );

    await file.writeAsBytes(audioBytes, flush: true);

    await playFile(file.path);
  }

  Future<void> stop() async {
    debugPrint(
      '[AUDIO STOP] Requested. '
      'Position: ${_player.position}, '
      'State: ${_player.processingState}',
    );

    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
