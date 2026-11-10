import 'dart:async';

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
    return const VoiceTestResult.failure(
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

/// Сервис голосовой проверки.
///
/// Пока содержит заглушку. Запись микрофона, VAD и API будут добавлены
/// отдельным этапом.
class VoiceTestService {
  Future<VoiceTestResult> execute({
    required VoiceTestRequest request,
    required VoiceTestCancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return VoiceTestResult.cancelled();
    }

    // Временная заглушка до реализации записи и обращения к API.
    return VoiceTestResult.failure(
      errorCode: 'not_implemented',
      errorMessage: 'Голосовая проверка ещё не реализована.',
    );
  }
}
