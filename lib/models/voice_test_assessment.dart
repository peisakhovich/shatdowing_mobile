import 'package:flutter/material.dart';

enum VoiceWordStatus { correct, mispronunciation, omission }

enum _AlignmentOperation { match, substitution, omission, insertion }

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

    final reference = _tokenize(referenceText);
    final recognizedText = json['recognized_text']?.toString().trim() ?? '';
    final recognized = _tokenize(recognizedText);

    final statuses = List<VoiceWordStatus?>.filled(reference.length, null);
    final accuracies = List<double?>.filled(reference.length, null);
    final insertions = <String>[];

    // Main comparison is based on the actual recognized transcript.
    // This catches added words even when Azure does not label them
    // as "Insertion" in its word-level assessment.
    _alignWords(
      reference: reference,
      recognized: recognized,
      statuses: statuses,
      insertions: insertions,
    );

    // Azure word-level details are supplementary. In particular, Azure can
    // restore an omitted expected word in recognized_text, while still
    // reporting that omission in the "words" array.
    final rawWords = json['words'];
    if (rawWords is List) {
      var searchFrom = 0;

      for (final raw in rawWords) {
        if (raw is! Map) continue;

        final word = raw['word']?.toString().trim() ?? '';
        if (word.isEmpty) continue;

        final type = (raw['error_type']?.toString() ?? 'None').toLowerCase();
        final score = raw['accuracy_score'] is num
            ? (raw['accuracy_score'] as num).toDouble()
            : null;

        if (type == 'omission' || type == 'mispronunciation') {
          final target = _findReferenceWord(reference, word, searchFrom);
          if (target != null) {
            statuses[target] = type == 'omission'
                ? VoiceWordStatus.omission
                : VoiceWordStatus.mispronunciation;
            accuracies[target] = score;
            searchFrom = target + 1;
          }
        }

        // Keep Azure's explicit insertion only if the transcript alignment
        // did not already report the same word.
        if (type == 'insertion' &&
            !_containsNormalized(insertions, word)) {
          insertions.add(word);
        }
      }
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
          status: statuses[index] ?? VoiceWordStatus.correct,
          accuracy: accuracies[index],
        ),
      ),
      insertions: insertions,
    );
  }

  static void _alignWords({
    required List<String> reference,
    required List<String> recognized,
    required List<VoiceWordStatus?> statuses,
    required List<String> insertions,
  }) {
    final n = reference.length;
    final m = recognized.length;
    final costs = List.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
    );

    for (var i = n; i >= 0; i--) {
      for (var j = m; j >= 0; j--) {
        if (i == n && j == m) continue;
        if (i == n) {
          costs[i][j] = m - j;
        } else if (j == m) {
          costs[i][j] = n - i;
        } else {
          final substitutionCost =
              _normalize(reference[i]) == _normalize(recognized[j]) ? 0 : 1;
          final substitution = substitutionCost + costs[i + 1][j + 1];
          final omission = 1 + costs[i + 1][j];
          final insertion = 1 + costs[i][j + 1];

          costs[i][j] = [
            substitution,
            omission,
            insertion,
          ].reduce((a, b) => a < b ? a : b);
        }
      }
    }

    var i = 0;
    var j = 0;

    while (i < n || j < m) {
      if (i < n &&
          j < m &&
          _normalize(reference[i]) == _normalize(recognized[j]) &&
          costs[i][j] == costs[i + 1][j + 1]) {
        statuses[i] = VoiceWordStatus.correct;
        i++;
        j++;
        continue;
      }

      // Prefer an insertion when it gives an optimal alignment. This prevents
      // one extra spoken word from shifting the comparison of later words.
      if (j < m && costs[i][j] == 1 + costs[i][j + 1]) {
        insertions.add(recognized[j]);
        j++;
        continue;
      }

      if (i < n && costs[i][j] == 1 + costs[i + 1][j]) {
        statuses[i] = VoiceWordStatus.omission;
        i++;
        continue;
      }

      if (i < n && j < m) {
        statuses[i] = VoiceWordStatus.mispronunciation;
        i++;
        j++;
        continue;
      }

      if (i < n) {
        statuses[i] = VoiceWordStatus.omission;
        i++;
      } else if (j < m) {
        insertions.add(recognized[j]);
        j++;
      }
    }
  }

  static List<String> _tokenize(String text) {
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
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

  static bool _containsNormalized(List<String> words, String candidate) {
    final normalized = _normalize(candidate);
    return words.any((word) => _normalize(word) == normalized);
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
