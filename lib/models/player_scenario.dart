class PlayerScenario {
  final String key;
  final String caption;
  final List<ScenarioAction> actions;

  const PlayerScenario({
    required this.key,
    required this.caption,
    required this.actions,
  });

  factory PlayerScenario.fromJson(String key, Map<String, dynamic> json) {
    final rawActions = json['actions'];

    if (rawActions is! List) {
      throw FormatException('У сценария "$key" отсутствует список actions.');
    }

    return PlayerScenario(
      key: key,
      caption: json['caption'] as String,
      actions: rawActions.map((item) {
        if (item is! Map<String, dynamic>) {
          throw FormatException('Некорректное действие в сценарии "$key".');
        }

        return ScenarioAction.fromJson(item);
      }).toList(),
    );
  }
}

class ScenarioAction {
  final String action;
  final String? target;
  final String? content;
  final String? source;

  const ScenarioAction({
    required this.action,
    this.target,
    this.content,
    this.source,
  });

  factory ScenarioAction.fromJson(Map<String, dynamic> json) {
    final action = json['action'];

    if (action is! String ||
        !{'SHOW', 'HIDE', 'PLAY', 'WAIT'}.contains(action)) {
      throw FormatException('Неизвестная команда сценария: $action');
    }

    return ScenarioAction(
      action: action,
      target: json['target'] as String?,
      content: json['content'] as String?,
      source: json['source'] as String?,
    );
  }
}
