import 'dart:async';

class ScenarioPauseController {
  bool _isPaused = false;
  Completer<void>? _resumeCompleter;

  bool get isPaused => _isPaused;

  /// Переводит сценарий в состояние паузы.
  void pause() {
    if (_isPaused) return;

    _isPaused = true;
    _resumeCompleter = Completer<void>();
  }

  /// Возобновляет сценарий.
  void resume() {
    if (!_isPaused) return;

    _isPaused = false;

    final completer = _resumeCompleter;
    _resumeCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Ожидает возобновления сценария.
  Future<void> waitWhilePaused() async {
    while (_isPaused) {
      final completer = _resumeCompleter;
      if (completer == null) return;

      await completer.future;
    }
  }

  /// Выполняет паузу заданной продолжительности.
  ///
  /// Время, проведённое в состоянии паузы, не учитывается.
  Future<void> wait(
    Duration duration, {
    required bool Function() isCancelled,
  }) async {
    var remaining = duration;

    while (remaining > Duration.zero && !isCancelled()) {
      await waitWhilePaused();

      if (isCancelled()) return;

      final interval = remaining > const Duration(milliseconds: 50)
          ? const Duration(milliseconds: 50)
          : remaining;

      final stopwatch = Stopwatch()..start();

      await Future.delayed(interval);

      stopwatch.stop();

      remaining -= stopwatch.elapsed;

      if (remaining.isNegative) {
        remaining = Duration.zero;
      }
    }
  }

  /// Сбрасывает состояние при окончательной остановке.
  void reset() {
    resume();
  }
}
