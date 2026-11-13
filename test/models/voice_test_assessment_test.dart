import 'package:flutter_test/flutter_test.dart';
import 'package:shadowing_mobile/models/voice_test_assessment.dart';

void main() {
  group('VoiceTestAssessment alignment interpretation', () {
    test('does not mark a transcript match as both present and omitted', () {
      final assessment = VoiceTestAssessment.fromJson(
        referenceText: 'Ja bardzo lubię kawę.',
        json: {
          'recognized_text': 'Ja bardzo lubię kawę.',
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {
              'word': 'bardzo',
              'error_type': 'Omission',
              'accuracy_score': 0,
            },
            {'word': 'lubię', 'error_type': 'None', 'accuracy_score': 98},
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 99},
          ],
        },
      );

      expect(
        assessment.referenceWords[1].status,
        VoiceWordStatus.correct,
      );
      expect(assessment.omissionCount, 0);
      expect(assessment.insertions, isEmpty);
      expect(assessment.alignmentWarnings, isNotEmpty);
    });

    test('keeps a genuine transcript omission', () {
      final assessment = VoiceTestAssessment.fromJson(
        referenceText: 'Ja bardzo lubię kawę.',
        json: {
          'recognized_text': 'Ja lubię kawę.',
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {
              'word': 'bardzo',
              'error_type': 'Omission',
              'accuracy_score': 0,
            },
            {'word': 'lubię', 'error_type': 'None', 'accuracy_score': 98},
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 99},
          ],
        },
      );

      expect(
        assessment.referenceWords[1].status,
        VoiceWordStatus.omission,
      );
      expect(assessment.omissionCount, 1);
      expect(assessment.insertions, isEmpty);
    });

    test('uses Azure mispronunciation and word score', () {
      final assessment = VoiceTestAssessment.fromJson(
        referenceText: 'Ja lubię kawę.',
        json: {
          'recognized_text': 'Ja lubię kawę.',
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {
              'word': 'lubię',
              'error_type': 'Mispronunciation',
              'accuracy_score': 54,
            },
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 98},
          ],
        },
      );

      expect(
        assessment.referenceWords[1].status,
        VoiceWordStatus.mispronunciation,
      );
      expect(assessment.referenceWords[1].accuracy, 54);
    });

    test('keeps repeated insertions as separate occurrences', () {
      final assessment = VoiceTestAssessment.fromJson(
        referenceText: 'Ja lubię kawę.',
        json: {
          'recognized_text': 'Ja bardzo bardzo lubię kawę.',
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {
              'word': 'bardzo',
              'error_type': 'Insertion',
              'accuracy_score': 91,
            },
            {
              'word': 'bardzo',
              'error_type': 'Insertion',
              'accuracy_score': 88,
            },
            {'word': 'lubię', 'error_type': 'None', 'accuracy_score': 98},
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 99},
          ],
        },
      );

      expect(assessment.insertions.length, 2);
      expect(
        assessment.insertions.map((item) => item.recognizedIndex).toSet(),
        {1, 2},
      );
      expect(
        assessment.insertions.map((item) => item.accuracy).toList(),
        [91.0, 88.0],
      );
    });

    test('does not invent a transcript insertion from Azure-only evidence', () {
      final assessment = VoiceTestAssessment.fromJson(
        referenceText: 'Ja lubię kawę.',
        json: {
          'recognized_text': 'Ja lubię kawę.',
          'words': [
            {'word': 'Ja', 'error_type': 'None', 'accuracy_score': 99},
            {
              'word': 'dodatkowo',
              'error_type': 'Insertion',
              'accuracy_score': 60,
            },
            {'word': 'lubię', 'error_type': 'None', 'accuracy_score': 98},
            {'word': 'kawę.', 'error_type': 'None', 'accuracy_score': 99},
          ],
        },
      );

      expect(assessment.insertions, isEmpty);
      expect(assessment.alignmentWarnings, isNotEmpty);
    });
  });
}
