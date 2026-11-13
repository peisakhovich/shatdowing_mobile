import 'package:flutter_test/flutter_test.dart';
import 'package:shadowing_mobile/models/voice_token_alignment.dart';

void main() {
  group('VoiceTokenAlignment', () {
    test('aligns an exact phrase', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Ja lubię dobrą kawę.',
        recognizedText: 'Ja lubię dobrą kawę.',
      );

      expect(result.matches.length, 4);
      expect(result.substitutions, isEmpty);
      expect(result.omissions, isEmpty);
      expect(result.insertions, isEmpty);
    });

    test('isolates an extra word and preserves later matches', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Ja lubię dobrą kawę.',
        recognizedText: 'Ja naprawdę lubię dobrą kawę.',
      );

      expect(result.matches.length, 4);
      expect(result.insertions.length, 1);
      expect(result.insertions.single.recognizedIndex, 1);
      expect(result.recognizedTokens[1], 'naprawdę');
      expect(result.omissions, isEmpty);
    });

    test('detects an omitted word', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Ja lubię dobrą kawę.',
        recognizedText: 'Ja lubię kawę.',
      );

      expect(result.omissions.length, 1);
      expect(result.omissions.single.referenceIndex, 2);
      expect(result.insertions, isEmpty);
    });

    test('represents a lexical substitution as one paired operation', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Ja lubię kawę.',
        recognizedText: 'Ja piję kawę.',
      );

      expect(result.substitutions.length, 1);
      expect(result.substitutions.single.referenceIndex, 1);
      expect(result.substitutions.single.recognizedIndex, 1);
      expect(result.omissions, isEmpty);
      expect(result.insertions, isEmpty);
    });

    test('handles a missing occurrence of a repeated word', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Ja bardzo bardzo lubię kawę.',
        recognizedText: 'Ja bardzo lubię kawę.',
      );

      expect(result.omissions.length, 1);
      expect(result.omissions.single.referenceIndex, 2);
      expect(result.insertions, isEmpty);
      expect(result.matches.length, 4);
    });

    test('handles an extra occurrence of a repeated word', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Ja bardzo lubię kawę.',
        recognizedText: 'Ja bardzo bardzo lubię kawę.',
      );

      expect(result.insertions.length, 1);
      expect(result.insertions.single.recognizedIndex, 2);
      expect(result.omissions, isEmpty);
      expect(result.matches.length, 4);
    });

    test('uses surrounding words to align repeated occurrences', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Dzisiaj jest piękny dzień i jest ciepło.',
        recognizedText: 'Dzisiaj jest piękny dzień i ciepło.',
      );

      expect(result.omissions.length, 1);
      expect(result.omissions.single.referenceIndex, 5);
      expect(result.insertions, isEmpty);
    });

    test('uses sequence context even when repeated-word counts are equal', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'A B A C',
        recognizedText: 'A A B C',
      );

      expect(result.insertions.length, 1);
      expect(result.insertions.single.recognizedIndex, 1);
      expect(result.omissions.length, 1);
      expect(result.omissions.single.referenceIndex, 2);
      expect(result.matches.length, 3);
    });

    test('ignores edge punctuation when comparing words', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Dzień dobry, jak się masz?',
        recognizedText: 'Dzień dobry jak się masz',
      );

      expect(result.matches.length, 5);
      expect(result.omissions, isEmpty);
      expect(result.insertions, isEmpty);
    });

    test('handles an empty recognized phrase', () {
      final result = VoiceTokenAlignment.align(
        referenceText: 'Ja lubię kawę.',
        recognizedText: '',
      );

      expect(result.omissions.length, 3);
      expect(result.insertions, isEmpty);
    });

    test('handles an empty reference phrase', () {
      final result = VoiceTokenAlignment.align(
        referenceText: '',
        recognizedText: 'Ja lubię kawę.',
      );

      expect(result.omissions, isEmpty);
      expect(result.insertions.length, 3);
    });

    test('every token is consumed by exactly one operation', () {
      final examples = [
        ('A B C D', 'A X B C D'),
        ('A B C D', 'A C D'),
        ('A B C D', 'A X C D'),
        ('A B A C', 'A A C'),
        ('A B A C', 'A B A A C'),
        ('A B C', 'C B A'),
        ('A A A B', 'A A B'),
        ('A A B A', 'A B A A'),
      ];

      for (final example in examples) {
        final result = VoiceTokenAlignment.align(
          referenceText: example.$1,
          recognizedText: example.$2,
        );

        _expectEveryTokenUsedExactlyOnce(result);
      }
    });
  });
}

void _expectEveryTokenUsedExactlyOnce(
  VoiceTokenAlignmentResult result,
) {
  final referenceUsage =
      List<int>.filled(result.referenceTokens.length, 0);
  final recognizedUsage =
      List<int>.filled(result.recognizedTokens.length, 0);

  for (final operation in result.operations) {
    if (operation.referenceIndex != null) {
      referenceUsage[operation.referenceIndex!]++;
    }
    if (operation.recognizedIndex != null) {
      recognizedUsage[operation.recognizedIndex!]++;
    }
  }

  expect(referenceUsage, everyElement(1));
  expect(recognizedUsage, everyElement(1));
}
