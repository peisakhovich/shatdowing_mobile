import 'dart:async';

import 'package:flutter/material.dart';

import '../models/learning_item.dart';
import '../models/player_scenario.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/player_config_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlayerConfigService _configService = PlayerConfigService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  final ApiClient _apiClient = ApiClient();

  static const int _setId = 69;

  static const double _minPauseFactor = 0.0;
  static const double _maxPauseFactor = 6.0;

  static const int _minBetweenSentencesMs = 0;
  static const int _maxBetweenSentencesMs = 16000;
  static const int _betweenSentencesStepMs = 250;

  PlayerConfig? _config;
  PlayerScenario? _selectedScenario;

  List<LearningItem> _items = [];
  int _currentItemIndex = 0;

  String _phraseText = '';
  String _translateText = '';

  bool _isPlaying = false;

  bool _showTop = false;
  bool _showBottom = false;

  // Пользовательские настройки пауз.
  // Они не изменяют исходные данные LearningItem.
  double _pauseBeforeTranslationFactor = 1.0;
  int _pauseBetweenSentencesMs = 2000;

  int _playbackGeneration = 0;

  bool _isLoading = true;
  bool _isLoadingSet = true;

  String? _errorMessage;
  String? _setError;

  LearningItem? get _currentItem {
    if (_items.isEmpty ||
        _currentItemIndex < 0 ||
        _currentItemIndex >= _items.length) {
      return null;
    }

    return _items[_currentItemIndex];
  }

  bool get _hasTranslation {
    final translation = _currentItem?.translation;
    return translation != null && translation.trim().isNotEmpty;
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

  Future<void> _loadLearningSet() async {
    try {
      final learningSet = await _apiClient.getLearningSet(_setId);

      if (!mounted) return;

      if (learningSet.items.isEmpty) {
        throw const FormatException('API вернул набор без учебных элементов.');
      }

      setState(() {
        _items = learningSet.items;
        _currentItemIndex = 0;
        _updateCurrentTexts();
        _isLoadingSet = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _setError = error.toString();
        _isLoadingSet = false;
      });
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

  /// Останавливает воспроизведение и выбирает другой элемент.
  /// Новый элемент не запускается автоматически, если проигрыватель
  /// до перехода находился в состоянии остановки.
  void _navigateToItem(int index) {
    if (_items.isEmpty) return;

    final targetIndex = index.clamp(0, _items.length - 1).toInt();
    final wasPlaying = _isPlaying;

    // Отменяем предыдущий сценарий и его ожидания.
    _playbackGeneration++;

    unawaited(_audioPlayerService.stop());

    setState(() {
      _currentItemIndex = targetIndex;
      _updateCurrentTexts();

      _showTop = false;
      _showBottom = false;
      _isPlaying = wasPlaying;
    });

    _applyScenarioVisibility();

    if (wasPlaying) {
      final generation = ++_playbackGeneration;
      unawaited(_runAllItems(generation));
    }
  }

  bool _isPlaybackCancelled(int generation) {
    return !mounted || !_isPlaying || generation != _playbackGeneration;
  }

  /// Ожидание небольшими отрезками позволяет быстро реагировать на Stop
  /// и переход к другому элементу.
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

        // Если перевода нет, пауза перед переводом не нужна.
        if (!_hasTranslation) {
          return Duration.zero;
        }

        // Исходная пауза элемента не изменяется.
        final milliseconds =
            (item.pauseBeforeTranslation * _pauseBeforeTranslationFactor)
                .round();

        return Duration(milliseconds: milliseconds);

      case 'pause_between_sentences':
        return Duration(milliseconds: _pauseBetweenSentencesMs);

      default:
        throw FormatException('Неизвестный источник паузы: ${action.source}');
    }
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

    final audioBytes = await _apiClient.getItemAudio(
      setId: _setId,
      itemId: item.id,
      audioType: audioType,
    );

    if (_isPlaybackCancelled(generation)) return;

    await _audioPlayerService.playBytes(audioBytes);
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
            'source=${action.source}, duration=${duration.inMilliseconds} ms',
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

        setState(() {
          _currentItemIndex++;
          _updateCurrentTexts();
          _showTop = false;
          _showBottom = false;
        });
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

  Widget _buildPauseSettings() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Настройки пауз'),
      subtitle: const Text('Влияют на последующие паузы'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Перед переводом')),
                  Text(
                    '${_pauseBeforeTranslationFactor.toStringAsFixed(2)}×',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              Slider(
                min: _minPauseFactor,
                max: _maxPauseFactor,
                divisions: 24,
                value: _pauseBeforeTranslationFactor,
                label: '${_pauseBeforeTranslationFactor.toStringAsFixed(2)}×',
                onChanged: (value) {
                  setState(() {
                    _pauseBeforeTranslationFactor = value;
                  });
                },
              ),
              Row(
                children: [
                  const Expanded(child: Text('Между предложениями')),
                  Text(
                    '$_pauseBetweenSentencesMs мс',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              Slider(
                min: _minBetweenSentencesMs.toDouble(),
                max: _maxBetweenSentencesMs.toDouble(),
                divisions: _maxBetweenSentencesMs ~/ _betweenSentencesStepMs,
                value: _pauseBetweenSentencesMs.toDouble(),
                label: '$_pauseBetweenSentencesMs мс',
                onChanged: (value) {
                  setState(() {
                    _pauseBetweenSentencesMs =
                        (value / _betweenSentencesStepMs).round() *
                        _betweenSentencesStepMs;
                  });
                },
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildTextWindow({
    required String title,
    required String text,
    required bool visible,
    required double fontSize,
  }) {
    return Expanded(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: visible
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: visible
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: fontSize),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(),
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
    if (_isLoading || _isLoadingSet) {
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

    if (_setError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sound Language Studio')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить учебный набор:\n$_setError'),
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
              _buildPauseSettings(),
              const SizedBox(height: 4),
              Text(
                'Элемент ${_currentItemIndex + 1} / ${_items.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _buildTextWindow(
                title: 'Оригинал',
                text: _phraseText,
                visible: _showTop,
                fontSize: 26,
              ),
              _buildTextWindow(
                title: 'Перевод',
                text: _translateText,
                visible: _showBottom,
                fontSize: 20,
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
