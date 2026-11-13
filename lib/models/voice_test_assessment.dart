import 'package:flutter/material.dart';

import 'voice_token_alignment.dart';

enum VoiceWordStatus {
  correct,
  mispronunciation,
  omission,
}

class VoiceWordResult {
  final String text;
  final VoiceWordStatus status;
  final double? accuracy;

  const VoiceWordResult({
    required this.text,
    required this.status,
    this.accuracy,
  });
}

class VoiceInsertionResult {
  final String text;
  final double? accuracy;
  final int? recognizedIndex;

  const VoiceInsertionResult({
    required this.text,
    this.accuracy,
    this.recognizedIndex,
  });
}

class VoiceTestAssessment {
  final double? pronunciation;
  final double? accuracy;
  final double? fluency;
  final double? completeness;
  final String recognizedText;
  final List<VoiceWordResult> referenceWords;
  final List<VoiceInsertionResult> insertions;
  final VoiceTokenAlignmentResult alignment;
  final List<String> alignmentWarnings;

  const VoiceTestAssessment({
    required this.pronunciation,
    required this.accuracy,
    required this.fluency,
    required this.completeness,
    required this.recognizedText,
    required this.referenceWords,
    required this.insertions,
    required this.alignment,
    this.alignmentWarnings = const [],
  });

  int get correctCount => referenceWords
      .where((word) => word.status == VoiceWordStatus.correct)
      .length;

  int get mispronunciationCount => referenceWords
      .where((word) => word.status == VoiceWordStatus.mispronunciation)
      .length;

  int get omissionCount => referenceWords
      .where((word) => word.status == VoiceWordStatus.omission)
      .length;

  factory VoiceTestAssessment.fromJson({
    required String referenceText,
    required Map<String, dynamic> json,
  }) {
    final rawAssessment = json['assessment'];
    final assessment = rawAssessment is Map
        ? Map<String, dynamic>.from(rawAssessment)
        : <String, dynamic>{};

    final recognizedText =
        json['recognized_text']?.toString().trim() ?? '';

    // The transcript alignment is the only source of structural operations.
    final alignment = VoiceTokenAlignment.align(
      referenceText: referenceText,
      recognizedText: recognizedText,
    );

    final reference = alignment.referenceTokens;
    final recognized = alignment.recognizedTokens;

    final statuses = List<VoiceWordStatus>.filled(
      reference.length,
      VoiceWordStatus.correct,
    );
    final scores = List<double?>.filled(reference.length, null);
    final insertionResults = <VoiceInsertionResult>[];

    for (final operation in alignment.operations) {
      switch (operation.type) {
        case VoiceAlignmentOperationType.match:
          break;

        case VoiceAlignmentOperationType.substitution:
          statuses[operation.referenceIndex!] =
              VoiceWordStatus.mispronunciation;
          break;

        case VoiceAlignmentOperationType.omission:
          statuses[operation.referenceIndex!] =
              VoiceWordStatus.omission;
          break;

        case VoiceAlignmentOperationType.insertion:
          final recognizedIndex = operation.recognizedIndex!;
          insertionResults.add(
            VoiceInsertionResult(
              text: recognized[recognizedIndex],
              recognizedIndex: recognizedIndex,
            ),
          );
          break;
      }
    }

    final warnings = <String>[];
    final rawWords = json['words'];

    if (rawWords is List) {
      _applyAzureWordData(
        rawWords: rawWords,
        reference: reference,
        statuses: statuses,
        scores: scores,
        insertions: insertionResults,
        warnings: warnings,
      );
    }

    return VoiceTestAssessment(
      pronunciation: _asDouble(assessment['pronunciation_score']),
      accuracy: _asDouble(assessment['accuracy_score']),
      fluency: _asDouble(assessment['fluency_score']),
      completeness: _asDouble(assessment['completeness_score']),
      recognizedText: recognizedText,
      referenceWords: List.generate(
        reference.length,
        (index) => VoiceWordResult(
          text: reference[index],
          status: statuses[index],
          accuracy: scores[index],
        ),
        growable: false,
      ),
      insertions: List.unmodifiable(insertionResults),
      alignment: alignment,
      alignmentWarnings: List.unmodifiable(warnings),
    );
  }

  /// Azure data enriches the transcript alignment; it does not replace it.
  ///
  /// Azure's word list can contain omission placeholders and insertion
  /// entries. We separate insertions, align the remaining Azure sequence to
  /// the reference as a whole, and attach scores through indexed operations.
  /// Azure mispronunciation evidence may refine a paired word's status.
  /// An Azure omission never silently turns a transcript match into a
  /// structural omission; such disagreement is retained as a warning.
  static void _applyAzureWordData({
    required List rawWords,
    required List<String> reference,
    required List<VoiceWordStatus> statuses,
    required List<double?> scores,
    required List<VoiceInsertionResult> insertions,
    required List<String> warnings,
  }) {
    final azureReferenceWords = <String>[];
    final azureReferenceEntries = <Map<String, dynamic>>[];
    final azureInsertionEntries = <Map<String, dynamic>>[];

    for (final raw in rawWords) {
      if (raw is! Map) continue;

      final entry = Map<String, dynamic>.from(raw);
      final word = entry['word']?.toString().trim() ?? '';
      if (word.isEmpty) continue;

      final errorType = _normalizeErrorType(
        entry['error_type']?.toString() ?? '',
      );

      if (errorType == 'insertion') {
        azureInsertionEntries.add(entry);
      } else {
        azureReferenceWords.add(word);
        azureReferenceEntries.add(entry);
      }
    }

    if (reference.isNotEmpty && azureReferenceWords.isNotEmpty) {
      final azureAlignment = VoiceTokenAlignment.alignTokens(
        referenceTokens: reference,
        recognizedTokens: azureReferenceWords,
      );

      for (final operation in azureAlignment.operations) {
        final referenceIndex = operation.referenceIndex;
        final azureIndex = operation.recognizedIndex;

        if (referenceIndex == null || azureIndex == null) {
          if (operation.type == VoiceAlignmentOperationType.omission) {
            warnings.add(
              'Azure word sequence has no entry for reference token '
              '#$referenceIndex.',
            );
          } else if (operation.type ==
              VoiceAlignmentOperationType.insertion) {
            warnings.add(
              'Azure returned an unpaired word: '
              '${azureReferenceWords[azureIndex!]}',
            );
          }
          continue;
        }

        final entry = azureReferenceEntries[azureIndex];
        final errorType = _normalizeErrorType(
          entry['error_type']?.toString() ?? '',
        );
        final score = _asDouble(entry['accuracy_score']);

        scores[referenceIndex] = score ?? scores[referenceIndex];

        if (errorType == 'mispronunciation') {
          if (statuses[referenceIndex] == VoiceWordStatus.omission) {
            warnings.add(
              'Azure pronunciation result conflicts with transcript '
              'omission at reference token #$referenceIndex.',
            );
          } else {
            statuses[referenceIndex] =
                VoiceWordStatus.mispronunciation;
          }
        } else if (errorType == 'omission' &&
            statuses[referenceIndex] != VoiceWordStatus.omission) {
          warnings.add(
            'Azure reported omission for reference token '
            '#$referenceIndex, but the recognized transcript aligned it '
            'to a spoken token.',
          );
        }
      }
    }

    // Repeated insertions are enriched one-to-one, never merged by spelling.
    final enrichedInsertionIndexes = <int>{};

    for (final entry in azureInsertionEntries) {
      final word = entry['word']?.toString().trim() ?? '';
      if (word.isEmpty) continue;

      final normalized = VoiceTokenAlignment.normalize(word);

      final insertionIndex = insertions.indexWhere((item) {
        return item.recognizedIndex != null &&
            !enrichedInsertionIndexes.contains(item.recognizedIndex) &&
            VoiceTokenAlignment.normalize(item.text) == normalized;
      });

      if (insertionIndex < 0) {
        warnings.add(
          'Azure reported an insertion not present in the transcript '
          'insertion list: $word',
        );
        continue;
      }

      final existing = insertions[insertionIndex];
      final recognizedIndex = existing.recognizedIndex!;
      enrichedInsertionIndexes.add(recognizedIndex);

      insertions[insertionIndex] = VoiceInsertionResult(
        text: existing.text,
        accuracy: _asDouble(entry['accuracy_score']) ?? existing.accuracy,
        recognizedIndex: recognizedIndex,
      );
    }
  }

  static String _normalizeErrorType(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
  }

  static double? _asDouble(dynamic value) =>
      value is num ? value.toDouble() : null;
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
        VoiceWordStatus.mispronunciation => Colors.amber.shade900,
        VoiceWordStatus.omission => Colors.red.shade700,
      };

      final background = switch (word.status) {
        VoiceWordStatus.correct =>
          Colors.green.withValues(alpha: 0.12),
        VoiceWordStatus.mispronunciation =>
          Colors.amber.withValues(alpha: 0.18),
        VoiceWordStatus.omission =>
          Colors.red.withValues(alpha: 0.12),
      };

      spans.add(
        TextSpan(
          text: '${word.text}${index == words.length - 1 ? '' : ' '}',
          style: TextStyle(
            color: color,
            backgroundColor: background,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(height: 1.8),
    );
  }
}
