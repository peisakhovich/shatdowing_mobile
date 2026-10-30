class LearningItem {
  final int id;
  final String phrase;
  final String? translation;

  // Индивидуальная пауза перед переводом, полученная из API.
  final int pauseBeforeTranslation;

  // Скорость воспроизведения и число повторений.
  final double speed;
  final int repeatCount;

  // Локальные пути к аудиофайлам.
  final String phraseAudioPath;
  final String? translationAudioPath;

  const LearningItem({
    required this.id,
    required this.phrase,
    required this.translation,
    required this.pauseBeforeTranslation,
    required this.speed,
    required this.repeatCount,
    required this.phraseAudioPath,
    required this.translationAudioPath,
  });

  factory LearningItem.fromJson(Map<String, dynamic> json) {
    return LearningItem(
      id: json['item_id'] as int,
      phrase: json['phrase_text'] as String,
      translation: json['translate_text'] as String?,
      pauseBeforeTranslation: json['pause_ms'] as int,
      speed: (json['speed'] as num).toDouble(),
      repeatCount: (json['repeat_count'] as int?) ?? 0,
      phraseAudioPath: '',
      translationAudioPath: null,
    );
  }
}
