import 'package:flutter_test/flutter_test.dart';
import 'package:shadowing_mobile/models/voice_test_assessment.dart';

void main() {
  group('VoiceTestAssessment API response', () {
    test('uses server alignment for matches, substitutions, omissions and insertions', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Dzień dobry, kupię chleb i mleko.',
        json: {
          'assessment': {
            'pronunciation_score': 85.6,
            'accuracy_score': 100.0,
            'fluency_score': 76.0,
            'completeness_score': 100.0,
          },
          'recognized_text': 'Dzień dobry. Kupię chleb i mleko.',
          'standard_recognition': {
            'success': true,
            'recognized_text': 'Dzień dobry kupię świeży chleb samochód i mleko',
            'confidence': 0.91,
          },
          'comparison': {
            'method': 'word_level_levenshtein',
            'edit_distance': 2,
            'counts': {
              'matches': 6,
              'substitutions': 0,
              'omissions': 0,
              'insertions': 2,
            },
            'alignment': [
              {'type': 'match', 'reference_word': 'Dzień', 'recognized_word': 'Dzień'},
              {'type': 'match', 'reference_word': 'dobry', 'recognized_word': 'dobry'},
              {'type': 'match', 'reference_word': 'kupię', 'recognized_word': 'kupię'},
              {'type': 'insertion', 'reference_word': null, 'recognized_word': 'świeży', 'confidence': 0.88},
              {'type': 'match', 'reference_word': 'chleb', 'recognized_word': 'chleb'},
              {'type': 'insertion', 'reference_word': null, 'recognized_word': 'samochód', 'confidence': 0.89},
              {'type': 'match', 'reference_word': 'i', 'recognized_word': 'i'},
              {'type': 'match', 'reference_word': 'mleko', 'recognized_word': 'mleko'},
            ],
          },
          'words': [
            {'word': 'Dzień', 'error_type': 'None', 'accuracy_score': 99},
            {'word': 'dobry', 'error_type': 'None', 'accuracy_score': 98},
            {'word': 'kupię', 'error_type': 'None', 'accuracy_score': 97},
            {'word': 'chleb', 'error_type': 'None', 'accuracy_score': 96},
            {'word': 'i', 'error_type': 'None', 'accuracy_score': 98},
            {'word': 'mleko', 'error_type': 'None', 'accuracy_score': 99},
          ],
        },
      );

      expect(result.comparisonAvailable, isTrue);
      expect(result.correctCount, 6);
      expect(result.insertionCount, 2);
      expect(result.insertions.map((item) => item.text),
          ['świeży', 'samochód']);
      expect(result.recognizedText,
          'Dzień dobry kupię świeży chleb samochód i mleko');
      expect(result.azureRecognizedText, 'Dzień dobry. Kupię chleb i mleko.');
      expect(result.pronunciation, 85.6);
    });

    test('keeps Azure pronunciation finding separate from structural substitution', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Ja lubię kawę.',
        json: {
          'assessment': {'pronunciation_score': 78},
          'standard_recognition': {
            'success': true,
            'recognized_text': 'Ja kocham kawę',
          },
          'comparison': {
            'counts': {
              'matches': 2,
              'substitutions': 1,
              'omissions': 0,
              'insertions': 0,
            },
            'alignment': [
              {'type': 'match', 'reference_word': 'Ja', 'recognized_word': 'Ja'},
              {'type': 'substitution', 'reference_word': 'lubię', 'recognized_word': 'kocham'},
              {'type': 'match', 'reference_word': 'kawę.', 'recognized_word': 'kawę'},
            ],
          },
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {'word': 'lubię', 'error_type': 'Mispronunciation', 'accuracy_score': 54},
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 98},
          ],
        },
      );

      expect(result.referenceWords[1].status, VoiceWordStatus.substitution);
      expect(result.referenceWords[1].azureStatus,
          VoiceWordStatus.mispronunciation);
      expect(result.referenceWords[1].mispronounced, isTrue);
      expect(result.mispronunciationCount, 1);
      expect(result.substitutionCount, 1);
    });

    test('matches Azure scores by word text and skips unmatched Azure tokens', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Ja lubię kawę.',
        json: {
          'standard_recognition': {
            'success': true,
            'recognized_text': 'Ja lubię kawę',
          },
          'comparison': {
            'counts': {
              'matches': 3,
              'substitutions': 0,
              'omissions': 0,
              'insertions': 0,
            },
            'alignment': [
              {'type': 'match', 'reference_word': 'Ja', 'recognized_word': 'Ja'},
              {'type': 'match', 'reference_word': 'lubię', 'recognized_word': 'lubię'},
              {'type': 'match', 'reference_word': 'kawę.', 'recognized_word': 'kawę'},
            ],
          },
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {'word': 'nieznane', 'error_type': 'None', 'accuracy_score': 10},
            {'word': 'lubię,', 'error_type': 'None', 'accuracy_score': 88},
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 97},
          ],
        },
      );

      expect(result.referenceWords[0].accuracy, 99);
      expect(result.referenceWords[1].accuracy, 88);
      expect(result.referenceWords[2].accuracy, 97);
      expect(result.alignmentWarnings, isNotEmpty);
    });

    test('accepts numeric formatting differences when structured STT words match alignment', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Mam 7 lat.',
        json: {
          'standard_recognition': {
            'success': true,
            'recognized_text': 'Mam 7 lat.',
            'words': [
              {'word': 'Mam', 'confidence': 0.98},
              {'word': 'siedem', 'confidence': 0.99},
              {'word': 'lat', 'confidence': 0.97},
            ],
          },
          'comparison': {
            'counts': {
              'matches': 3,
              'substitutions': 0,
              'omissions': 0,
              'insertions': 0,
            },
            'alignment': [
              {'type': 'match', 'reference_word': 'Mam', 'recognized_word': 'Mam'},
              {'type': 'match', 'reference_word': 'siedem', 'recognized_word': 'siedem'},
              {'type': 'match', 'reference_word': 'lat.', 'recognized_word': 'lat'},
            ],
          },
          'words': [
            {'word': 'Mam', 'error_type': 'None', 'accuracy_score': 100},
            {'word': 'siedem', 'error_type': 'None', 'accuracy_score': 100},
            {'word': 'lat', 'error_type': 'None', 'accuracy_score': 100},
          ],
        },
      );

      expect(result.comparisonAvailable, isTrue);
      expect(result.referenceWords.length, 3);
      expect(result.referenceWords.every(
        (word) => word.status == VoiceWordStatus.correct,
      ), isTrue);
      expect(result.referenceWords.every(
        (word) => word.azureStatus == VoiceWordStatus.correct,
      ), isTrue);
      expect(result.alignmentWarnings, isEmpty);
    });

    test('keeps Azure and STT statuses independent for split word colors', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Mam chodzę.',
        json: {
          'standard_recognition': {
            'success': true,
            'recognized_text': 'chodzi',
            'words': [
              {'word': 'chodzi', 'confidence': 0.5},
            ],
          },
          'comparison': {
            'counts': {
              'matches': 0,
              'substitutions': 1,
              'omissions': 1,
              'insertions': 0,
            },
            'alignment': [
              {'type': 'omission', 'reference_word': 'Mam', 'recognized_word': null},
              {'type': 'substitution', 'reference_word': 'chodzę.', 'recognized_word': 'chodzi'},
            ],
          },
          'words': [
            {'word': 'Mam', 'error_type': 'None', 'accuracy_score': 97},
            {'word': 'chodzę.', 'error_type': 'Omission', 'accuracy_score': 0},
          ],
        },
      );

      expect(result.comparisonAvailable, isTrue);
      expect(result.referenceWords[0].status, VoiceWordStatus.omission);
      expect(result.referenceWords[0].azureStatus, VoiceWordStatus.correct);
      expect(result.referenceWords[0].accuracy, 97);
      expect(result.referenceWords[1].status, VoiceWordStatus.substitution);
      expect(result.referenceWords[1].azureStatus, VoiceWordStatus.omission);
      expect(result.referenceWords[1].recognizedWord, 'chodzi');
    });

    test('rejects an incomplete server alignment instead of showing partial colors', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Ja lubię kawę.',
        json: {
          'standard_recognition': {
            'success': true,
            'recognized_text': 'Ja lubię kawę',
          },
          'comparison': {
            'counts': {
              'matches': 2,
              'substitutions': 0,
              'omissions': 0,
              'insertions': 0,
            },
            'alignment': [
              {'type': 'match', 'reference_word': 'Ja', 'recognized_word': 'Ja'},
              {'type': 'match', 'reference_word': 'lubię', 'recognized_word': 'lubię'},
            ],
          },
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {'word': 'lubię', 'error_type': 'None', 'accuracy_score': 98},
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 97},
          ],
        },
      );

      expect(result.comparisonAvailable, isFalse);
      expect(
        result.referenceWords.every(
          (word) => word.status == VoiceWordStatus.unverified,
        ),
        isTrue,
      );
      expect(result.alignmentWarnings, isNotEmpty);
      expect(result.referenceWords.every((word) => word.accuracy == null), isTrue);
    });

    test('does not fabricate comparison when standard recognition fails', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Ja lubię kawę.',
        json: {
          'assessment': {'pronunciation_score': 91},
          'recognized_text': 'Ja lubię kawę.',
          'standard_recognition': {
            'success': false,
            'error': {'message': 'Recognition unavailable'},
          },
          'comparison': {
            'success': false,
            'error': {'message': 'Text comparison unavailable'},
          },
        },
      );

      expect(result.comparisonAvailable, isFalse);
      expect(result.referenceWords.every(
          (word) => word.status == VoiceWordStatus.unverified), isTrue);
      expect(result.insertions, isEmpty);
      expect(result.integratedConclusion, contains('Текстовое сравнение'));
      expect(result.pronunciation, 91);
    });

    test('integrates the two analyses without inventing an averaged score', () {
      final result = VoiceTestAssessment.fromJson(
        referenceText: 'Dzień dobry.',
        json: {
          'assessment': {'pronunciation_score': 94},
          'standard_recognition': {
            'success': true,
            'recognized_text': 'Dzień dobry',
          },
          'comparison': {
            'counts': {
              'matches': 2,
              'substitutions': 0,
              'omissions': 0,
              'insertions': 0,
            },
            'alignment': [
              {'type': 'match', 'reference_word': 'Dzień', 'recognized_word': 'Dzień'},
              {'type': 'match', 'reference_word': 'dobry.', 'recognized_word': 'dobry'},
            ],
          },
          'words': [
            {'word': 'Dzień', 'error_type': 'None', 'accuracy_score': 99},
            {'word': 'dobry.', 'error_type': 'None', 'accuracy_score': 98},
          ],
        },
      );

      expect(result.integratedConclusion, contains('полностью совпал'));
      expect(result.integratedConclusion, contains('высокое'));
      expect(result.integratedConclusion, isNot(contains('средний балл')));
    });
  });
}
