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
  final VoiceWordStatus status;
  final double? accuracy;
  final bool mispronounced;
  final String? recognizedWord;
  final double? confidence;
  final int? offsetMs;
  final int? durationMs;

  const VoiceWordResult({
    required this.text,
    required this.status,
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
    final comparisonAvailable = standard['success'] == true &&
        comparison['success'] != false &&
        comparisonAlignment is List &&
        comparison['counts'] is Map;

    final standardText = standard['recognized_text']?.toString().trim() ?? '';
    final azureText = json['recognized_text']?.toString().trim() ?? '';

    // Tokenize only to preserve the user's original spelling and punctuation.
    // The actual match/substitution/omission/insertion decisions come solely
    // from comparison.alignment returned by the API.
    final referenceTokens = _displayTokens(referenceText);
    final recognizedTokens = <String>[];
    final operations = <VoiceAlignmentOperation>[];
    final referenceResults = <VoiceWordResult>[];
    final insertionResults = <VoiceInsertionResult>[];

    final rawAlignment = comparisonAlignment is List
        ? comparisonAlignment
        : const <dynamic>[];

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

    final warnings = <String>[];
    final rawAzureWords = json['words'];
    if (rawAzureWords is List && comparisonAvailable) {
      var azureReferenceIndex = 0;
      for (final raw in rawAzureWords) {
        if (raw is! Map) continue;
        final word = Map<String, dynamic>.from(raw);
        final errorType = _normalizeErrorType(
          word['error_type']?.toString() ?? '',
        );
        if (errorType == 'insertion') continue;
        if (azureReferenceIndex >= referenceResults.length) {
          warnings.add('Azure вернул больше слов, чем содержит эталон.');
          break;
        }

        final existing = referenceResults[azureReferenceIndex];
        final isMispronounced = errorType == 'mispronunciation';
        final azureStatus = isMispronounced &&
                existing.status == VoiceWordStatus.correct
            ? VoiceWordStatus.mispronunciation
            : existing.status;

        // Structural comparison status has priority over Azure's omission
        // flag. Azure contributes pronunciation evidence and word accuracy.
        referenceResults[azureReferenceIndex] = VoiceWordResult(
          text: existing.text,
          status: existing.status == VoiceWordStatus.omission
              ? existing.status
              : azureStatus,
          accuracy: _asDouble(word['accuracy_score']),
          mispronounced: isMispronounced,
          recognizedWord: existing.recognizedWord,
          confidence: existing.confidence,
          offsetMs: existing.offsetMs,
          durationMs: existing.durationMs,
        );
        azureReferenceIndex++;
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

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];

    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      final color = switch (word.status) {
        VoiceWordStatus.correct => Colors.green.shade700,
        VoiceWordStatus.mispronunciation => Colors.yellow.shade800,
        VoiceWordStatus.substitution => Colors.deepPurple.shade700,
        VoiceWordStatus.omission => Colors.red.shade700,
        VoiceWordStatus.unverified => Colors.grey.shade700,
      };
      final background = switch (word.status) {
        VoiceWordStatus.correct => Colors.green.withValues(alpha: 0.12),
        VoiceWordStatus.mispronunciation => Colors.yellow.withValues(alpha: 0.28),
        VoiceWordStatus.substitution => Colors.deepPurple.withValues(alpha: 0.14),
        VoiceWordStatus.omission => Colors.red.withValues(alpha: 0.12),
        VoiceWordStatus.unverified => Colors.grey.withValues(alpha: 0.10),
      };

      spans.add(TextSpan(
        text: '${word.text}${index == words.length - 1 ? '' : ' '}',
        style: TextStyle(
          color: color,
          backgroundColor: background,
          fontWeight: FontWeight.w600,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.8),
    );
  }
}
