import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings_en.dart';
import 'strings_ru.dart';
import 'strings_pl.dart';
import 'strings_de.dart';
import 'strings_fr.dart';

class Localization extends ChangeNotifier {
  static const _preferenceKey = 'app_language';
  static const Map<String, Map<String, String>> _dictionaries = {
    'en': stringsEN, 'ru': stringsRU, 'pl': stringsPL, 'de': stringsDE, 'fr': stringsFR,
  };
  static const Map<String, String> languageNames = {
    'ru': 'Русский',
    'pl': 'Polski',
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Français',
  };

  String _languageCode = 'en';
  String get languageCode => _languageCode;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_preferenceKey);
    _languageCode = _dictionaries.containsKey(saved) ? saved! : 'en';
  }

  Future<void> setLanguage(String code) async {
    if (!_dictionaries.containsKey(code) || code == _languageCode) return;
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, code);
  }

  String t(String key, {Map<String, Object?> params = const {}}) {
    var value = _dictionaries[_languageCode]?[key] ?? stringsEN[key] ?? '[$key]';
    for (final entry in params.entries) {
      value = value = value.replaceAll('{${entry.key}}', entry.value?.toString() ?? '');
    }
    return value;
  }
}

final Localization lng = Localization();
