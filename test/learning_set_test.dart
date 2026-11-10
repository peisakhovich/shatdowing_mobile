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
          'phrase_code': 'pl',
          'phrase_locale': 'pl-PL',
          'translate_code': 'ru',
          'translate_locale': 'ru-RU',
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
    expect(learningSet.items.first.phraseCode, 'pl');
    expect(learningSet.items.first.phraseLocale, 'pl-PL');
    expect(learningSet.items.first.translateCode, 'ru');
    expect(learningSet.items.first.translateLocale, 'ru-RU');
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

  test('LearningItem supports legacy JSON without language fields', () {
    final json = {
      'item_id': 1,
      'phrase_text': 'Hello.',
      'translate_text': 'Привет.',
      'pause_ms': 500,
      'speed': 1.0,
      'repeat_count': 1,
    };

    final learningSet = LearningSet.fromJson({
      'set': {
        'set_id': 1,
        'set_name': 'Legacy',
        'set_description': '',
        'user_nickname': '',
      },
      'items': [json],
      'state': {'current_index': 0},
    });

    final item = learningSet.items.first;
    expect(item.phraseCode, isNull);
    expect(item.phraseLocale, isNull);
    expect(item.translateCode, isNull);
    expect(item.translateLocale, isNull);
  });
}
