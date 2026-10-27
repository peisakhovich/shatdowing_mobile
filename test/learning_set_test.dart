import 'package:flutter_test/flutter_test.dart';
import 'package:shadowing_mobile/models/learning_set.dart';

void main() {
  test('LearningSet converts JSON into Dart objects', () {
    final json = {
      'set': {
        'set_id': 69,
        'set_name': 'For thin client application',
        'set_description': 'Multi language shadowing session',
        'user_nickname': 'pga',
      },
      'items': [
        {
          'item_id': 1565,
          'phrase_text': 'Listen carefully to the words.',
          'translate_text': 'Słuchaj uważnie słów.',
          'pause_ms': 800,
          'speed': 1.0,
          'repeat_count': 1,
        },
      ],
      'state': {'current_index': 0},
    };

    final learningSet = LearningSet.fromJson(json);

    expect(learningSet.setDescription, 'Multi language shadowing session');
    expect(learningSet.items.first.translation, 'Słuchaj uważnie słów.');
    expect(learningSet.items.first.repeatCount, 1);

    expect(learningSet.setId, 69);
    expect(learningSet.setName, 'For thin client application');
    expect(learningSet.userNickname, 'pga');
    expect(learningSet.items.length, 1);
    expect(learningSet.items.first.phrase, 'Listen carefully to the words.');
    expect(learningSet.items.first.pauseBeforeTranslation, 800);
    expect(learningSet.items.first.speed, 1.0);
    expect(learningSet.currentIndex, 0);
  });
}
