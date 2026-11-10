import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Результат одной голосовой проверки.
class VoiceTestResult {
  final bool success;
  final String? resultText;
  final String? errorCode;
  final String? errorMessage;

  const VoiceTestResult({
    required this.success,
    this.resultText,
    this.errorCode,
    this.errorMessage,
  });

  factory VoiceTestResult.completed(String resultText) {
    return VoiceTestResult(
      success: true,
      resultText: resultText,
    );
  }

  factory VoiceTestResult.failure({
    required String errorCode,
    required String errorMessage,
  }) {
    return VoiceTestResult(
      success: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  factory VoiceTestResult.cancelled() {
    return VoiceTestResult.failure(
      errorCode: 'cancelled',
      errorMessage: 'Голосовая проверка отменена.',
    );
  }
}

/// Данные, необходимые для проверки произношения.
class VoiceTestRequest {
  final String referenceText;
  final String locale;

  const VoiceTestRequest({
    required this.referenceText,
    required this.locale,
  });
}

/// Токен отмены одной операции.
class VoiceTestCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

class _SpeechCaptureResult {
  final String? filePath;
  final String? errorCode;
  final String? errorMessage;

  const _SpeechCaptureResult.success(this.filePath)
      : errorCode = null,
        errorMessage = null;

  const _SpeechCaptureResult.failure(this.errorCode, this.errorMessage)
      : filePath = null;

  bool get success => filePath != null;
}

/// Сервис записи и проверки произношения.
///
/// Сервис самостоятельно управляет микрофоном и обнаружением речи.
/// Он не зависит от UI и не управляет учебными элементами.
class VoiceTestService {
  static const Duration _amplitudeInterval = Duration(milliseconds: 100);
  static const Duration _speechStartTimeout = Duration(seconds: 5);
  static const Duration _silenceTimeout = Duration(milliseconds: 1500);
  static const Duration _minimumSpeechDuration = Duration(milliseconds: 500);
  static const Duration _maximumRecordingDuration = Duration(seconds: 30);

  // Начальный порог VAD. После проверки на реальном телефоне его можно
  // откалибровать под фактический уровень микрофона и окружающий шум.
  static const double _speechThresholdDb = -42.0;

  final AudioRecorder _recorder = AudioRecorder();

  Completer<void>? _captureFinished;
  bool _disposed = false;

  /// Запускает запись речи и автоматически завершает её после паузы.
  ///
  /// Возвращает путь к WAV-файлу. При отмене или ошибке временная запись
  /// удаляется. Успешная запись сохраняется для последующей отправки на API.
  Future<_SpeechCaptureResult> _captureSpeech({
    required VoiceTestCancellationToken cancellationToken,
  }) async {
    if (_disposed) {
      return const _SpeechCaptureResult.failure(
        'service_disposed',
        'Сервис голосовой проверки уже закрыт.',
      );
    }

    if (cancellationToken.isCancelled) {
      return const _SpeechCaptureResult.failure(
        'cancelled',
        'Голосовая проверка отменена.',
      );
    }

    final captureFinished = Completer<void>();
    _captureFinished = captureFinished;

    String? recordingPath;
    var recordingStarted = false;
    StreamSubscription<Amplitude>? amplitudeSubscription;
    Timer? monitorTimer;

    try {
      final hasPermission = await _recorder.hasPermission();

      if (cancellationToken.isCancelled) {
        return const _SpeechCaptureResult.failure(
          'cancelled',
          'Голосовая проверка отменена.',
        );
      }

      if (!hasPermission) {
        return const _SpeechCaptureResult.failure(
          'permission_denied',
          'Нет разрешения на использование микрофона.',
        );
      }

      final supportsWav =
          await _recorder.isEncoderSupported(AudioEncoder.wav);

      if (!supportsWav) {
        return const _SpeechCaptureResult.failure(
          'unsupported_audio_format',
          'Устройство не поддерживает запись WAV.',
        );
      }

      final directory = await getTemporaryDirectory();
      final fileName =
          'voice_test_${DateTime.now().microsecondsSinceEpoch}.wav';
      recordingPath = '${directory.path}${Platform.pathSeparator}$fileName';

      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: false,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: AndroidRecordConfig(
          manageBluetooth: true,
        ),
      );

      await _recorder.start(config, path: recordingPath);
      recordingStarted = true;

      final captureStartedAt = DateTime.now();
      var speechFrameCount = 0;
      DateTime? lastSpeechAt;
      var confirmedSpeech = false;

      final captureCompleter = Completer<String?>();

      amplitudeSubscription = _recorder
          .onAmplitudeChanged(_amplitudeInterval)
          .listen(
        (amplitude) {
          final now = DateTime.now();

          if (amplitude.current >= _speechThresholdDb) {
            speechFrameCount++;
            lastSpeechAt = now;

            if (!confirmedSpeech &&
                speechFrameCount * _amplitudeInterval.inMilliseconds >=
                    _minimumSpeechDuration.inMilliseconds) {
              confirmedSpeech = true;
            }
          }
        },
        onError: (Object error) {
          if (!captureCompleter.isCompleted) {
            captureCompleter.completeError(error);
          }
        },
      );

      monitorTimer = Timer.periodic(_amplitudeInterval, (_) {
        if (captureCompleter.isCompleted) return;

        if (cancellationToken.isCancelled) {
          captureCompleter.complete('cancelled');
          return;
        }

        final now = DateTime.now();
        final elapsed = now.difference(captureStartedAt);

        if (!confirmedSpeech && elapsed >= _speechStartTimeout) {
          captureCompleter.complete('no_speech');
          return;
        }

        if (confirmedSpeech &&
            lastSpeechAt != null &&
            now.difference(lastSpeechAt!) >= _silenceTimeout) {
          captureCompleter.complete('completed');
          return;
        }

        if (elapsed >= _maximumRecordingDuration) {
          captureCompleter.complete(
            confirmedSpeech ? 'completed' : 'no_speech',
          );
        }
      });

      final outcome = await Future.any<String?>([
        captureCompleter.future,
        cancellationToken.whenCancelled.then((_) => 'cancelled'),
      ]);

      monitorTimer.cancel();
      monitorTimer = null;

      await amplitudeSubscription.cancel();
      amplitudeSubscription = null;

      if (outcome == 'cancelled' || cancellationToken.isCancelled) {
        await _recorder.cancel();
        recordingStarted = false;
        await _deleteFile(recordingPath);

        return const _SpeechCaptureResult.failure(
          'cancelled',
          'Голосовая проверка отменена.',
        );
      }

      if (outcome == 'no_speech') {
        await _recorder.cancel();
        recordingStarted = false;
        await _deleteFile(recordingPath);

        return const _SpeechCaptureResult.failure(
          'no_speech',
          'Речь не обнаружена. Попробуйте произнести фразу ещё раз.',
        );
      }

      await _recorder.stop();
      recordingStarted = false;

      final file = File(recordingPath);
      if (!await file.exists() || await file.length() <= 44) {
        await _deleteFile(recordingPath);

        return const _SpeechCaptureResult.failure(
          'empty_recording',
          'Не удалось получить аудиозапись.',
        );
      }

      if (cancellationToken.isCancelled) {
        await _deleteFile(recordingPath);

        return const _SpeechCaptureResult.failure(
          'cancelled',
          'Голосовая проверка отменена.',
        );
      }

      debugPrint('[VOICE TEST] WAV recorded: $recordingPath');

      return _SpeechCaptureResult.success(recordingPath);
    } catch (error, stackTrace) {
      debugPrint('[VOICE TEST] Recording error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (recordingStarted) {
        try {
          await _recorder.cancel();
        } catch (_) {
          // Сохраняем исходную ошибку записи.
        }
      }

      await _deleteFile(recordingPath);

      return _SpeechCaptureResult.failure(
        'recording_error',
        'Ошибка записи с микрофона: $error',
      );
    } finally {
      monitorTimer?.cancel();
      await amplitudeSubscription?.cancel();
      if (!captureFinished.isCompleted) {
        captureFinished.complete();
      }
      if (identical(_captureFinished, captureFinished)) {
        _captureFinished = null;
      }
    }
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null) return;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('[VOICE TEST] Could not delete temporary audio: $error');
    }
  }

  Future<VoiceTestResult> execute({
    required VoiceTestRequest request,
    required VoiceTestCancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return VoiceTestResult.cancelled();
    }

    if (request.referenceText.trim().isEmpty ||
        request.locale.trim().isEmpty) {
      return VoiceTestResult.failure(
        errorCode: 'invalid_request',
        errorMessage: 'Не задан текст фразы или язык.',
      );
    }

    final capture = await _captureSpeech(
      cancellationToken: cancellationToken,
    );

    if (!capture.success) {
      if (capture.errorCode == 'cancelled') {
        return VoiceTestResult.cancelled();
      }

      return VoiceTestResult.failure(
        errorCode: capture.errorCode ?? 'recording_error',
        errorMessage: capture.errorMessage ?? 'Не удалось записать речь.',
      );
    }

    // На этом этапе проверяем только работу микрофона и VAD.
    // Отправка WAV на сервер и оценка Azure будут подключены следующим этапом.
    await _deleteFile(capture.filePath);

    return VoiceTestResult.failure(
      errorCode: 'api_not_connected',
      errorMessage:
          'Запись речи выполнена. Подключение сервера оценки произношения '
          'будет добавлено следующим этапом.',
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    final activeCapture = _captureFinished;
    if (activeCapture != null) {
      await activeCapture.future;
    }

    await _recorder.dispose();
  }
}
