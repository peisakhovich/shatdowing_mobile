import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/learning_item.dart';
import '../models/learning_set.dart';

class DefaultSessionService {
  static const String _sessionAssetPath =
      'assets/default_session/default_session.json';

  static const String _audioAssetDirectory = 'assets/default_session/audio';

  Future<LearningSet> loadDefaultSession() async {
    final jsonString = await rootBundle.loadString(_sessionAssetPath);

    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    final session = LearningSet.fromJson(json);

    final items = session.items.map((item) {
      final hasTranslation =
          item.translation != null && item.translation!.trim().isNotEmpty;

      return LearningItem(
        id: item.id,
        phrase: item.phrase,
        translation: item.translation,
        pauseBeforeTranslation: item.pauseBeforeTranslation,
        speed: item.speed,
        repeatCount: item.repeatCount,
        phraseAudioPath: '$_audioAssetDirectory/${item.id}_phrase.mp3',
        translationAudioPath: hasTranslation
            ? '$_audioAssetDirectory/${item.id}_translate.mp3'
            : null,
      );
    }).toList();

    return LearningSet(
      setId: session.setId,
      setName: session.setName,
      setDescription: session.setDescription,
      userNickname: session.userNickname,
      items: items,
      currentIndex: 0,
    );
  }
}
