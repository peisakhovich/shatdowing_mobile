/// The structural relationship between one reference phrase and one
/// recognized transcript.
enum VoiceAlignmentOperationType {
  match,
  substitution,
  omission,
  insertion,
}

/// One atomic alignment operation.
///
/// A reference index and a recognized index can each occur in exactly one
/// operation. This preserves the identity of repeated word occurrences.
class VoiceAlignmentOperation {
  final VoiceAlignmentOperationType type;
  final int? referenceIndex;
  final int? recognizedIndex;

  const VoiceAlignmentOperation({
    required this.type,
    this.referenceIndex,
    this.recognizedIndex,
  });

  @override
  String toString() {
    return 'VoiceAlignmentOperation('
        'type: $type, '
        'referenceIndex: $referenceIndex, '
        'recognizedIndex: $recognizedIndex)';
  }
}

/// Immutable result of aligning two word sequences.
class VoiceTokenAlignmentResult {
  final List<String> referenceTokens;
  final List<String> recognizedTokens;
  final List<VoiceAlignmentOperation> operations;

  const VoiceTokenAlignmentResult({
    required this.referenceTokens,
    required this.recognizedTokens,
    required this.operations,
  });

  List<VoiceAlignmentOperation> get matches =>
      operations.where(
        (operation) =>
            operation.type == VoiceAlignmentOperationType.match,
      ).toList(growable: false);

  List<VoiceAlignmentOperation> get substitutions =>
      operations.where(
        (operation) =>
            operation.type == VoiceAlignmentOperationType.substitution,
      ).toList(growable: false);

  List<VoiceAlignmentOperation> get omissions =>
      operations.where(
        (operation) =>
            operation.type == VoiceAlignmentOperationType.omission,
      ).toList(growable: false);

  List<VoiceAlignmentOperation> get insertions =>
      operations.where(
        (operation) =>
            operation.type == VoiceAlignmentOperationType.insertion,
      ).toList(growable: false);
}

/// Global sequence alignment for reference and recognized words.
///
/// The algorithm minimizes word-level edit distance:
/// - exact match: 0;
/// - substitution: 1;
/// - omission: 1;
/// - insertion: 1.
///
/// The complete sequences are aligned together. It never searches forward
/// for a matching spelling and therefore does not lose occurrence identity
/// when a word appears several times.
///
/// Deterministic tie-breaking:
/// 1. Preserve an exact match.
/// 2. Prefer an insertion, keeping later reference words aligned.
/// 3. Prefer an omission.
/// 4. Use a substitution when it is the remaining optimal operation.
///
/// For identical adjacent repetitions, the exact physical occurrence that
/// was omitted/inserted may be unknowable from text alone. The algorithm
/// chooses one stable alignment while preserving the correct total counts.
class VoiceTokenAlignment {
  VoiceTokenAlignment._();

  static VoiceTokenAlignmentResult align({
    required String referenceText,
    required String recognizedText,
  }) {
    return alignTokens(
      referenceTokens: tokenize(referenceText),
      recognizedTokens: tokenize(recognizedText),
    );
  }

  static VoiceTokenAlignmentResult alignTokens({
    required List<String> referenceTokens,
    required List<String> recognizedTokens,
  }) {
    final reference = List<String>.unmodifiable(referenceTokens);
    final recognized = List<String>.unmodifiable(recognizedTokens);

    final n = reference.length;
    final m = recognized.length;

    // dp[i][j] is the minimum edit cost for the remaining suffixes.
    final dp = List.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
    );

    for (var i = n; i >= 0; i--) {
      for (var j = m; j >= 0; j--) {
        if (i == n && j == m) {
          dp[i][j] = 0;
        } else if (i == n) {
          dp[i][j] = m - j;
        } else if (j == m) {
          dp[i][j] = n - i;
        } else {
          final substitutionCost =
              normalize(reference[i]) == normalize(recognized[j]) ? 0 : 1;

          final matchOrSubstitution =
              substitutionCost + dp[i + 1][j + 1];
          final omission = 1 + dp[i + 1][j];
          final insertion = 1 + dp[i][j + 1];

          var best = matchOrSubstitution;
          if (omission < best) best = omission;
          if (insertion < best) best = insertion;

          dp[i][j] = best;
        }
      }
    }

    final operations = <VoiceAlignmentOperation>[];
    var i = 0;
    var j = 0;

    while (i < n || j < m) {
      // Exact matches take priority, including repeated words.
      if (i < n &&
          j < m &&
          normalize(reference[i]) == normalize(recognized[j]) &&
          dp[i][j] == dp[i + 1][j + 1]) {
        operations.add(
          VoiceAlignmentOperation(
            type: VoiceAlignmentOperationType.match,
            referenceIndex: i,
            recognizedIndex: j,
          ),
        );
        i++;
        j++;
        continue;
      }

      // On an optimal tie, isolate an extra recognized token first.
      if (j < m && dp[i][j] == 1 + dp[i][j + 1]) {
        operations.add(
          VoiceAlignmentOperation(
            type: VoiceAlignmentOperationType.insertion,
            recognizedIndex: j,
          ),
        );
        j++;
        continue;
      }

      if (i < n && dp[i][j] == 1 + dp[i + 1][j]) {
        operations.add(
          VoiceAlignmentOperation(
            type: VoiceAlignmentOperationType.omission,
            referenceIndex: i,
          ),
        );
        i++;
        continue;
      }

      if (i < n &&
          j < m &&
          dp[i][j] == 1 + dp[i + 1][j + 1]) {
        operations.add(
          VoiceAlignmentOperation(
            type: VoiceAlignmentOperationType.substitution,
            referenceIndex: i,
            recognizedIndex: j,
          ),
        );
        i++;
        j++;
        continue;
      }

      // Defensive fallback: every branch consumes at least one token.
      if (i < n) {
        operations.add(
          VoiceAlignmentOperation(
            type: VoiceAlignmentOperationType.omission,
            referenceIndex: i,
          ),
        );
        i++;
      } else if (j < m) {
        operations.add(
          VoiceAlignmentOperation(
            type: VoiceAlignmentOperationType.insertion,
            recognizedIndex: j,
          ),
        );
        j++;
      }
    }

    final result = VoiceTokenAlignmentResult(
      referenceTokens: reference,
      recognizedTokens: recognized,
      operations: List.unmodifiable(operations),
    );

    _validate(result);
    return result;
  }

  static List<String> tokenize(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    return trimmed
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  /// Normalization affects comparison only; displayed source spelling stays
  /// unchanged. This deliberately does not perform stemming, translation,
  /// grammatical analysis, or semantic equivalence.
  static String normalize(String value) {
    return value.toLowerCase().replaceAll(
      RegExp(
        r'^[.,!?;:()\[\]{}"„”«»…—–-]+|'
        r'[.,!?;:()\[\]{}"„”«»…—–-]+$',
      ),
      '',
    );
  }

  static void _validate(VoiceTokenAlignmentResult result) {
    final referenceUsage =
        List<int>.filled(result.referenceTokens.length, 0);
    final recognizedUsage =
        List<int>.filled(result.recognizedTokens.length, 0);

    var nextReferenceIndex = 0;
    var nextRecognizedIndex = 0;

    for (final operation in result.operations) {
      final referenceIndex = operation.referenceIndex;
      final recognizedIndex = operation.recognizedIndex;

      // Operations must consume both input sequences from left to right.
      if (referenceIndex != null) {
        if (referenceIndex != nextReferenceIndex) {
          throw StateError('Reference tokens are not aligned in sequence order.');
        }
        nextReferenceIndex++;
      }

      if (recognizedIndex != null) {
        if (recognizedIndex != nextRecognizedIndex) {
          throw StateError('Recognized tokens are not aligned in sequence order.');
        }
        nextRecognizedIndex++;
      }

      switch (operation.type) {
        case VoiceAlignmentOperationType.match:
        case VoiceAlignmentOperationType.substitution:
          if (referenceIndex == null ||
              recognizedIndex == null ||
              referenceIndex < 0 ||
              referenceIndex >= referenceUsage.length ||
              recognizedIndex < 0 ||
              recognizedIndex >= recognizedUsage.length) {
            throw StateError('Invalid paired alignment operation.');
          }
          referenceUsage[referenceIndex]++;
          recognizedUsage[recognizedIndex]++;
          break;

        case VoiceAlignmentOperationType.omission:
          if (referenceIndex == null ||
              recognizedIndex != null ||
              referenceIndex < 0 ||
              referenceIndex >= referenceUsage.length) {
            throw StateError('Invalid omission operation.');
          }
          referenceUsage[referenceIndex]++;
          break;

        case VoiceAlignmentOperationType.insertion:
          if (referenceIndex != null ||
              recognizedIndex == null ||
              recognizedIndex < 0 ||
              recognizedIndex >= recognizedUsage.length) {
            throw StateError('Invalid insertion operation.');
          }
          recognizedUsage[recognizedIndex]++;
          break;
      }
    }

    if (nextReferenceIndex != result.referenceTokens.length ||
        nextRecognizedIndex != result.recognizedTokens.length) {
      throw StateError('Alignment did not consume both input sequences.');
    }

    if (referenceUsage.any((count) => count != 1)) {
      throw StateError(
        'Alignment invariant failed: every reference token must be used once.',
      );
    }

    if (recognizedUsage.any((count) => count != 1)) {
      throw StateError(
        'Alignment invariant failed: every recognized token must be used once.',
      );
    }
  }
}
