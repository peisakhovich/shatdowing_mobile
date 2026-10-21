import 'package:flutter_test/flutter_test.dart';
import 'package:shadowing_mobile/services/player_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Загружает все шесть сценариев', () async {
    final config = await PlayerConfigService().load();

    expect(config.scenarios.length, 6);
    expect(config.defaultScenario, 'shadowing');

    expect(
      config.scenarios.keys,
      containsAll([
        'shadowing',
        'shadowing_no_translation',
        'shadowing_hidden',
        'revers_shatdowing',
        'reading',
        'dictation',
      ]),
    );
  });

  test('Сценарий Shadowing содержит восемь действий', () async {
    final config = await PlayerConfigService().load();

    final scenario = config.scenarios['shadowing']!;

    expect(scenario.caption, 'Shadowing');
    expect(scenario.actions.length, 8);
  });
}
