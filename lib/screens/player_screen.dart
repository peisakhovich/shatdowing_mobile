import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/learning_item.dart';
import '../models/learning_set.dart';
import '../models/player_scenario.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/local_session_storage.dart';
import '../services/player_config_service.dart';
import '../widgets/player/adaptive_text_window.dart';
import '../widgets/player/pause_settings.dart';

class PlayerScreen extends StatefulWidget {
  final int setId;

  const PlayerScreen({super.key, this.setId = 69});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlayerConfigService _configService = PlayerConfigService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  final ApiClient _apiClient = ApiClient();
  final LocalSessionStorage _localSessionStorage = LocalSessionStorage();

  PlayerConfig? _config;
  PlayerScenario? _selectedScenario;

  List<LearningItem> _items = [];
  int _currentItemIndex = 0;

  String _phraseText = '';
  String _translateText = '';

  bool _isPlaying = false;
  bool _showTop = false;
  bool _showBottom = false;

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

  @override
  void initState() {
    super.initState();
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
        _downloadSetName = 'Набор ${widget.setId}';
        _downloadCurrentFile = 'Проверка локальных файлов…';
        _downloadCompleted = 0;
        _downloadTotal = 0;
      });
    }

    try {
      LearningSet? learningSet;

      final cachedSet = await _localSessionStorage.loadLearningSet();

      if (cachedSet != null && cachedSet.setId == widget.setId) {
        _updateDownloadProgress(
          setName: cachedSet.setName,
          currentFile: 'Проверка сохранённых аудиофайлов…',
        );
        learningSet = await _restoreCachedSetWithAudio(cachedSet);
      }

      learningSet ??= await _downloadAndCacheLearningSet();

      if (learningSet.items.isEmpty) {
        throw const FormatException('Учебный набор не содержит элементов.');
      }

      if (!mounted) return;

      setState(() {
        _items = learningSet!.items;
        _currentItemIndex = learningSet.currentIndex;
        _updateCurrentTexts();
        _isLoadingSet = false;
      });
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
    _updateDownloadProgress(
      currentFile: 'Получение списка элементов с сервера…',
    );

    final apiSet = await _apiClient.getLearningSet(widget.setId);

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
          setId: widget.setId,
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
            setId: widget.setId,
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

    await _localSessionStorage.saveLearningSet(cachedSet);

    _updateDownloadProgress(
      currentFile: 'Загрузка завершена',
      completed: totalAudioFiles,
    );

    return cachedSet;
  }

  /// Сохраняет позицию элемента без прерывания воспроизведения.
  Future<void> _saveCurrentIndex(int index) async {
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
  }

  void _selectScenario(String? key) {
    if (key == null || _config == null) return;

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

  void _togglePlayback() {
    if (_isPlaying) {
      setState(() {
        _playbackGeneration++;
        _isPlaying = false;
      });

      unawaited(_audioPlayerService.stop());
      return;
    }

    if (_items.isEmpty) return;

    final generation = ++_playbackGeneration;

    setState(() {
      _isPlaying = true;
    });

    unawaited(_runAllItems(generation));
  }

  /// Останавливает текущий сценарий и выбирает другой элемент.
  /// Автоматически продолжает воспроизведение, если оно было активно.
  void _navigateToItem(int index) {
    if (_items.isEmpty) return;

    final targetIndex = index.clamp(0, _items.length - 1).toInt();
    final wasPlaying = _isPlaying;

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

  /// Ожидание небольшими отрезками позволяет быстро реагировать на Stop.
  Future<void> _executeWait(Duration duration, int generation) async {
    var remaining = duration;
    const interval = Duration(milliseconds: 50);

    while (remaining > Duration.zero) {
      if (_isPlaybackCancelled(generation)) return;

      final chunk = remaining > interval ? interval : remaining;

      await Future.delayed(chunk);
      remaining -= chunk;
    }
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
      setId: widget.setId,
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

    // Проигрываем именно сохранённый MP3. Не создаём и не перезаписываем
    // общий временный файл для каждой фразы и каждого перевода.
    await _audioPlayerService.playFile(audioPath);
  }

  Future<void> _runCurrentScenario(int generation) async {
    final scenario = _selectedScenario;
    if (scenario == null) return;

    for (final action in scenario.actions) {
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
      }
    }
  }

  Future<void> _runAllItems(int generation) async {
    try {
      while (!_isPlaybackCancelled(generation)) {
        await _runCurrentScenario(generation);

        if (_isPlaybackCancelled(generation)) return;

        if (_currentItemIndex >= _items.length - 1) {
          break;
        }

        final nextIndex = _currentItemIndex + 1;

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
        });
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
              Row(
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
                      style: IconButton.styleFrom(shape: const CircleBorder()),
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
            ],
          ),
        ),
      ),
    );
  }
}
