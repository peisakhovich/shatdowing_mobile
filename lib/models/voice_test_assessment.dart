import 'package:flutter/material.dart';

import 'voice_token_alignment.dart';

enum VoiceWordStatus {
  correct,
  mispronunciation,
  substitution,
  omission,
  unverified,
}

class VoiceWordResult {
  final String text;
  /// Structural status from independent standard Speech-to-Text comparison.
  final VoiceWordStatus status;

  /// Independent Azure Pronunciation Assessment status.
  final VoiceWordStatus azureStatus;
  final double? accuracy;
  final bool mispronounced;
  final String? recognizedWord;
  final double? confidence;
  final int? offsetMs;
  final int? durationMs;

  const VoiceWordResult({
    required this.text,
    required this.status,
    this.azureStatus = VoiceWordStatus.unverified,
    this.accuracy,
    this.mispronounced = false,
    this.recognizedWord,
    this.confidence,
    this.offsetMs,
    this.durationMs,
  });
}

class VoiceInsertionResult {
  final String text;
  final double? confidence;
  final int? offsetMs;
  final int? durationMs;
  final int? recognizedIndex;

  const VoiceInsertionResult({
    required this.text,
    this.confidence,
    this.offsetMs,
    this.durationMs,
    this.recognizedIndex,
  });
}

class VoiceTestAssessment {
  final double? pronunciation;
  final double? accuracy;
  final double? fluency;
  final double? completeness;

  /// Independent standard Speech-to-Text transcript used by comparison.
  final String recognizedText;

  /// Reference-based transcript returned by Pronunciation Assessment.
  final String azureRecognizedText;

  final List<VoiceWordResult> referenceWords;
  final List<VoiceInsertionResult> insertions;
  final VoiceTokenAlignmentResult alignment;
  final List<String> alignmentWarnings;
  final bool comparisonAvailable;
  final String? comparisonError;
  final int? editDistance;
  final int? serverMatchCount;
  final int? serverSubstitutionCount;
  final int? serverOmissionCount;
  final int? serverInsertionCount;
  final double? standardRecognitionConfidence;

  const VoiceTestAssessment({
    required this.pronunciation,
    required this.accuracy,
    required this.fluency,
    required this.completeness,
    required this.recognizedText,
    required this.azureRecognizedText,
    required this.referenceWords,
    required this.insertions,
    required this.alignment,
    required this.comparisonAvailable,
    this.comparisonError,
    this.alignmentWarnings = const [],
    this.editDistance,
    this.serverMatchCount,
    this.serverSubstitutionCount,
    this.serverOmissionCount,
    this.serverInsertionCount,
    this.standardRecognitionConfidence,
  });

  int get correctCount =>
      serverMatchCount ??
      referenceWords.where((word) => word.status == VoiceWordStatus.correct).length;

  int get mispronunciationCount => referenceWords
      .where((word) =>
          word.status == VoiceWordStatus.mispronunciation || word.mispronounced)
      .length;

  int get substitutionCount =>
      serverSubstitutionCount ??
      referenceWords.where((word) => word.status == VoiceWordStatus.substitution).length;

  int get omissionCount =>
      serverOmissionCount ??
      referenceWords.where((word) => word.status == VoiceWordStatus.omission).length;

  int get insertionCount => serverInsertionCount ?? insertions.length;

  int get structuralErrorCount =>
      substitutionCount + omissionCount + insertionCount;

  /// A concise interpretation of both independent analyses.
  ///
  /// This is a qualitative conclusion, not an averaged or invented score.
  String get integratedConclusion {
    if (!comparisonAvailable) {
      final pronunciationText = pronunciation == null
          ? 'Оценка произношения Azure также отсутствует.'
          : 'Azure оценил произношение на ${pronunciation!.toStringAsFixed(1)}%.';
      return 'Текстовое сравнение выполнить не удалось. '
          '$pronunciationText '
          'Поэтому соответствие произнесённой фразы заданию пока нельзя '
          'подтвердить.';
    }

    final structuralText = structuralErrorCount == 0
        ? 'Обычное распознавание полностью совпало с эталоном: '
            '$correctCount слов совпали, замен, пропусков и лишних слов нет.'
        : 'В текстовом сравнении: $correctCount совпадений, '
            '$substitutionCount замен, $omissionCount пропусков '
            'и $insertionCount лишних слов.';

    final pronunciationText = pronunciation == null
        ? 'Azure не предоставил итоговую оценку произношения.'
        : pronunciation! >= 90
            ? 'Качество произношения по оценке Azure высокое '
                '(${pronunciation!.toStringAsFixed(1)}%).'
            : pronunciation! >= 75
                ? 'Оценка произношения Azure — '
                    '${pronunciation!.toStringAsFixed(1)}%; есть возможности '
                    'для улучшения.'
                : 'Оценка произношения Azure — '
                    '${pronunciation!.toStringAsFixed(1)}%; произношение '
                    'требует дополнительной работы.';

    final pronunciationErrors = mispronunciationCount == 0
        ? ''
        : ' Azure отдельно отметил ошибки произношения в '
            '$mispronunciationCount словах.';

    final overallText = structuralErrorCount == 0
        ? 'Итог: по распознанному тексту задание выполнено точно.'
        : 'Итог: произнесённая фраза отличается от эталона; '
            'проверьте перечисленные расхождения.';

    return '$structuralText $pronunciationText'
        '$pronunciationErrors $overallText';
  }

  factory VoiceTestAssessment.fromJson({
    required String referenceText,
    required Map<String, dynamic> json,
  }) {
    final rawAssessment = json['assessment'];
    final assessment = rawAssessment is Map
        ? Map<String, dynamic>.from(rawAssessment)
        : <String, dynamic>{};

    final standard = json['standard_recognition'] is Map
        ? Map<String, dynamic>.from(json['standard_recognition'] as Map)
        : <String, dynamic>{};
    final comparison = json['comparison'] is Map
        ? Map<String, dynamic>.from(json['comparison'] as Map)
        : <String, dynamic>{};

    final comparisonAlignment = comparison['alignment'];
    final standardText = standard['recognized_text']?.toString().trim() ?? '';
    final azureText = json['recognized_text']?.toString().trim() ?? '';

    // Tokenize only to preserve the user's original spelling and punctuation.
    // The actual match/substitution/omission/insertion decisions come solely
    // from comparison.alignment returned by the API.
    final referenceTokens = _displayTokens(referenceText);
    final transcriptTokens = _displayTokens(standardText);

    // Azure's word list preserves the spoken/reference token form used by
    // comparison.alignment. This matters when the displayed reference uses
    // digits ("7") but Azure and STT expose the spoken form ("siedem").
    final rawAzureWords = json['words'];
    final azureReferenceTokens = rawAzureWords is List
        ? rawAzureWords
            .whereType<Map>()
            .where((word) =>
                _normalizeErrorType(word['error_type']?.toString() ?? '') !=
                'insertion')
            .map((word) => word['word']?.toString().trim() ?? '')
            .where((word) => word.isNotEmpty)
            .toList()
        : <String>[];
    final validationReferenceTokens =
        azureReferenceTokens.length == referenceTokens.length
            ? azureReferenceTokens
            : referenceTokens;

    // Prefer the recognizer's structured word list over the display
    // transcript, which may format numbers as digits ("7") rather than
    // their spoken form ("siedem").
    final rawStandardWords = standard['words'];
    final structuredTranscriptTokens = rawStandardWords is List
        ? rawStandardWords
            .whereType<Map>()
            .map((word) => word['word']?.toString().trim() ?? '')
            .where((word) => word.isNotEmpty)
            .toList()
        : <String>[];
    final validationTranscriptTokens = structuredTranscriptTokens.isNotEmpty
        ? structuredTranscriptTokens
        : transcriptTokens;
    final rawAlignment = comparisonAlignment is List
        ? comparisonAlignment
        : const <dynamic>[];
    final warnings = <String>[];
    final hasComparisonPayload = standard['success'] == true &&
        comparison['success'] != false &&
        comparisonAlignment is List &&
        comparison['counts'] is Map;
    final comparisonAvailable = hasComparisonPayload &&
        _isCompleteAlignment(
          rawAlignment: rawAlignment,
          referenceTokens: validationReferenceTokens,
          recognizedTokens: validationTranscriptTokens,
        );
    if (hasComparisonPayload && !comparisonAvailable) {
      warnings.add(
        'Серверное сравнение неполное или не соответствует тексту '
        'распознавания; цветовая разметка не применена.',
      );
    }
    final recognizedTokens = <String>[];
    final operations = <VoiceAlignmentOperation>[];
    final referenceResults = <VoiceWordResult>[];
    final insertionResults = <VoiceInsertionResult>[];

    var referenceIndex = 0;
    var recognizedIndex = 0;

    for (final raw in rawAlignment) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final type = item['type']?.toString().toLowerCase();

      final rawReferenceWord = item['reference_word']?.toString();
      final rawRecognizedWord = item['recognized_word']?.toString();

      final hasReference = type != 'insertion' && rawReferenceWord != null;
      final hasRecognized = type != 'omission' && rawRecognizedWord != null;

      final currentReferenceIndex = hasReference ? referenceIndex : null;
      final currentRecognizedIndex = hasRecognized ? recognizedIndex : null;

      if (hasReference) referenceIndex++;
      if (hasRecognized) {
        recognizedTokens.add(rawRecognizedWord);
        recognizedIndex++;
      }

      final operationType = switch (type) {
        'match' => VoiceAlignmentOperationType.match,
        'substitution' => VoiceAlignmentOperationType.substitution,
        'omission' => VoiceAlignmentOperationType.omission,
        'insertion' => VoiceAlignmentOperationType.insertion,
        _ => null,
      };
      if (operationType == null) continue;

      operations.add(VoiceAlignmentOperation(
        type: operationType,
        referenceIndex: currentReferenceIndex,
        recognizedIndex: currentRecognizedIndex,
      ));

      if (operationType == VoiceAlignmentOperationType.insertion) {
        insertionResults.add(VoiceInsertionResult(
          text: rawRecognizedWord ?? '',
          confidence: _asDouble(item['confidence']),
          offsetMs: _asInt(item['offset_ms']),
          durationMs: _asInt(item['duration_ms']),
          recognizedIndex: currentRecognizedIndex,
        ));
        continue;
      }

      if (currentReferenceIndex == null ||
          currentReferenceIndex >= referenceTokens.length) {
        continue;
      }

      final status = switch (operationType) {
        VoiceAlignmentOperationType.match => VoiceWordStatus.correct,
        VoiceAlignmentOperationType.substitution => VoiceWordStatus.substitution,
        VoiceAlignmentOperationType.omission => VoiceWordStatus.omission,
        VoiceAlignmentOperationType.insertion => VoiceWordStatus.unverified,
      };

      referenceResults.add(VoiceWordResult(
        text: referenceTokens[currentReferenceIndex],
        status: status,
        recognizedWord: rawRecognizedWord,
        confidence: _asDouble(item['confidence']),
        offsetMs: _asInt(item['offset_ms']),
        durationMs: _asInt(item['duration_ms']),
      ));
    }

    // Keep one result per reference token. If comparison is unavailable, do
    // not fabricate a local comparison: show neutral, unverified words.
    if (!comparisonAvailable) {
      referenceResults
        ..clear()
        ..addAll(referenceTokens.map((word) => VoiceWordResult(
              text: word,
              status: VoiceWordStatus.unverified,
            )));
      operations.clear();
      insertionResults.clear();
      recognizedTokens.clear();
    }

    if (rawAzureWords is List) {
      var nextReferenceIndex = 0;
      for (final raw in rawAzureWords) {
        if (raw is! Map) continue;
        final word = Map<String, dynamic>.from(raw);
        final errorType = _normalizeErrorType(
          word['error_type']?.toString() ?? '',
        );
        if (errorType == 'insertion') continue;

        final azureWord = _normalizeWord(word['word']?.toString() ?? '');
        if (azureWord.isEmpty) {
          warnings.add('Azure вернул слово без текста; его оценка не применена.');
          continue;
        }

        // Use the canonical validation tokens here as well. The displayed
        // reference may contain a digit ("7"), while Azure returns "siedem".
        var matchedIndex = -1;
        for (var index = nextReferenceIndex;
            index < referenceResults.length;
            index++) {
          if (_normalizeWord(validationReferenceTokens[index]) == azureWord) {
            matchedIndex = index;
            break;
          }
        }

        if (matchedIndex < 0) {
          warnings.add(
            'Не удалось сопоставить слово Azure «${word['word']}» '
            'со следующим словом эталона; оценка не применена.',
          );
          continue;
        }

        if (matchedIndex > nextReferenceIndex) {
          warnings.add(
            'В последовательности Azure пропущено одно или несколько слов '
            'эталона перед «${word['word']}».',
          );
        }

        final existing = referenceResults[matchedIndex];
        final isMispronounced = errorType == 'mispronunciation';
        final azureStatus = switch (errorType) {
          'none' => VoiceWordStatus.correct,
          'mispronunciation' => VoiceWordStatus.mispronunciation,
          'omission' => VoiceWordStatus.omission,
          _ => VoiceWordStatus.unverified,
        };

        // Keep Azure and STT results independent. Neither assessment
        // overwrites the status produced by the other mechanism.
        referenceResults[matchedIndex] = VoiceWordResult(
          text: existing.text,
          status: existing.status,
          azureStatus: azureStatus,
          accuracy: _asDouble(word['accuracy_score']),
          mispronounced: isMispronounced,
          recognizedWord: existing.recognizedWord,
          confidence: existing.confidence,
          offsetMs: existing.offsetMs,
          durationMs: existing.durationMs,
        );
        nextReferenceIndex = matchedIndex + 1;
      }
    }

    final counts = comparison['counts'] is Map
        ? Map<String, dynamic>.from(comparison['counts'] as Map)
        : <String, dynamic>{};

    return VoiceTestAssessment(
      pronunciation: _asDouble(assessment['pronunciation_score']),
      accuracy: _asDouble(assessment['accuracy_score']),
      fluency: _asDouble(assessment['fluency_score']),
      completeness: _asDouble(assessment['completeness_score']),
      recognizedText: standardText,
      azureRecognizedText: azureText,
      referenceWords: List.unmodifiable(referenceResults),
      insertions: List.unmodifiable(insertionResults),
      alignment: VoiceTokenAlignmentResult(
        referenceTokens: List.unmodifiable(referenceTokens),
        recognizedTokens: List.unmodifiable(recognizedTokens),
        operations: List.unmodifiable(operations),
      ),
      comparisonAvailable: comparisonAvailable,
      comparisonError: _nestedErrorMessage(comparison),
      alignmentWarnings: List.unmodifiable(warnings),
      editDistance: _asInt(comparison['edit_distance']),
      serverMatchCount: _asInt(counts['matches']),
      serverSubstitutionCount: _asInt(counts['substitutions']),
      serverOmissionCount: _asInt(counts['omissions']),
      serverInsertionCount: _asInt(counts['insertions']),
      standardRecognitionConfidence: _asDouble(standard['confidence']),
    );
  }

  static bool _isCompleteAlignment({
    required List<dynamic> rawAlignment,
    required List<String> referenceTokens,
    required List<String> recognizedTokens,
  }) {
    final alignedReference = <String>[];
    final alignedRecognized = <String>[];

    for (final raw in rawAlignment) {
      if (raw is! Map) return false;
      final item = Map<String, dynamic>.from(raw);
      final type = item['type']?.toString().toLowerCase();
      final referenceWord = item['reference_word']?.toString();
      final recognizedWord = item['recognized_word']?.toString();

      switch (type) {
        case 'match':
        case 'substitution':
          if (referenceWord == null || recognizedWord == null) return false;
          alignedReference.add(referenceWord);
          alignedRecognized.add(recognizedWord);
          break;
        case 'omission':
          if (referenceWord == null || recognizedWord != null) return false;
          alignedReference.add(referenceWord);
          break;
        case 'insertion':
          if (referenceWord != null || recognizedWord == null) return false;
          alignedRecognized.add(recognizedWord);
          break;
        default:
          return false;
      }
    }

    if (alignedReference.length != referenceTokens.length ||
        alignedRecognized.length != recognizedTokens.length) {
      return false;
    }

    for (var index = 0; index < referenceTokens.length; index++) {
      if (_normalizeWord(alignedReference[index]) !=
          _normalizeWord(referenceTokens[index])) {
        return false;
      }
    }
    for (var index = 0; index < recognizedTokens.length; index++) {
      if (_normalizeWord(alignedRecognized[index]) !=
          _normalizeWord(recognizedTokens[index])) {
        return false;
      }
    }
    return true;
  }

  static List<String> _displayTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    return trimmed.split(RegExp(r'\s+'));
  }

  static String? _nestedErrorMessage(Map<String, dynamic> value) {
    final error = value['error'];
    if (error is Map) {
      final message = error['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
    }
    return null;
  }

  static String _normalizeWord(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"""^[.,!?;:()"'«»„“”]+|[.,!?;:()"'«»„“”]+$"""), '');

  static String _normalizeErrorType(String value) =>
      value.toLowerCase().replaceAll('_', '').replaceAll('-', '').replaceAll(' ', '');

  static double? _asDouble(dynamic value) =>
      value is num ? value.toDouble() : null;

  static int? _asInt(dynamic value) =>
      value is num ? value.toInt() : null;
}

class VoiceReferenceText extends StatelessWidget {
  final List<VoiceWordResult> words;

  const VoiceReferenceText({
    super.key,
    required this.words,
  });

  Color _statusBackground(VoiceWordStatus status) => switch (status) {
        VoiceWordStatus.correct => Colors.green.withValues(alpha: 0.20),
        VoiceWordStatus.mispronunciation =>
          Colors.yellow.withValues(alpha: 0.42),
        VoiceWordStatus.substitution =>
          Colors.deepPurple.withValues(alpha: 0.28),
        VoiceWordStatus.omission => Colors.red.withValues(alpha: 0.22),
        VoiceWordStatus.unverified => Colors.grey.withValues(alpha: 0.14),
      };

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final textColor = Theme.of(context).colorScheme.onSurface;

    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      final hasStt = word.status != VoiceWordStatus.unverified;
      final hasAzure = word.azureStatus != VoiceWordStatus.unverified;
      final sttColor = _statusBackground(word.status);
      final azureColor = _statusBackground(word.azureStatus);

      final Decoration decoration;
      if (hasStt && hasAzure && word.status != word.azureStatus) {
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              azureColor,
              azureColor,
              sttColor,
              sttColor,
            ],
            stops: const [0.0, 0.5, 0.5, 1.0],
          ),
        );
      } else {
        final background = hasStt
            ? sttColor
            : hasAzure
                ? azureColor
                : _statusBackground(VoiceWordStatus.unverified);
        decoration = BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(3),
        );
      }

      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: decoration,
          child: Text(
            word.text,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ));
      if (index != words.length - 1) {
        spans.add(const TextSpan(text: ' '));
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.8),
    );
  }
}
