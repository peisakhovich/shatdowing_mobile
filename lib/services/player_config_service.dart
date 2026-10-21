import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/player_scenario.dart';

class PlayerConfigService {
  static const String _configPath = 'assets/config/player_config.json';

  Future<PlayerConfig> load() async {
    final jsonString = await rootBundle.loadString(_configPath);

    final decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Корневой элемент конфигурации должен быть объектом.',
      );
    }

    final version = decoded['version'];

    if (version != 1) {
      throw FormatException('Неподдерживаемая версия конфигурации: $version');
    }

    final defaultScenario = decoded['default_scenario'];
    final rawScenarios = decoded['scenarios'];

    if (defaultScenario is! String || rawScenarios is! Map<String, dynamic>) {
      throw const FormatException(
        'В конфигурации отсутствуют default_scenario или scenarios.',
      );
    }

    final scenarios = <String, PlayerScenario>{};

    for (final entry in rawScenarios.entries) {
      final value = entry.value;

      if (value is! Map<String, dynamic>) {
        throw FormatException('Некорректное описание сценария "${entry.key}".');
      }

      scenarios[entry.key] = PlayerScenario.fromJson(entry.key, value);
    }

    if (!scenarios.containsKey(defaultScenario)) {
      throw FormatException(
        'Сценарий по умолчанию "$defaultScenario" не найден.',
      );
    }

    return PlayerConfig(
      defaultScenario: defaultScenario,
      scenarios: Map.unmodifiable(scenarios),
    );
  }
}

class PlayerConfig {
  final String defaultScenario;
  final Map<String, PlayerScenario> scenarios;

  const PlayerConfig({required this.defaultScenario, required this.scenarios});

  PlayerScenario get defaultScenarioConfig => scenarios[defaultScenario]!;
}
