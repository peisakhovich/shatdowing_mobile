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
    if (_starting ||
        _phase == _DialogPhase.recording ||
        _phase == _DialogPhase.processing) {
      return;
    }

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

  String _scoreText(double? value) =>
      value == null ? '—' : '${value.round()}%';

  Widget _score(String label, double? value) {
    return SizedBox(
      width: 130,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(children: [
            Text(
              _scoreText(value),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(label, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Color _statusColor(VoiceWordStatus status) => switch (status) {
        VoiceWordStatus.correct => Colors.green.shade700,
        VoiceWordStatus.mispronunciation => Colors.amber.shade900,
        VoiceWordStatus.substitution => Colors.deepOrange.shade700,
        VoiceWordStatus.omission => Colors.red.shade700,
        VoiceWordStatus.unverified => Colors.grey.shade700,
      };

  String _statusLabel(VoiceWordStatus status) => switch (status) {
        VoiceWordStatus.correct => 'Совпадение',
        VoiceWordStatus.mispronunciation => 'Ошибка произношения (Azure)',
        VoiceWordStatus.substitution => 'Заменено другим словом',
        VoiceWordStatus.omission => 'Не распознано в произнесённой фразе',
        VoiceWordStatus.unverified => 'Сравнение недоступно',
      };

  Widget _wordStatistics(VoiceTestAssessment assessment) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        title: const Text('Сравнение по словам'),
        subtitle: assessment.comparisonAvailable
            ? Text(
                'Совпадения: ${assessment.correctCount} · '
                'Замены: ${assessment.substitutionCount} · '
                'Пропуски: ${assessment.omissionCount} · '
                'Лишние: ${assessment.insertionCount}',
              )
            : const Text('Серверное сравнение текста недоступно'),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 6),
          for (var index = 0; index < assessment.referenceWords.length; index++)
            _wordStatisticsRow(index + 1, assessment.referenceWords[index]),
          if (assessment.insertions.isNotEmpty) ...[
            const Divider(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Лишние слова (${assessment.insertions.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 6),
            for (final insertion in assessment.insertions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline,
                        color: Colors.deepOrange, size: 19),
                    const SizedBox(width: 8),
                    Expanded(child: Text(insertion.text)),
                    if (insertion.confidence != null)
                      Text('Уверенность STT: ${_scoreText(insertion.confidence! * 100)}'),
                  ],
                ),
              ),
          ],
          if (assessment.referenceWords.every((word) => word.accuracy == null))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Azure не вернул индивидуальные оценки точности для слов. '
                'Структурные совпадения и ошибки текста поступают отдельно '
                'из серверного сравнения.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wordStatisticsRow(int number, VoiceWordResult word) {
    final color = _statusColor(word.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 25,
            child: Text(
              '$number.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word.text,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  _statusLabel(word.status),
                  style: TextStyle(color: color, fontSize: 12),
                ),
                if (word.mispronounced &&
                    word.status != VoiceWordStatus.mispronunciation)
                  Text(
                    'Azure также отметил ошибку произношения',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontSize: 12,
                    ),
                  ),
                if (word.recognizedWord != null &&
                    word.status == VoiceWordStatus.substitution)
                  Text(
                    'Распознано: ${word.recognizedWord}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (word.accuracy != null)
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _scoreText(word.accuracy),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  LinearProgressIndicator(
                    value: word.accuracy!.clamp(0.0, 100.0).toDouble() / 100.0,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 2),
                  const Text('Точность Azure', style: TextStyle(fontSize: 9)),
                ],
              ),
            )
          else
            const SizedBox(
              width: 104,
              child: Text(
                'Нет оценки Azure',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _transcriptCard({
    required String title,
    required String text,
    required String description,
  }) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 5),
            Text(text.isEmpty ? 'Текст не получен.' : text),
            const SizedBox(height: 5),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

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
                  const Expanded(
                    child: Text(
                      'Проверка произношения',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!busy)
                    IconButton(
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
                      if (_phase != _DialogPhase.result) ...[
                        Text('Произнесите фразу:',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        Text(
                          widget.request.referenceText,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(height: 1.45),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_phase == _DialogPhase.ready) ...[
                        const Text(
                          'Нажмите «Начать запись» и произнесите фразу естественно.',
                        ),
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
                        Text(
                          _formatDuration(_recordingDuration),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text(
                          'Идёт запись. Она завершится после паузы или по кнопке.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _stopRecording,
                          icon: const Icon(Icons.stop),
                          label: const Text('Завершить запись'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ],
                      if (_phase == _DialogPhase.processing) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 14),
                        const Text(
                          'Отправка записи и оценка произношения…',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_phase == _DialogPhase.result && _assessment != null) ...[
                        Text('Результаты',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            _score('Произношение', _assessment!.pronunciation),
                            _score('Точность Azure', _assessment!.accuracy),
                            _score('Беглость', _assessment!.fluency),
                            _score('Полнота Azure', _assessment!.completeness),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Card(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Итоговое заключение',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(_assessment!.integratedConclusion),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Эталонная фраза',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        VoiceReferenceText(words: _assessment!.referenceWords),
                        const SizedBox(height: 8),
                        Wrap(spacing: 12, runSpacing: 6, children: [
                          _legend(Colors.green, 'Совпадение'),
                          _legend(Colors.amber.shade900, 'Ошибка произношения'),
                          _legend(Colors.deepOrange, 'Замена'),
                          _legend(Colors.red, 'Пропуск'),
                        ]),
                        _wordStatistics(_assessment!),
                        if (!_assessment!.comparisonAvailable)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _assessment!.comparisonError ??
                                  'Дополнительное распознавание текста не удалось. '
                                      'Оценки Azure сохранены, но сравнение фразы недоступно.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (_assessment!.comparisonAvailable) ...[
                          _transcriptCard(
                            title: 'Обычное распознавание (STT)',
                            text: _assessment!.recognizedText,
                            description:
                                'Этот текст использован сервером для поиска совпадений, замен, пропусков и лишних слов.',
                          ),
                        ],
                        if (_assessment!.azureRecognizedText.isNotEmpty)
                          _transcriptCard(
                            title: 'Распознавание Azure Pronunciation Assessment',
                            text: _assessment!.azureRecognizedText,
                            description:
                                'Это отдельный результат Azure, используемый при оценке произношения.',
                          ),
                        if (_assessment!.insertions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Лишние слова',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          const Text('Эти слова распознаны, но отсутствуют в эталоне.'),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            children: _assessment!.insertions
                                .map((item) => Chip(
                                      label: Text(item.text),
                                      backgroundColor: Colors.deepOrange.shade50,
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                      if (_phase == _DialogPhase.error) ...[
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          _result?.errorMessage ??
                              'Не удалось выполнить проверку.',
                          textAlign: TextAlign.center,
                        ),
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
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _startRecording,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить'),
                        ),
                      ),
                    if (_phase == _DialogPhase.result) const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Закрыть'),
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
