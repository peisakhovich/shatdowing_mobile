import 'package:flutter/material.dart';

class PauseSettings extends StatelessWidget {
  final double pauseBeforeTranslationFactor;
  final int pauseBeforeTranslationMs;
  final int effectivePauseBeforeTranslationMs;
  final int pauseBetweenSentencesMs;

  final ValueChanged<double> onPauseBeforeTranslationChanged;
  final ValueChanged<int> onPauseBetweenSentencesChanged;

  const PauseSettings({
    super.key,
    required this.pauseBeforeTranslationFactor,
    required this.pauseBeforeTranslationMs,
    required this.effectivePauseBeforeTranslationMs,
    required this.pauseBetweenSentencesMs,
    required this.onPauseBeforeTranslationChanged,
    required this.onPauseBetweenSentencesChanged,
  });

  static const double _minPauseFactor = 0.0;
  static const double _maxPauseFactor = 6.0;

  static const int _minBetweenSentencesMs = 0;
  static const int _maxBetweenSentencesMs = 16000;
  static const int _betweenSentencesStepMs = 250;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Настройки пауз'),
      subtitle: const Text('Влияют на последующие паузы'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Перед переводом  '
                '${pauseBeforeTranslationFactor.toStringAsFixed(2)}x'
                '$pauseBeforeTranslationMs='
                '$effectivePauseBeforeTranslationMs ms',
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Slider(
                min: _minPauseFactor,
                max: _maxPauseFactor,
                divisions: 24,
                value: pauseBeforeTranslationFactor,
                label: '${pauseBeforeTranslationFactor.toStringAsFixed(2)}x',
                onChanged: onPauseBeforeTranslationChanged,
              ),
              Row(
                children: [
                  const Expanded(child: Text('Между предложениями')),
                  Text(
                    '$pauseBetweenSentencesMs ms',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              Slider(
                min: _minBetweenSentencesMs.toDouble(),
                max: _maxBetweenSentencesMs.toDouble(),
                divisions: _maxBetweenSentencesMs ~/ _betweenSentencesStepMs,
                value: pauseBetweenSentencesMs.toDouble(),
                label: '$pauseBetweenSentencesMs мс',
                onChanged: (value) {
                  final newValue =
                      (value / _betweenSentencesStepMs).round() *
                      _betweenSentencesStepMs;

                  onPauseBetweenSentencesChanged(newValue);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
