import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/learning_item.dart';
import '../models/learning_set.dart';

class LocalSessionStorage {
  static const String _legacySessionDirectoryName = 'learning_session';
  static const String _sessionsDirectoryName = 'learning_sessions';
  static const String _sessionFileName = 'learning_set.json';
  static const String _audioDirectoryName = 'audio';
  static const String _currentIndexFileName = 'current_index.txt';

  final int? _ownerUserId;
  final int? _setId;

  LocalSessionStorage({this._ownerUserId, this._setId});

  /// Возвращает каталог текущей сессии.
  ///
  /// Если setId не указан, используется старый каталог
  /// learning_session для совместимости.
  ///
  /// Если setId указан, создаётся отдельный каталог
  /// для конкретного пользователя и набора.
  Future<Directory> _getSessionDirectory() async {
    final appDirectory = await getApplicationDocumentsDirectory();

    late final Directory directory;

    if (_setId == null) {
      directory = Directory(
        '${appDirectory.path}/$_legacySessionDirectoryName',
      );
    } else {
      final ownerDirectory = _ownerUserId == null
          ? 'guest'
          : 'user_$_ownerUserId';

      directory = Directory(
        '${appDirectory.path}/$_sessionsDirectoryName/'
        '$ownerDirectory/set_$_setId',
      );
    }

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<File> _getSessionFile() async {
    final directory = await _getSessionDirectory();

    return File('${directory.path}/$_sessionFileName');
  }

  Future<Directory> _getAudioDirectory() async {
    final sessionDirectory = await _getSessionDirectory();

    final directory = Directory(
      '${sessionDirectory.path}/$_audioDirectoryName',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<File> _getCurrentIndexFile() async {
    final directory = await _getSessionDirectory();

    return File('${directory.path}/$_currentIndexFileName');
  }

  /// Сохраняет учебный набор, его владельца и текущую позицию.
  ///
  /// ownerUserId == null означает гостевую сессию.
  Future<void> saveLearningSet(
    LearningSet learningSet, {
    int? ownerUserId,
  }) async {
    final json = <String, dynamic>{
      'session_owner_type': ownerUserId == null ? 'guest' : 'user',
      'session_owner_user_id': ownerUserId,
      'set': {
        'set_id': learningSet.setId,
        'set_name': learningSet.setName,
        'set_description': learningSet.setDescription,
        'user_nickname': learningSet.userNickname,
      },
      'items': learningSet.items.map((item) {
        return <String, dynamic>{
          'item_id': item.id,
          'phrase_text': item.phrase,
          'translate_text': item.translation,
          'phrase_code': item.phraseCode,
          'phrase_locale': item.phraseLocale,
          'translate_code': item.translateCode,
          'translate_locale': item.translateLocale,
          'pause_ms': item.pauseBeforeTranslation,
          'speed': item.speed,
          'repeat_count': item.repeatCount,
          'phrase_audio_path': item.phraseAudioPath,
          'translation_audio_path': item.translationAudioPath,
        };
      }).toList(),
      'state': {'current_index': learningSet.currentIndex},
    };

    final file = await _getSessionFile();

    await file.writeAsString(jsonEncode(json), flush: true);

    await saveCurrentIndex(learningSet.currentIndex);
  }

  /// Проверяет, принадлежит ли сохранённая сессия пользователю.
  Future<bool> isSessionOwnedByUser(int userId) async {
    final file = await _getSessionFile();

    if (!await file.exists()) {
      return false;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      return decoded['session_owner_type'] == 'user' &&
          decoded['session_owner_user_id'] == userId;
    } catch (_) {
      return false;
    }
  }

  /// Проверяет, является ли сохранённая сессия гостевой.
  Future<bool> isGuestSession() async {
    final file = await _getSessionFile();

    if (!await file.exists()) {
      return false;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      return decoded['session_owner_type'] == 'guest';
    } catch (_) {
      return false;
    }
  }

  /// Загружает учебный набор вместе с путями к локальным MP3.
  Future<LearningSet?> loadLearningSet() async {
    final file = await _getSessionFile();

    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Некорректный формат сохранённого учебного набора.',
      );
    }

    final savedSet = LearningSet.fromJson(decoded);
    final itemsJson = decoded['items'] as List<dynamic>;

    final items = <LearningItem>[];

    for (var i = 0; i < savedSet.items.length; i++) {
      final itemJson = itemsJson[i] as Map<String, dynamic>;
      final item = savedSet.items[i];

      items.add(
        LearningItem(
          id: item.id,
          phrase: item.phrase,
          translation: item.translation,
          phraseCode: item.phraseCode,
          phraseLocale: item.phraseLocale,
          translateCode: item.translateCode,
          translateLocale: item.translateLocale,
          pauseBeforeTranslation: item.pauseBeforeTranslation,
          speed: item.speed,
          repeatCount: item.repeatCount,
          phraseAudioPath: itemJson['phrase_audio_path'] as String? ?? '',
          translationAudioPath: itemJson['translation_audio_path'] as String?,
        ),
      );
    }

    final savedIndex = await _readCurrentIndex();
    final currentIndex = savedIndex ?? savedSet.currentIndex;

    final safeIndex = items.isEmpty
        ? 0
        : currentIndex.clamp(0, items.length - 1);

    return LearningSet(
      setId: savedSet.setId,
      setName: savedSet.setName,
      setDescription: savedSet.setDescription,
      userNickname: savedSet.userNickname,
      items: items,
      currentIndex: safeIndex,
    );
  }

  /// Сохраняет MP3 и возвращает путь к файлу.
  Future<String> saveAudio({
    required int itemId,
    required String audioType,
    required List<int> bytes,
  }) async {
    if (audioType != 'phrase' && audioType != 'translate') {
      throw ArgumentError.value(
        audioType,
        'audioType',
        'Допустимы только phrase и translate.',
      );
    }

    final directory = await _getAudioDirectory();
    final file = File('${directory.path}/${itemId}_$audioType.mp3');

    await file.writeAsBytes(bytes, flush: true);

    return file.path;
  }

  /// Возвращает путь к MP3, если файл существует.
  Future<String?> getAudioPath({
    required int itemId,
    required String audioType,
  }) async {
    if (audioType != 'phrase' && audioType != 'translate') {
      throw ArgumentError.value(
        audioType,
        'audioType',
        'Допустимы только phrase и translate.',
      );
    }

    final directory = await _getAudioDirectory();
    final file = File('${directory.path}/${itemId}_$audioType.mp3');

    if (!await file.exists()) {
      return null;
    }

    return file.path;
  }

  /// Сохраняет индекс текущего элемента.
  Future<void> saveCurrentIndex(int index) async {
    if (index < 0) {
      throw ArgumentError.value(index, 'index');
    }

    final file = await _getCurrentIndexFile();

    await file.writeAsString(index.toString(), flush: true);
  }

  /// Загружает индекс текущего элемента.
  Future<int> loadCurrentIndex() async {
    return await _readCurrentIndex() ?? 0;
  }

  Future<int?> _readCurrentIndex() async {
    final file = await _getCurrentIndexFile();

    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    final index = int.tryParse(content.trim());

    if (index == null || index < 0) {
      return null;
    }

    return index;
  }

  /// Удаляет локальную текущую учебную сессию и её аудиофайлы.
  Future<void> clearLearningSession() async {
    final directory = await _getSessionDirectory();

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Удаляет все локальные учебные сессии.
  ///
  /// Используется, например, при выходе из аккаунта.
  Future<void> clearAllLearningSessions() async {
    final appDirectory = await getApplicationDocumentsDirectory();

    final legacyDirectory = Directory(
      '${appDirectory.path}/$_legacySessionDirectoryName',
    );

    final sessionsDirectory = Directory(
      '${appDirectory.path}/$_sessionsDirectoryName',
    );

    if (await legacyDirectory.exists()) {
      await legacyDirectory.delete(recursive: true);
    }

    if (await sessionsDirectory.exists()) {
      await sessionsDirectory.delete(recursive: true);
    }
  }
}
