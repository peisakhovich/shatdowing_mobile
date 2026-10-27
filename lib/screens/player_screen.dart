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

  PlayerConfig? _config;
  PlayerScenario? _selectedScenario;

  List<LearningItem> _items = [];
  int _currentItemIndex = 0;

  String _phraseText = '';
  String _translateText = '';

  bool _isPlaying = false;
  bool _isTestingAudio = false;
  bool _showTop = false;
  bool _showBottom = false;

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
      final learningSet = await _apiClient.getLearningSet(69);

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
    if (scenario == null) return;

    final firstAction = scenario.actions.firstOrNull;
    if (firstAction == null) return;

    setState(() {
      if (firstAction.action == 'SHOW') {
        if (firstAction.target == 'top') _showTop = true;
        if (firstAction.target == 'bottom') _showBottom = true;
      } else if (firstAction.action == 'HIDE') {
        if (firstAction.target == 'top') _showTop = false;
        if (firstAction.target == 'bottom') _showBottom = false;
      }
    });
  }

  Future<void> _testAudio() async {
    if (_isTestingAudio) return;

    setState(() {
      _isTestingAudio = true;
    });

    try {
      await _audioPlayerService.playAsset('assets/audio_test/test.mp3');
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка воспроизведения: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isTestingAudio = false;
        });
      }
    }
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

  bool _isPlaybackCancelled(int generation) {
    return !mounted || !_isPlaying || generation != _playbackGeneration;
  }

  Future<void> _executeWait(Duration duration, int generation) async {
    await Future.delayed(duration);
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
        audioType = 'translate';
        break;

      default:
        throw FormatException('Неизвестный источник аудио: ${action.source}');
    }

    if (audioType == 'translate' &&
        (item.translation == null || item.translation!.isEmpty)) {
      return;
    }

    final audioBytes = await _apiClient.getItemAudio(
      setId: 69,
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
          setState(() {
            if (action.target == 'top') _showTop = true;
            if (action.target == 'bottom') _showBottom = true;
          });
          break;

        case 'HIDE':
          setState(() {
            if (action.target == 'top') _showTop = false;
            if (action.target == 'bottom') _showBottom = false;
          });
          break;

        case 'WAIT':
          await _executeWait(const Duration(seconds: 2), generation);
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
              const SizedBox(height: 8),
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
              SizedBox(
                width: double.infinity,
                height: 72,
                child: FilledButton.icon(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 36,
                  ),
                  label: Text(
                    _isPlaying ? 'Stop' : 'Play',
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isTestingAudio ? null : _testAudio,
                icon: const Icon(Icons.volume_up),
                label: Text(
                  _isTestingAudio ? 'Воспроизводится...' : 'Проверить звук',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
