import 'package:flutter/material.dart';

import '../../models/voice_test_assessment.dart';
import '../../services/voice_test_service.dart';

class VoiceTestDialog extends StatefulWidget {
  final VoiceTestService service;
  final VoiceTestRequest request;
  final VoiceTestCancellationToken cancellationToken;

  const VoiceTestDialog({
    super.key,
    required this.service,
    required this.request,
    required this.cancellationToken,
  });

  @override
  State<VoiceTestDialog> createState() => _VoiceTestDialogState();
}

enum _DialogPhase { ready, recording, processing, result, error }

class _VoiceTestDialogState extends State<VoiceTestDialog> {
  _DialogPhase _phase = _DialogPhase.ready;
  Duration _recordingDuration = Duration.zero;
  VoiceTestResult? _result;
  VoiceTestAssessment? _assessment;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    widget.cancellationToken.whenCancelled.then((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _startRecording() async {
    if (_starting || _phase == _DialogPhase.recording ||
        _phase == _DialogPhase.processing) return;

    setState(() {
      _starting = true;
      _phase = _DialogPhase.recording;
      _recordingDuration = Duration.zero;
      _result = null;
      _assessment = null;
    });

    final result = await widget.service.execute(
      request: widget.request,
      cancellationToken: widget.cancellationToken,
      onRecordingDurationChanged: (duration) {
        if (mounted) setState(() => _recordingDuration = duration);
      },
      onProcessingStarted: () {
        if (mounted) setState(() => _phase = _DialogPhase.processing);
      },
    );

    if (!mounted) return;
    setState(() {
      _starting = false;
      _result = result;
      if (result.success && result.assessmentData != null) {
        _assessment = VoiceTestAssessment.fromJson(
          referenceText: widget.request.referenceText,
          json: result.assessmentData!,
        );
        _phase = _DialogPhase.result;
      } else {
        _phase = _DialogPhase.error;
      }
    });
  }

  void _stopRecording() => widget.service.stopRecording();

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final tenths = (duration.inMilliseconds % 1000) ~/ 100;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}.$tenths';
  }

  Widget _score(String label, double? value) {
    return SizedBox(
      width: 130,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(children: [
            Text(value == null ? '—' : value.round().toString(),
              style: Theme.of(context).textTheme.headlineSmall),
            Text(label, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _DialogPhase.recording ||
        _phase == _DialogPhase.processing;
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(children: [
                  const Expanded(child: Text('Проверка произношения',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600))),
                  if (!busy) IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Закрыть',
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Произнесите фразу:',
                        style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Text(widget.request.referenceText,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.45)),
                      const SizedBox(height: 20),
                      if (_phase == _DialogPhase.ready) ...[
                        const Text('Нажмите «Начать запись» и произнесите фразу естественно.'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _startRecording,
                          icon: const Icon(Icons.mic),
                          label: const Text('Начать запись'),
                        ),
                      ],
                      if (_phase == _DialogPhase.recording) ...[
                        const Icon(Icons.mic, size: 42, color: Colors.red),
                        const SizedBox(height: 8),
                        Text(_formatDuration(_recordingDuration),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text('Идёт запись. Она завершится после паузы или по кнопке.',
                          textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _stopRecording,
                          icon: const Icon(Icons.stop),
                          label: const Text('Завершить запись'),
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        ),
                      ],
                      if (_phase == _DialogPhase.processing) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 14),
                        const Text('Отправка записи и оценка произношения…',
                          textAlign: TextAlign.center),
                      ],
                      if (_phase == _DialogPhase.result && _assessment != null) ...[
                        Text('Результаты', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            _score('Произношение', _assessment!.pronunciation),
                            _score('Точность', _assessment!.accuracy),
                            _score('Беглость', _assessment!.fluency),
                            _score('Полнота', _assessment!.completeness),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Эталонная фраза', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        VoiceReferenceText(words: _assessment!.referenceWords),
                        const SizedBox(height: 8),
                        Wrap(spacing: 12, runSpacing: 6, children: [
                          _legend(Colors.green, 'Правильно'),
                          _legend(Colors.deepOrange, 'Произношение'),
                          _legend(Colors.red, 'Пропуск'),
                        ]),
                        if (_assessment!.recognizedText.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('Распознано', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 5),
                          Text(_assessment!.recognizedText),
                        ],
                        if (_assessment!.insertions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Лишние слова', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 5),
                          Wrap(spacing: 6, children: _assessment!.insertions.map((word) =>
                            Chip(label: Text(word), backgroundColor: Colors.amber.shade100)).toList()),
                        ],
                      ],
                      if (_phase == _DialogPhase.error) ...[
                        const Icon(Icons.error_outline, color: Colors.red, size: 40),
                        const SizedBox(height: 8),
                        Text(_result?.errorMessage ?? 'Не удалось выполнить проверку.',
                          textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _startRecording,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить запись'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_phase == _DialogPhase.result || _phase == _DialogPhase.error)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(children: [
                    if (_phase == _DialogPhase.result)
                      Expanded(child: OutlinedButton.icon(
                        onPressed: _startRecording,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Повторить'),
                      )),
                    if (_phase == _DialogPhase.result) const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Закрыть'),
                    )),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
