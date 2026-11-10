class LearningItem {
  final int id;
  final String phrase;
  final String? translation;

  // Языковые коды и локали текущей учебной фразы и её перевода.
  final String? phraseCode;
  final String? phraseLocale;
  final String? translateCode;
  final String? translateLocale;

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
    this.phraseCode,
    this.phraseLocale,
    this.translateCode,
    this.translateLocale,
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
      phraseCode: json['phrase_code'] as String?,
      phraseLocale: json['phrase_locale'] as String?,
      translateCode: json['translate_code'] as String?,
      translateLocale: json['translate_locale'] as String?,
      pauseBeforeTranslation: json['pause_ms'] as int,
      speed: (json['speed'] as num).toDouble(),
      repeatCount: (json['repeat_count'] as int?) ?? 0,
      phraseAudioPath: '',
      translationAudioPath: null,
    );
  }
}
