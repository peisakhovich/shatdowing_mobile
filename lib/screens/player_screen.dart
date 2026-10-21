import 'dart:async';

import 'package:flutter/material.dart';

import '../models/player_scenario.dart';
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

  PlayerConfig? _config;
  PlayerScenario? _selectedScenario;

  final String _phraseText = 'This is a sample sentence.';
  final String _translateText = 'Это пример предложения.';

  bool _isPlaying = false;
  bool _isTestingAudio = false;
  bool _showTop = false;
  bool _showBottom = false;
  int _playbackGeneration = 0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadConfig();
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

  void _selectScenario(String? key) {
    if (key == null || _config == null) return;

    setState(() {
      _selectedScenario = _config!.scenarios[key];
      _playbackGeneration++;
      _isPlaying = false;
      _showTop = false;
      _showBottom = false;
    });

    _applyScenarioVisibility();
  }

  void _applyScenarioVisibility() {
    final scenario = _selectedScenario;
    if (scenario == null) return;

    final firstAction = scenario.actions.firstOrNull;
    if (firstAction == null) return;

    setState(() {
      if (firstAction.action == 'SHOW') {
        if (firstAction.target == 'top') {
          _showTop = true;
        }
        if (firstAction.target == 'bottom') {
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
      return;
    }

    setState(() {
      _playbackGeneration++;
      _isPlaying = true;
    });

    _runScenario(_playbackGeneration);
  }

  bool _isPlaybackCancelled(int generation) {
    return !mounted || !_isPlaying || generation != _playbackGeneration;
  }

  Future<void> _executeWait(Duration duration, int generation) async {
    await Future.delayed(duration);

    if (_isPlaybackCancelled(generation)) {
      return;
    }
  }

  Future<void> _runScenario(int generation) async {
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
          final duration = action.source == 'pause_before_translation'
              ? const Duration(seconds: 2)
              : const Duration(seconds: 2);

          await _executeWait(duration, generation);
          break;

        case 'PLAY':
          // Пока имитируем воспроизведение в сценарии.
          // Настоящий MP3 проверяется отдельной кнопкой.
          await _executeWait(const Duration(seconds: 1), generation);
          break;
      }
    }

    if (!_isPlaybackCancelled(generation)) {
      setState(() {
        _isPlaying = false;
      });
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
              const SizedBox(height: 12),
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
