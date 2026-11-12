import 'package:flutter/material.dart';

enum VoiceWordStatus { correct, mispronunciation, omission }

class VoiceWordResult {
  final String text;
  final VoiceWordStatus status;
  /// Azure Pronunciation Assessment accuracy score (0-100).
  /// This is the service's per-word pronunciation accuracy, not ASR confidence.
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

  const VoiceInsertionResult({required this.text, this.accuracy});
}

class VoiceTestAssessment {
  final double? pronunciation;
  final double? accuracy;
  final double? fluency;
  final double? completeness;
  final String recognizedText;
  final List<VoiceWordResult> referenceWords;
  final List<VoiceInsertionResult> insertions;

  const VoiceTestAssessment({
    required this.pronunciation,
    required this.accuracy,
    required this.fluency,
    required this.completeness,
    required this.recognizedText,
    required this.referenceWords,
    required this.insertions,
  });

  int get correctCount =>
      referenceWords.where((word) => word.status == VoiceWordStatus.correct).length;
  int get mispronunciationCount => referenceWords
      .where((word) => word.status == VoiceWordStatus.mispronunciation).length;
  int get omissionCount =>
      referenceWords.where((word) => word.status == VoiceWordStatus.omission).length;

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
    final scores = List<double?>.filled(reference.length, null);
    final insertionResults = <VoiceInsertionResult>[];

    // Transcript alignment detects substitutions, omissions and additions
    // even when Azure's word-level error_type is absent.
    _alignTranscript(
      reference: reference,
      recognized: recognized,
      statuses: statuses,
      insertions: insertionResults,
    );

    // Azure word-level results are authoritative for its explicit miscues
    // and supply the quantitative accuracy score for individual words.
    // A reported omission overrides a transcript that ASR reconstructed
    // from context. Scores are retained for correct words as well.
    final rawWords = json['words'];
    if (rawWords is List) {
      var referenceCursor = 0;

      for (final raw in rawWords) {
        if (raw is! Map) continue;

        final word = raw['word']?.toString().trim() ?? '';
        if (word.isEmpty) continue;

        final type = (raw['error_type']?.toString() ?? 'None')
            .toLowerCase()
            .replaceAll('_', '');
        final score = _asDouble(raw['accuracy_score']);
        final isInsertion = type == 'insertion';

        if (isInsertion) {
          _addInsertion(insertionResults, word, score);
          continue;
        }

        final target = _findReferenceWord(reference, word, referenceCursor);
        if (target != null) {
          scores[target] = score ?? scores[target];

          if (type == 'omission') {
            statuses[target] = VoiceWordStatus.omission;
          } else if (type == 'mispronunciation') {
            statuses[target] = VoiceWordStatus.mispronunciation;
          } else if (statuses[target] == null) {
            statuses[target] = VoiceWordStatus.correct;
          }

          referenceCursor = target + 1;
          continue;
        }

        // Some Azure responses identify a mispronounced word without an
        // exact lexical match. Attach it to the next still-unmapped reference
        // word rather than silently losing its score.
        if (type == 'mispronunciation') {
          final next = _nextUnmapped(statuses, referenceCursor);
          if (next != null) {
            statuses[next] = VoiceWordStatus.mispronunciation;
            scores[next] = score ?? scores[next];
            referenceCursor = next + 1;
          }
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
          accuracy: scores[index],
        ),
      ),
      insertions: insertionResults,
    );
  }

  static void _alignTranscript({
    required List<String> reference,
    required List<String> recognized,
    required List<VoiceWordStatus?> statuses,
    required List<VoiceInsertionResult> insertions,
  }) {
    final n = reference.length;
    final m = recognized.length;
    final costs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

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
          costs[i][j] = [substitution, omission, insertion]
              .reduce((a, b) => a < b ? a : b);
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
        statuses[i] ??= VoiceWordStatus.correct;
        i++;
        j++;
        continue;
      }

      // Prefer an insertion on an optimal tie so later reference words stay
      // aligned instead of shifting because of one extra spoken word.
      if (j < m && costs[i][j] == 1 + costs[i][j + 1]) {
        _addInsertion(insertions, recognized[j], null);
        j++;
        continue;
      }

      if (i < n && costs[i][j] == 1 + costs[i + 1][j]) {
        statuses[i] ??= VoiceWordStatus.omission;
        i++;
        continue;
      }

      if (i < n && j < m) {
        statuses[i] ??= VoiceWordStatus.mispronunciation;
        i++;
        j++;
      } else if (i < n) {
        statuses[i] ??= VoiceWordStatus.omission;
        i++;
      } else if (j < m) {
        _addInsertion(insertions, recognized[j], null);
        j++;
      }
    }
  }

  static void _addInsertion(
    List<VoiceInsertionResult> insertions,
    String word,
    double? score,
  ) {
    final normalized = _normalize(word);
    final existing = insertions.indexWhere(
      (item) => _normalize(item.text) == normalized,
    );
    if (existing == -1) {
      insertions.add(VoiceInsertionResult(text: word, accuracy: score));
    } else if (insertions[existing].accuracy == null && score != null) {
      insertions[existing] = VoiceInsertionResult(text: word, accuracy: score);
    }
  }

  static int? _nextUnmapped(List<VoiceWordStatus?> statuses, int start) {
    for (var i = start; i < statuses.length; i++) {
      if (statuses[i] == null || statuses[i] == VoiceWordStatus.correct) {
        return i;
      }
    }
    return null;
  }

  static int? _findReferenceWord(
    List<String> words,
    String candidate,
    int start,
  ) {
    final normalizedCandidate = _normalize(candidate);
    if (normalizedCandidate.isEmpty) return null;
    for (var index = start; index < words.length; index++) {
      if (_normalize(words[index]) == normalizedCandidate) return index;
    }
    return null;
  }

  static List<String> _tokenize(String text) => text
      .trim()
      .split(RegExp(r'\\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  static String _normalize(String value) => value.toLowerCase().replaceAll(
        RegExp(r'^[.,!?;:()\\[\\]{}"„”«»…—–-]+|[.,!?;:()\\[\\]{}"„”«»…—–-]+$'),
        '',
      );

  static double? _asDouble(dynamic value) =>
      value is num ? value.toDouble() : null;
}

class VoiceReferenceText extends StatelessWidget {
  final List<VoiceWordResult> words;

  const VoiceReferenceText({super.key, required this.words});

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
