import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  bool _pauseRequested = false;
  bool _playbackStarted = false;

  Completer<void>? _resumeCompleter;

  int _playbackGeneration = 0;

  bool get isPlaying => _player.playing;

  Future<void> playFile(String filePath) async {
    final generation = ++_playbackGeneration;

    _playbackStarted = false;

    debugPrint('[AUDIO] Opening: $filePath');

    await _player.setFilePath(filePath);

    if (generation != _playbackGeneration) return;

    await _playAndWait(generation);
  }

  Future<void> playAsset(String assetPath) async {
    final generation = ++_playbackGeneration;

    _playbackStarted = false;

    await _player.setAsset(assetPath);

    if (generation != _playbackGeneration) return;

    await _playAndWait(generation);
  }

  Future<void> _waitUntilResumed() async {
    while (_pauseRequested) {
      final completer = _resumeCompleter;

      if (completer == null) return;

      await completer.future;
    }
  }

  Future<void> _playAndWait(int generation) async {
    // Подписываемся до запуска, чтобы не пропустить завершение.
    final completed = _player.processingStateStream.firstWhere(
      (state) =>
          state == ProcessingState.completed || state == ProcessingState.idle,
    );

    // Если Bluetooth-пауза пришла во время подготовки MP3,
    // ждём её снятия, не пропуская текущую фразу.
    await _waitUntilResumed();

    if (generation != _playbackGeneration) return;

    _playbackStarted = true;

    debugPrint('[AUDIO] Playback started');

    await _player.play();

    // Ожидаем фактического завершения аудио.
    try {
      await completed;
    } finally {
      if (generation == _playbackGeneration) {
        _playbackStarted = false;
      }
    }
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

  Future<void> pause() async {
    if (_pauseRequested) return;

    _pauseRequested = true;
    _resumeCompleter = Completer<void>();

    debugPrint('[AUDIO] Pause requested. Position: ${_player.position}');

    await _player.pause();
  }

  Future<void> resume() async {
    if (!_pauseRequested) return;

    _pauseRequested = false;

    final completer = _resumeCompleter;
    _resumeCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    debugPrint('[AUDIO] Resume requested. Position: ${_player.position}');

    // Если MP3 уже воспроизводился, продолжаем с прежней позиции.
    // Если он ещё загружался, _playAndWait запустит его самостоятельно.
    if (_playbackStarted &&
        _player.processingState != ProcessingState.completed) {
      await _player.play();
    }
  }

  Future<void> stop() async {
    // Отменяем незавершённую операцию воспроизведения.
    _playbackGeneration++;

    _playbackStarted = false;
    _pauseRequested = false;

    final completer = _resumeCompleter;
    _resumeCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

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
