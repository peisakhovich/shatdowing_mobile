import 'package:flutter/material.dart';

enum VoiceWordStatus { correct, mispronunciation, omission }

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

class VoiceTestAssessment {
  final double? pronunciation;
  final double? accuracy;
  final double? fluency;
  final double? completeness;
  final String recognizedText;
  final List<VoiceWordResult> referenceWords;
  final List<String> insertions;

  const VoiceTestAssessment({
    required this.pronunciation,
    required this.accuracy,
    required this.fluency,
    required this.completeness,
    required this.recognizedText,
    required this.referenceWords,
    required this.insertions,
  });

  factory VoiceTestAssessment.fromJson({
    required String referenceText,
    required Map<String, dynamic> json,
  }) {
    final rawAssessment = json['assessment'];
    final assessment = rawAssessment is Map
        ? Map<String, dynamic>.from(rawAssessment)
        : <String, dynamic>{};

    final reference = referenceText
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    final statuses = List<VoiceWordStatus?>.filled(reference.length, null);
    final accuracies = List<double?>.filled(reference.length, null);
    final insertions = <String>[];
    var cursor = 0;
    final rawWords = json['words'];

    if (rawWords is List) {
      for (final raw in rawWords) {
        if (raw is! Map) continue;

        final word = raw['word']?.toString().trim() ?? '';
        if (word.isEmpty) continue;

        final type = (raw['error_type']?.toString() ?? 'None').toLowerCase();
        final score = raw['accuracy_score'] is num
            ? (raw['accuracy_score'] as num).toDouble()
            : null;

        if (type == 'insertion') {
          insertions.add(word);
          continue;
        }

        if (cursor >= reference.length) {
          insertions.add(word);
          continue;
        }

        if (type == 'omission') {
          final match = _findReferenceWord(reference, word, cursor);
          final target = match ?? cursor;

          while (cursor < target) {
            statuses[cursor] = VoiceWordStatus.omission;
            cursor++;
          }

          statuses[target] = VoiceWordStatus.omission;
          cursor = target + 1;
          continue;
        }

        final match = _findReferenceWord(reference, word, cursor);

        if (match == null) {
          if (type == 'mispronunciation') {
            statuses[cursor] = VoiceWordStatus.mispronunciation;
            accuracies[cursor] = score;
            cursor++;
          } else {
            insertions.add(word);
          }
          continue;
        }

        while (cursor < match) {
          statuses[cursor] = VoiceWordStatus.omission;
          cursor++;
        }

        statuses[match] = type == 'mispronunciation'
            ? VoiceWordStatus.mispronunciation
            : VoiceWordStatus.correct;
        accuracies[match] = score;
        cursor = match + 1;
      }
    }

    if (rawWords is List && rawWords.isNotEmpty) {
      while (cursor < reference.length) {
        statuses[cursor] ??= VoiceWordStatus.omission;
        cursor++;
      }
    }

    return VoiceTestAssessment(
      pronunciation: _asDouble(assessment['pronunciation_score']),
      accuracy: _asDouble(assessment['accuracy_score']),
      fluency: _asDouble(assessment['fluency_score']),
      completeness: _asDouble(assessment['completeness_score']),
      recognizedText: json['recognized_text']?.toString().trim() ?? '',
      referenceWords: List.generate(
        reference.length,
        (index) => VoiceWordResult(
          text: reference[index],
          status: statuses[index] ?? VoiceWordStatus.correct,
          accuracy: accuracies[index],
        ),
      ),
      insertions: insertions,
    );
  }

  static int? _findReferenceWord(
    List<String> words,
    String candidate,
    int start,
  ) {
    final normalizedCandidate = _normalize(candidate);
    if (normalizedCandidate.isEmpty) return null;

    for (var index = start; index < words.length; index++) {
      if (_normalize(words[index]) == normalizedCandidate) {
        return index;
      }
    }

    return null;
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(
          RegExp(r'^[.,!?;:()\[\]{}"„”«»…—–-]+|[.,!?;:()\[\]{}"„”«»…—–-]+$'),
          '',
        );
  }

  static double? _asDouble(dynamic value) {
    return value is num ? value.toDouble() : null;
  }
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
        VoiceWordStatus.mispronunciation => Colors.deepOrange.shade700,
        VoiceWordStatus.omission => Colors.red.shade700,
      };

      final background = switch (word.status) {
        VoiceWordStatus.correct => Colors.green.withValues(alpha: 0.12),
        VoiceWordStatus.mispronunciation =>
          Colors.deepOrange.withValues(alpha: 0.14),
        VoiceWordStatus.omission => Colors.red.withValues(alpha: 0.12),
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
      style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.8),
    );
  }
}
