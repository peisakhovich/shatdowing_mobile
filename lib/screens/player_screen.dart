import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/bluetooth_audio_service.dart';
import '../models/learning_item.dart';
import '../models/learning_set.dart';
import '../models/player_scenario.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/local_session_storage.dart';
import '../services/player_config_service.dart';
import '../widgets/player/adaptive_text_window.dart';
import '../widgets/player/pause_settings.dart';
import '../widgets/player/player_controls.dart';
import '../services/default_session_service.dart';
import 'settings_screen.dart';
import '../services/user_session.dart';
import '../services/device_wake_lock.dart';
import '../services/scenario_pause_controller.dart';
import '../services/voice_test_service.dart';

class PlayerScreen extends StatefulWidget {
  final int setId;
  final bool useDefaultSession;

  // Вызывается после успешной загрузки новой сессии.
  final Future<void> Function()? onSessionReady;

  const PlayerScreen({
    super.key,
    this.setId = 69,
    this.useDefaultSession = true,
    this.onSessionReady,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlayerConfigService _configService = PlayerConfigService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  final ApiClient _apiClient = ApiClient();
  late LocalSessionStorage _localSessionStorage;
  final DefaultSessionService _defaultSessionService = DefaultSessionService();
  final ScenarioPauseController _pauseController = ScenarioPauseController();
  final VoiceTestService _voiceTestService = VoiceTestService();

  VoiceTestCancellationToken? _voiceTestCancellationToken;

  bool _isPaused = false;

  StreamSubscription<dynamic>? _bluetoothCommandSubscription;

  PlayerConfig? _config;
  PlayerScenario? _selectedScenario;

  List<LearningItem> _items = [];
  int _currentItemIndex = 0;

  String _phraseText = '';
  String _translateText = '';

  bool _isPlaying = false;
  bool _showTop = false;
  bool _showBottom = false;
  bool _randomizerEnabled = false;
  int _repeatMultiplier = 1;

  // Настройки пользователя не изменяют исходные данные LearningItem.
  double _pauseBeforeTranslationFactor = 1.0;
  int _pauseBetweenSentencesMs = 2000;

  int _playbackGeneration = 0;
  bool _isLoading = true;
  bool _isLoadingSet = true;

  String? _errorMessage;
  String? _setError;

  // Состояние отображения загрузки учебного набора и MP3.
  String _downloadSetName = '';
  String _downloadCurrentFile = 'Подготовка загрузки…';
  int _downloadCompleted = 0;
  int _downloadTotal = 0;

  // Фактически загруженный учебный набор.
  late int _activeSetId;
  String _currentSetName = '';
  String _currentSetDescription = '';

  // Владелец пользовательской сессии.
  // null означает гостевую сессию.
  int? _activeOwnerUserId;

  LearningItem? get _currentItem {
    if (_items.isEmpty ||
        _currentItemIndex < 0 ||
        _currentItemIndex >= _items.length) {
      return null;
    }

    return _items[_currentItemIndex];
  }

  int get _effectivePauseBeforeTranslationMs {
    final item = _currentItem;
    if (item == null) return 0;

    return (item.pauseBeforeTranslation * _pauseBeforeTranslationFactor)
        .round();
  }

  bool get _hasTranslation {
    final translation = _currentItem?.translation;
    return translation != null && translation.trim().isNotEmpty;
  }

  double get _downloadProgress {
    if (_downloadTotal <= 0) return 0;
    return (_downloadCompleted / _downloadTotal).clamp(0.0, 1.0);
  }

  /// Отменяет текущую голосовую проверку, если она выполняется.
  void _cancelVoiceTest() {
    final token = _voiceTestCancellationToken;
    _voiceTestCancellationToken = null;
    token?.cancel();
  }

  void _pauseScenario() {
    if (!_isPlaying || _isPaused) return;

    _isPaused = true;
    _pauseController.pause();

    // Останавливаем звук, сохраняя текущую позицию.
    // Сервис также запомнит паузу во время загрузки MP3.
    unawaited(_audioPlayerService.pause());

    BluetoothAudioService.handler.updatePlayingState(false);

    debugPrint('[BLUETOOTH] Scenario paused');
  }

  void _resumeScenario() {
    if (!_isPlaying || !_isPaused) return;

    _isPaused = false;
    _pauseController.resume();

    // Сервис сам определит, нужно ли продолжить
    // уже начатое воспроизведение или разрешить запуск MP3.
    unawaited(_audioPlayerService.resume());

    BluetoothAudioService.handler.updatePlayingState(true);

    debugPrint('[BLUETOOTH] Scenario resumed');
  }

  @override
  void initState() {
    super.initState();

    _bluetoothCommandSubscription = BluetoothAudioService.handler.customEvent
        .listen((event) {
          if (!mounted) return;

          debugPrint('[BLUETOOTH] Command received: $event');

          switch (event) {
            case 'pause':
              _pauseScenario();
              break;

            case 'play':
              _resumeScenario();
              break;

            case 'next':
              if (_items.isNotEmpty) {
                _navigateToItem(_currentItemIndex + 1);
              }
              break;

            case 'previous':
              if (_items.isNotEmpty) {
                _navigateToItem(_currentItemIndex - 1);
              }
              break;
          }
        });

    _activeSetId = widget.setId;
    _loadConfig();
    _loadLearningSet();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _configService.load();

      if (!mounted) return;

      setState(() {
        _config = config;
        _selectedScenario = config.defaultScenarioConfig;
        _isLoading = false;
      });

      _applyScenarioVisibility();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  /// Обновляет сведения о загрузке, если экран ещё существует.
  void _updateDownloadProgress({
    String? setName,
    String? currentFile,
    int? completed,
    int? total,
  }) {
    if (!mounted) return;

    setState(() {
      if (setName != null) _downloadSetName = setName;
      if (currentFile != null) _downloadCurrentFile = currentFile;
      if (completed != null) _downloadCompleted = completed;
      if (total != null) _downloadTotal = total;
    });
  }

  /// Загружает набор из локального хранилища.
  ///
  /// Если нужного набора нет или в нём отсутствует аудио,
  /// получает набор и MP3 через API и сохраняет их локально.
  Future<void> _loadLearningSet() async {
    if (mounted) {
      setState(() {
        _isLoadingSet = true;
        _setError = null;
        _downloadSetName = 'Проверка учебного набора';
        _downloadCurrentFile = 'Проверка локальных файлов…';
        _downloadCompleted = 0;
        _downloadTotal = 0;
      });
    }

    try {
      LearningSet? learningSet;

      final userSession = UserSession.instance;
      final account = userSession.account;
      final selectedSetId = userSession.selectedSetId;

      // 1. Определяем владельца и ID набора.
      if (account != null && !widget.useDefaultSession) {
        // Новый экран получил конкретный набор из Settings.
        // Используем именно его, не прежний selectedSetId.
        _activeOwnerUserId = account.userId;
        _activeSetId = widget.setId;
      } else if (account != null && selectedSetId != null) {
        _activeOwnerUserId = account.userId;
        _activeSetId = selectedSetId;
      } else {
        _activeOwnerUserId = null;
        _activeSetId = widget.setId;
      }

      // Используем отдельное локальное хранилище для каждого набора.
      _localSessionStorage = LocalSessionStorage(
        ownerUserId: _activeOwnerUserId,
        setId: _activeSetId,
      );

      // 2. Создаём хранилище именно для этого пользователя и набора.
      _localSessionStorage = LocalSessionStorage(
        ownerUserId: _activeOwnerUserId,
        setId: _activeSetId,
      );

      // 2. Проверяем локальную сессию только для её владельца.
      if (_activeOwnerUserId != null) {
        final cachedSet = await _localSessionStorage.loadLearningSet();

        final isOwner = await _localSessionStorage.isSessionOwnedByUser(
          _activeOwnerUserId!,
        );

        if (cachedSet != null && isOwner && cachedSet.setId == _activeSetId) {
          _updateDownloadProgress(
            setName: cachedSet.setName,
            currentFile: 'Проверка сохранённых аудиофайлов…',
          );

          learningSet = await _restoreCachedSetWithAudio(cachedSet);
        } else if (cachedSet != null) {
          // Локальные данные принадлежат другому пользователю
          // или относятся к другому набору.
          await _localSessionStorage.clearLearningSession();
        }
      }

      // 3. Если это гостевая сессия, загружаем встроенный набор.
      if (learningSet == null &&
          _activeOwnerUserId == null &&
          widget.useDefaultSession) {
        _updateDownloadProgress(
          setName: 'Стартовый учебный набор',
          currentFile: 'Загрузка встроенного набора…',
        );

        learningSet = await _defaultSessionService.loadDefaultSession();
      }

      // 4. Если пользователь выбрал свой набор,
      // загружаем его через API.
      learningSet ??= await _downloadAndCacheLearningSet();

      if (learningSet.items.isEmpty) {
        throw const FormatException('Учебный набор не содержит элементов.');
      }

      if (!mounted) return;

      setState(() {
        _activeSetId = learningSet!.setId;
        _currentSetName = learningSet.setName;
        _currentSetDescription = learningSet.setDescription;

        _items = learningSet.items;
        _currentItemIndex = learningSet.currentIndex;
        _updateCurrentTexts();
        _isLoadingSet = false;
      });

      // Новая сессия полностью загружена.
      // Теперь можно переключить приложение со старого плеера.
      if (widget.onSessionReady != null) {
        try {
          await widget.onSessionReady!.call();
        } catch (callbackError) {
          debugPrint('[PLAYER] Session switch callback failed: $callbackError');
        }
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _setError = error.toString();
        _isLoadingSet = false;
        _downloadCurrentFile = 'Загрузка прервана';
      });
    }
  }

  /// Проверяет, что локальный набор содержит все необходимые MP3.
  ///
  /// Возвращает null, если хотя бы одного файла не хватает.
  Future<LearningSet?> _restoreCachedSetWithAudio(LearningSet savedSet) async {
    final restoredItems = <LearningItem>[];

    for (final item in savedSet.items) {
      final phrasePath = await _localSessionStorage.getAudioPath(
        itemId: item.id,
        audioType: 'phrase',
      );

      if (phrasePath == null) {
        return null;
      }

      String? translationPath;

      final translation = item.translation;
      if (translation != null && translation.trim().isNotEmpty) {
        translationPath = await _localSessionStorage.getAudioPath(
          itemId: item.id,
          audioType: 'translate',
        );

        if (translationPath == null) {
          return null;
        }
      }

      restoredItems.add(
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
          phraseAudioPath: phrasePath,
          translationAudioPath: translationPath,
        ),
      );
    }

    return LearningSet(
      setId: savedSet.setId,
      setName: savedSet.setName,
      setDescription: savedSet.setDescription,
      userNickname: savedSet.userNickname,
      items: restoredItems,
      currentIndex: savedSet.currentIndex,
    );
  }

  /// Загружает набор и необходимые MP3.
  ///
  /// Уже сохранённые файлы пропускаются. После каждого найденного или
  /// загруженного файла обновляется прогресс на экране.
  Future<LearningSet> _downloadAndCacheLearningSet() async {
    await DeviceWakeLock.acquire();

    try {
      return await _downloadAndCacheLearningSetInternal();
    } finally {
      await DeviceWakeLock.release();
    }
  }

  Future<LearningSet> _downloadAndCacheLearningSetInternal() async {
    _updateDownloadProgress(
      currentFile: 'Получение списка элементов с сервера…',
    );

    final apiSet = await _apiClient.getLearningSet(_activeSetId);

    if (apiSet.items.isEmpty) {
      throw const FormatException('API вернул набор без учебных элементов.');
    }

    final totalAudioFiles = apiSet.items.fold<int>(
      0,
      (total, item) =>
          total +
          1 +
          ((item.translation != null && item.translation!.trim().isNotEmpty)
              ? 1
              : 0),
    );

    _updateDownloadProgress(
      setName: apiSet.setName,
      currentFile: 'Подготовка аудиофайлов…',
      completed: 0,
      total: totalAudioFiles,
    );

    final cachedItems = <LearningItem>[];
    var completedAudioFiles = 0;

    for (var index = 0; index < apiSet.items.length; index++) {
      final item = apiSet.items[index];
      final itemLabel = 'Элемент ${index + 1} из ${apiSet.items.length}';

      // Сначала проверяем, нет ли уже сохранённого MP3 фразы.
      var phrasePath = await _localSessionStorage.getAudioPath(
        itemId: item.id,
        audioType: 'phrase',
      );

      if (phrasePath == null) {
        _updateDownloadProgress(
          currentFile: '$itemLabel: загрузка оригинала',
          completed: completedAudioFiles,
        );

        final phraseBytes = await _apiClient.getItemAudio(
          setId: _activeSetId,
          itemId: item.id,
          audioType: 'phrase',
        );

        phrasePath = await _localSessionStorage.saveAudio(
          itemId: item.id,
          audioType: 'phrase',
          bytes: phraseBytes,
        );
      }

      completedAudioFiles++;
      _updateDownloadProgress(
        currentFile: '$itemLabel: оригинал сохранён',
        completed: completedAudioFiles,
      );

      // Перевод может отсутствовать.
      String? translationPath;
      final translation = item.translation;

      if (translation != null && translation.trim().isNotEmpty) {
        translationPath = await _localSessionStorage.getAudioPath(
          itemId: item.id,
          audioType: 'translate',
        );

        if (translationPath == null) {
          _updateDownloadProgress(
            currentFile: '$itemLabel: загрузка перевода',
            completed: completedAudioFiles,
          );

          final translationBytes = await _apiClient.getItemAudio(
            setId: _activeSetId,
            itemId: item.id,
            audioType: 'translate',
          );

          translationPath = await _localSessionStorage.saveAudio(
            itemId: item.id,
            audioType: 'translate',
            bytes: translationBytes,
          );
        }

        completedAudioFiles++;
        _updateDownloadProgress(
          currentFile: '$itemLabel: перевод сохранён',
          completed: completedAudioFiles,
        );
      }

      cachedItems.add(
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
          phraseAudioPath: phrasePath,
          translationAudioPath: translationPath,
        ),
      );
    }

    // Новый загруженный набор начинается с первого элемента.
    final cachedSet = LearningSet(
      setId: apiSet.setId,
      setName: apiSet.setName,
      setDescription: apiSet.setDescription,
      userNickname: apiSet.userNickname,
      items: cachedItems,
      currentIndex: 0,
    );

    _updateDownloadProgress(currentFile: 'Сохранение данных набора…');

    await _localSessionStorage.saveLearningSet(
      cachedSet,
      ownerUserId: _activeOwnerUserId,
    );

    _updateDownloadProgress(
      currentFile: 'Загрузка завершена',
      completed: totalAudioFiles,
    );

    return cachedSet;
  }

  /// Сохраняет позицию элемента без прерывания воспроизведения.
  Future<void> _saveCurrentIndex(int index) async {
    // Гостевую позицию не сохраняем в пользовательскую сессию.
    if (_activeOwnerUserId == null) return;

    try {
      await _localSessionStorage.saveCurrentIndex(index);
    } catch (error) {
      debugPrint('Не удалось сохранить позицию: $error');
    }
  }

  void _updateCurrentTexts() {
    final item = _currentItem;

    _phraseText = item?.phrase ?? '';
    _translateText = item?.translation ?? '';

    BluetoothAudioService.handler.updateTrack(
      title: _phraseText,
      trackNumber: _currentItemIndex + 1,
      totalTracks: _items.length,
    );
  }

  void _selectScenario(String? key) {
    if (key == null || _config == null) return;

    _cancelVoiceTest();

    final scenario = _config!.scenarios[key];
    if (scenario == null) return;

    setState(() {
      _playbackGeneration++;
      _isPlaying = false;
      _selectedScenario = scenario;
      _showTop = false;
      _showBottom = false;
    });

    unawaited(_audioPlayerService.stop());
    _applyScenarioVisibility();
  }

  void _applyScenarioVisibility() {
    final scenario = _selectedScenario;
    if (scenario == null || !mounted) return;

    final firstAction = scenario.actions.firstOrNull;
    if (firstAction == null) return;

    setState(() {
      if (firstAction.action == 'SHOW') {
        if (firstAction.target == 'top') {
          _showTop = true;
        }

        if (firstAction.target == 'bottom' && _hasTranslation) {
          _showBottom = true;
        }
      } else if (firstAction.action == 'HIDE') {
        if (firstAction.target == 'top') {
          _showTop = false;
        }

        if (firstAction.target == 'bottom') {
          _showBottom = false;
        }
      }
    });
  }

  /// Останавливает старую сессию перед переключением на новую.
  Future<void> _stopForSessionReplacement() async {
    _cancelVoiceTest();
    _playbackGeneration++;

    _pauseController.reset();

    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }

    await _audioPlayerService.stop();

    BluetoothAudioService.handler.updatePlayingState(false);

    debugPrint('[PLAYER] Previous session stopped');
  }

  void _togglePlayback() {
    // Обычная остановка кнопкой Stop.
    if (_isPlaying) {
      _cancelVoiceTest();
      setState(() {
        _playbackGeneration++;
        _isPlaying = false;
        _isPaused = false;
      });

      // Снимаем Bluetooth-паузу и сбрасываем её состояние.
      _pauseController.reset();

      // Останавливаем MP3 и обновляем состояние MediaSession.
      unawaited(_audioPlayerService.stop());
      BluetoothAudioService.handler.updatePlayingState(false);

      return;
    }

    if (_items.isEmpty) return;

    // Перед новым запуском убираем возможное старое состояние паузы.
    _pauseController.reset();
    _isPaused = false;

    final generation = ++_playbackGeneration;

    setState(() {
      _isPlaying = true;
    });

    BluetoothAudioService.handler.updatePlayingState(true);

    unawaited(_runAllItems(generation));
  }

  /// Останавливает текущий сценарий и выбирает другой элемент.
  /// Автоматически продолжает воспроизведение, если оно было активно.
  void _navigateToItem(int index) {
    if (_items.isEmpty) return;

    final targetIndex = index.clamp(0, _items.length - 1).toInt();
    final wasPlaying = _isPlaying;

    _cancelVoiceTest();
    _playbackGeneration++;

    unawaited(_audioPlayerService.stop());

    setState(() {
      _currentItemIndex = targetIndex;
      _updateCurrentTexts();

      _showTop = false;
      _showBottom = false;
      _isPlaying = wasPlaying;
    });

    unawaited(_saveCurrentIndex(targetIndex));

    _applyScenarioVisibility();

    if (wasPlaying) {
      final generation = ++_playbackGeneration;
      unawaited(_runAllItems(generation));
    }
  }

  bool _isPlaybackCancelled(int generation) {
    return !mounted || !_isPlaying || generation != _playbackGeneration;
  }

  /// Ожидание с учётом Bluetooth-паузы.
  /// Время, проведённое на паузе, не учитывается.
  Future<void> _executeWait(Duration duration, int generation) async {
    if (duration <= Duration.zero) return;

    await _pauseController.wait(
      duration,
      isCancelled: () => _isPlaybackCancelled(generation),
    );
  }

  Duration _getWaitDuration(ScenarioAction action) {
    switch (action.source) {
      case 'pause_before_translation':
        final item = _currentItem;

        if (item == null) {
          throw StateError('Учебный элемент ещё не загружен.');
        }

        if (!_hasTranslation) {
          return Duration.zero;
        }

        return Duration(milliseconds: _effectivePauseBeforeTranslationMs);

      case 'pause_between_sentences':
        return Duration(milliseconds: _pauseBetweenSentencesMs);

      default:
        throw FormatException('Неизвестный источник паузы: ${action.source}');
    }
  }

  /// Возвращает путь к полному локальному MP3-файлу.
  ///
  /// В отличие от playBytes(), воспроизведение по пути не перезаписывает
  /// общий временный файл audio_preview.mp3 перед каждым запуском.
  Future<String> _getAudioPath({
    required int itemId,
    required String audioType,
  }) async {
    final item = _items.firstWhere((item) => item.id == itemId);

    // Встроенный набор использует аудиофайлы из assets.
    if (item.phraseAudioPath.startsWith('assets/')) {
      final assetPath = audioType == 'phrase'
          ? item.phraseAudioPath
          : item.translationAudioPath;

      if (assetPath == null || assetPath.isEmpty) {
        throw StateError('Для элемента $itemId отсутствует аудио: $audioType.');
      }

      return assetPath;
    }

    // Пользовательский набор использует локальные MP3
    // или загружает недостающие файлы через API.
    final localPath = await _localSessionStorage.getAudioPath(
      itemId: itemId,
      audioType: audioType,
    );

    if (localPath != null) {
      final localFile = File(localPath);
      if (await localFile.exists() && await localFile.length() > 0) {
        return localPath;
      }
    }

    final bytes = await _apiClient.getItemAudio(
      setId: _activeSetId,
      itemId: itemId,
      audioType: audioType,
    );

    if (bytes.isEmpty) {
      throw StateError(
        'Сервер вернул пустой MP3 для элемента $itemId ($audioType).',
      );
    }

    return _localSessionStorage.saveAudio(
      itemId: itemId,
      audioType: audioType,
      bytes: bytes,
    );
  }

  Future<void> _playScenarioAudio(ScenarioAction action, int generation) async {
    final item = _currentItem;

    if (item == null) {
      throw StateError('Учебный элемент ещё не загружен.');
    }

    final String audioType;

    switch (action.source) {
      case 'phrase_audio':
        audioType = 'phrase';
        break;

      case 'translate_audio':
        if (!_hasTranslation) return;
        audioType = 'translate';
        break;

      default:
        throw FormatException('Неизвестный источник аудио: ${action.source}');
    }

    final audioPath = await _getAudioPath(
      itemId: item.id,
      audioType: audioType,
    );

    if (_isPlaybackCancelled(generation)) return;

    // Не начинаем воспроизведение, пока действует Bluetooth-пауза.
    await _pauseController.waitWhilePaused();

    if (_isPlaybackCancelled(generation)) return;

    if (audioPath.startsWith('assets/')) {
      await _audioPlayerService.playAsset(audioPath);
    } else {
      await _audioPlayerService.playFile(audioPath);
    }
  }

  /// Выполняет голосовую проверку текущей фразы.
  /// Результат отображается в существующем поле перевода.
  Future<void> _executeVoiceTest(int generation) async {
    final item = _currentItem;

    if (item == null) {
      throw StateError('Учебный элемент ещё не загружен.');
    }

    final locale = item.phraseLocale;
    if (locale == null || locale.trim().isEmpty) {
      _stopVoiceTestWithMessage(
        'Для этой фразы не задана языковая локаль.',
        generation,
      );
      return;
    }

    final token = VoiceTestCancellationToken();
    _voiceTestCancellationToken = token;

    try {
      final result = await _voiceTestService.execute(
        request: VoiceTestRequest(
          referenceText: item.phrase,
          locale: locale,
        ),
        cancellationToken: token,
      );

      if (!mounted ||
          _isPlaybackCancelled(generation) ||
          token.isCancelled ||
          !identical(_voiceTestCancellationToken, token)) {
        return;
      }

      if (!result.success) {
        _stopVoiceTestWithMessage(
          result.errorMessage ?? 'Не удалось выполнить голосовую проверку.',
          generation,
        );
        return;
      }

      final resultText = result.resultText?.trim();
      if (resultText == null || resultText.isEmpty) {
        _stopVoiceTestWithMessage(
          'Голосовая проверка не вернула результат.',
          generation,
        );
        return;
      }

      setState(() {
        _translateText = resultText;
        _showBottom = true;
      });

      await _executeWait(
        Duration(milliseconds: _pauseBetweenSentencesMs),
        generation,
      );
    } finally {
      if (identical(_voiceTestCancellationToken, token)) {
        _voiceTestCancellationToken = null;
      }
    }
  }

  /// Показывает сообщение и останавливает сценарий без авто-перехода.
  void _stopVoiceTestWithMessage(String message, int generation) {
    if (!mounted || generation != _playbackGeneration) return;

    setState(() {
      _translateText = message;
      _showBottom = true;
      _isPlaying = false;
      _isPaused = false;
      _playbackGeneration++;
    });

    _pauseController.reset();
    BluetoothAudioService.handler.updatePlayingState(false);
  }

  Future<void> _runCurrentScenario(int generation) async {
    final scenario = _selectedScenario;
    if (scenario == null) return;

    for (final action in scenario.actions) {
      if (_isPlaybackCancelled(generation)) return;

      // Если включена Bluetooth-пауза, ждём её снятия.
      await _pauseController.waitWhilePaused();

      if (_isPlaybackCancelled(generation)) return;

      switch (action.action) {
        case 'SHOW':
          if (action.target == 'bottom' && !_hasTranslation) {
            break;
          }

          setState(() {
            if (action.target == 'top') {
              _showTop = true;
            }

            if (action.target == 'bottom') {
              _showBottom = true;
            }
          });
          break;

        case 'HIDE':
          setState(() {
            if (action.target == 'top') {
              _showTop = false;
            }

            if (action.target == 'bottom') {
              _showBottom = false;
            }
          });
          break;

        case 'WAIT':
          final duration = _getWaitDuration(action);

          debugPrint(
            '[PAUSE START] item=${_currentItemIndex + 1}, '
            'source=${action.source}, '
            'duration=${duration.inMilliseconds} ms',
          );

          await _executeWait(duration, generation);

          debugPrint(
            '[PAUSE END] item=${_currentItemIndex + 1}, '
            'source=${action.source}',
          );
          break;

        case 'PLAY':
          await _playScenarioAudio(action, generation);
          break;

        case 'VOICE_TEST':
          await _executeVoiceTest(generation);
          break;
      }
    }
  }

  Future<void> _runAllItems(int generation) async {
    try {
      while (!_isPlaybackCancelled(generation)) {
        final item = _currentItem;

        if (item == null) {
          break;
        }

        // Если repeatCount отсутствует или равен 0,
        // используем одно базовое повторение.
        final baseRepeatCount = item.repeatCount > 0 ? item.repeatCount : 1;

        // Множитель применяется к индивидуальному количеству повторов.
        final effectiveRepeatCount = baseRepeatCount * _repeatMultiplier;

        var repeat = 0;

        while (repeat < effectiveRepeatCount) {
          if (_isPlaybackCancelled(generation)) return;

          await _runCurrentScenario(generation);

          if (_isPlaybackCancelled(generation)) return;

          repeat++;
        }

        // Обычный последовательный режим.
        if (!_randomizerEnabled) {
          if (_currentItemIndex >= _items.length - 1) {
            break;
          }
        }

        // Randomizer выбирает любой элемент из всего набора.
        // Повторное выпадение текущего элемента разрешено.
        final int nextIndex;

        if (_randomizerEnabled) {
          nextIndex = Random().nextInt(_items.length);
        } else {
          nextIndex = _currentItemIndex + 1;
        }

        setState(() {
          _currentItemIndex = nextIndex;
          _updateCurrentTexts();
          _showTop = false;
          _showBottom = false;
        });

        unawaited(_saveCurrentIndex(nextIndex));
      }
    } catch (error) {
      if (mounted && generation == _playbackGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка воспроизведения: $error')),
        );
      }
    } finally {
      if (mounted && generation == _playbackGeneration) {
        setState(() {
          _isPlaying = false;
          _isPaused = false;
        });

        _pauseController.reset();

        BluetoothAudioService.handler.updatePlayingState(false);
      }
    }
  }

  Widget _buildLoadingSetScreen() {
    final hasProgress = _downloadTotal > 0;
    final percent = (_downloadProgress * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Sound Language Studio')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cloud_download_outlined, size: 56),
                const SizedBox(height: 20),
                Text(
                  'Загрузка учебного набора',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _downloadSetName.isEmpty
                      ? 'Набор ${widget.setId}'
                      : _downloadSetName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: hasProgress ? _downloadProgress : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                if (hasProgress)
                  Text(
                    '$_downloadCompleted из $_downloadTotal аудиофайлов '
                    '($percent%)',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  )
                else
                  const Text(
                    'Подключение к серверу…',
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 12),
                Text(
                  _downloadCurrentFile,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Не закрывайте приложение до завершения загрузки.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(shape: const CircleBorder()),
        icon: Icon(icon, size: 20),
      ),
    );
  }

  @override
  void dispose() {
    _cancelVoiceTest();
    unawaited(_bluetoothCommandSubscription?.cancel() ?? Future<void>.value());

    unawaited(_audioPlayerService.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sound Language Studio')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sound Language Studio')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить конфигурацию:\n$_errorMessage'),
          ),
        ),
      );
    }

    if (_isLoadingSet) {
      return _buildLoadingSetScreen();
    }

    if (_setError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sound Language Studio')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Не удалось загрузить учебный набор:\n$_setError',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loadLearningSet,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить загрузку'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Уже сохранённые аудиофайлы останутся на устройстве.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final config = _config!;
    final scenario = _selectedScenario!;

    return Scaffold(
      appBar: AppBar(title: const Text('Sound Language Studio')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: scenario.key,
                decoration: const InputDecoration(
                  labelText: 'Сценарий',
                  border: OutlineInputBorder(),
                ),
                items: config.scenarios.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value.caption),
                  );
                }).toList(),
                onChanged: _selectScenario,
              ),
              PauseSettings(
                pauseBeforeTranslationFactor: _pauseBeforeTranslationFactor,
                pauseBeforeTranslationMs:
                    _currentItem?.pauseBeforeTranslation ?? 0,
                effectivePauseBeforeTranslationMs:
                    _effectivePauseBeforeTranslationMs,
                pauseBetweenSentencesMs: _pauseBetweenSentencesMs,
                onPauseBeforeTranslationChanged: (value) {
                  setState(() {
                    _pauseBeforeTranslationFactor = value;
                  });
                },
                onPauseBetweenSentencesChanged: (value) {
                  setState(() {
                    _pauseBetweenSentencesMs = value;
                  });
                },
                repeatMultiplier: _repeatMultiplier,
                onRepeatMultiplierChanged: (value) {
                  setState(() {
                    _repeatMultiplier = value;
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Элемент ${_currentItemIndex + 1} / ${_items.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              AdaptiveTextWindow(
                title: 'Оригинал',
                text: _phraseText,
                visible: _showTop,
                baseFontSize: 26,
              ),
              AdaptiveTextWindow(
                title: 'Перевод',
                text: _translateText,
                visible: _showBottom,
                baseFontSize: 20,
              ),
              const SizedBox(height: 12),
              PlayerControls(
                onSettings: () {
                  final previousPlayerRoute = ModalRoute.of(context);

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(
                        setName: _currentSetName,
                        setDescription: _currentSetDescription,
                        setId: _activeSetId,
                        previousPlayerRoute: previousPlayerRoute,
                        stopPreviousPlayer: _stopForSessionReplacement,
                      ),
                    ),
                  );
                },
                randomizerEnabled: _randomizerEnabled,
                onRandomizer: () {
                  setState(() {
                    _randomizerEnabled = !_randomizerEnabled;
                  });
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNavigationButton(
                      icon: Icons.first_page,
                      tooltip: 'В начало',
                      onPressed: _currentItemIndex > 0
                          ? () => _navigateToItem(0)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    _buildNavigationButton(
                      icon: Icons.chevron_left,
                      tooltip: 'Назад',
                      onPressed: _currentItemIndex > 0
                          ? () => _navigateToItem(_currentItemIndex - 1)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: IconButton.filled(
                        onPressed: _togglePlayback,
                        tooltip: _isPlaying ? 'Stop' : 'Play',
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          shape: const CircleBorder(),
                        ),
                        icon: Icon(
                          _isPlaying ? Icons.stop : Icons.play_arrow,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildNavigationButton(
                      icon: Icons.chevron_right,
                      tooltip: 'Вперёд',
                      onPressed: _currentItemIndex < _items.length - 1
                          ? () => _navigateToItem(_currentItemIndex + 1)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    _buildNavigationButton(
                      icon: Icons.last_page,
                      tooltip: 'В конец',
                      onPressed: _currentItemIndex < _items.length - 1
                          ? () => _navigateToItem(_items.length - 1)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
