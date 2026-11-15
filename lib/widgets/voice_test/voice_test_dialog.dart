import 'package:flutter/material.dart';

import '../../localization/localization.dart';
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

  String _scoreText(double? value) => value == null ? '—' : '${value.round()}%';

  Widget _scoreRow(String label, double? value, Color color) {
    final progress = value == null
        ? 0.0
        : value.clamp(0.0, 100.0).toDouble() / 100.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 104, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                color: color,
                backgroundColor: color.withValues(alpha: 0.13),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              _scoreText(value),
              textAlign: TextAlign.end,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoresTable(VoiceTestAssessment assessment) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Column(
          children: [
            _scoreRow(
              lng.t('voicePronunciation'),
              assessment.pronunciation,
              Colors.blue.shade700,
            ),
            const Divider(height: 1),
            _scoreRow(lng.t('voiceAccuracy'), assessment.accuracy, Colors.green.shade900),
            const Divider(height: 1),
            _scoreRow(
              lng.t('voiceFluency'),
              assessment.fluency,
              Colors.deepPurple.shade400,
            ),
            const Divider(height: 1),
            _scoreRow(
              lng.t('voiceCompleteness'),
              assessment.completeness,
              Colors.deepOrange.shade600,
            ),
          ],
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
    VoiceWordStatus.correct => const Color.fromARGB(255, 16, 107, 66),
    VoiceWordStatus.mispronunciation => const Color.fromARGB(255, 53, 193, 7),
    VoiceWordStatus.substitution => Colors.deepPurple.shade700,
    VoiceWordStatus.omission => Colors.red.shade700,
    VoiceWordStatus.unverified => const Color.fromARGB(255, 51, 145, 19),
  };


  String _statusLabel(VoiceWordStatus status) => switch (status) {
    VoiceWordStatus.correct => lng.t('voiceStatusCorrect'),
    VoiceWordStatus.mispronunciation => lng.t('voiceStatusMispronunciation'),
    VoiceWordStatus.substitution => lng.t('voiceStatusSubstitution'),
    VoiceWordStatus.omission => lng.t('voiceStatusOmission'),
    VoiceWordStatus.unverified => lng.t('voiceStatusUnverified'),
  };

  Widget _wordStatistics(VoiceTestAssessment assessment) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        title: Text(lng.t('voiceWordComparison')),
        subtitle: assessment.comparisonAvailable
            ? Text(
                '${lng.t('voiceMatches', params: {'count': assessment.correctCount})} · '
                '${lng.t('voiceSubstitutions', params: {'count': assessment.substitutionCount})} · '
                '${lng.t('voiceOmissions', params: {'count': assessment.omissionCount})} · '
                '${lng.t('voiceInsertions', params: {'count': assessment.insertionCount})}',
              )
            : Text(lng.t('voiceServerComparisonUnavailable')),
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
                lng.t('voiceExtraWordsTitle', params: {'count': assessment.insertions.length}),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 6),
            for (final insertion in assessment.insertions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      color: Colors.deepOrange,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(insertion.text)),
                    if (insertion.confidence != null)
                      Text(
                        lng.t('voiceSttConfidence', params: {'value': _scoreText(insertion.confidence! * 100)}),
                      ),
                  ],
                ),
              ),
          ],
          if (assessment.referenceWords.every((word) => word.accuracy == null))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                lng.t('voiceAzureNoWordScores'),
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wordStatisticsRow(int number, VoiceWordResult word) {
    final sttColor = _statusColor(word.status);
    final azureColor = _statusColor(word.azureStatus);
    final accuracyText = word.accuracy == null
        ? lng.t('voiceNoAzureAccuracy')
        : lng.t('voiceAzureAccuracy', params: {'value': '${word.accuracy!.round()}/100'});

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
                Text(
                  word.text,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'STT: ${_statusLabel(word.status)}',
                  style: TextStyle(color: sttColor, fontSize: 12),
                ),
                Text(
                  'Azure: ${_statusLabel(word.azureStatus)}',
                  style: TextStyle(color: azureColor, fontSize: 12),
                ),
                Text(
                  accuracyText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (word.recognizedWord != null &&
                    word.status == VoiceWordStatus.substitution)
                  Text(
                    lng.t('voiceRecognizedAs', params: {'word': word.recognizedWord}),
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcriptCard({required String title, required String text}) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 5),
            Text(
              text.isEmpty ? lng.t('voiceTextNotReceived') : text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        _phase == _DialogPhase.recording || _phase == _DialogPhase.processing;
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
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        lng.t('voiceTitle'),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!busy)
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: lng.t('voiceClose'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_phase != _DialogPhase.result) ...[
                        Text(
                          lng.t('voiceSayPhrase'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.request.referenceText,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(height: 1.45),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_phase == _DialogPhase.ready) ...[
                        Text(lng.t('voiceStartInstruction')),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _startRecording,
                          icon: const Icon(Icons.mic),
                          label: Text(lng.t('voiceStart')),
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
                          lng.t('voiceRecording'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _stopRecording,
                          icon: const Icon(Icons.stop),
                          label: Text(lng.t('voiceStop')),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ],
                      if (_phase == _DialogPhase.processing) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 14),
                        const Text(
                          lng.t('voiceProcessing'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_phase == _DialogPhase.result &&
                          _assessment != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          lng.t('voiceAzureAssessment'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 6),
                        _scoresTable(_assessment!),
                        const SizedBox(height: 8),
                        Text(
                          lng.t('voiceDeviations'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        VoiceReferenceText(words: _assessment!.referenceWords),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _legend(
                              const Color.fromARGB(255, 16, 107, 66),
                              lng.t('voiceLegendMatch'),
                            ),
                            _legend(
                              const Color.fromARGB(255, 53, 193, 7),
                              'Azure',
                            ),
                            _legend(Colors.deepPurple, lng.t('voiceLegendSubstitution')),
                            _legend(Colors.red, lng.t('voiceLegendOmission')),
                          ],
                        ),
                        Text(
                          lng.t('voiceMixedLegend'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_assessment!.comparisonAvailable)
                          _transcriptCard(
                            title: lng.t('voiceStandardRecognition'),
                            text: _assessment!.recognizedText,
                          ),
                        if (!_assessment!.comparisonAvailable)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _assessment!.comparisonError ??
                                  lng.t('voiceExtraRecognitionFailed'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        Card(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lng.t('voiceConclusion'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(_assessment!.integratedConclusion),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _wordStatistics(_assessment!),
                        if (_assessment!.insertions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            lng.t('voiceExtraWords'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(lng.t('voiceExtraWordsDescription')),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            children: _assessment!.insertions
                                .map(
                                  (item) => Chip(
                                    label: Text(item.text),
                                    backgroundColor: Colors.deepOrange.shade50,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                      if (_phase == _DialogPhase.error) ...[
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _result?.errorMessage ??
                              lng.t('voiceCheckFailed'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _startRecording,
                          icon: const Icon(Icons.refresh),
                          label: Text(lng.t('voiceRetryRecording')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_phase == _DialogPhase.result || _phase == _DialogPhase.error)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      if (_phase == _DialogPhase.result)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _startRecording,
                            icon: const Icon(Icons.refresh),
                            label: Text(lng.t('voiceRetry')),
                          ),
                        ),
                      if (_phase == _DialogPhase.result)
                        const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(lng.t('voiceClose')),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
