import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';

class UserStorage {
  static const String _userKey = 'saved_user_account';

  String _selectedSetKey(int userId) => 'selected_set_id_$userId';

  /// Сохраняет данные пользователя без пароля.
  Future<void> saveUser(UserAccount account) async {
    final prefs = await SharedPreferences.getInstance();

    final userData = {
      'user_id': account.userId,
      'nickname': account.nickname,
      'first_name': account.firstName,
      'last_name': account.lastName,
      'active': account.active,
    };

    await prefs.setString(_userKey, jsonEncode(userData));
  }

  /// Восстанавливает пользователя после перезапуска приложения.
  Future<UserAccount?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();

    final savedData = prefs.getString(_userKey);

    if (savedData == null) {
      return null;
    }

    try {
      final userData = jsonDecode(savedData) as Map<String, dynamic>;
      return UserAccount.fromJson(userData);
    } catch (_) {
      await prefs.remove(_userKey);
      return null;
    }
  }

  /// Сохраняет выбранный набор конкретного пользователя.
  Future<void> saveSelectedSetId({
    required int userId,
    required int setId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_selectedSetKey(userId), setId);
  }

  /// Восстанавливает выбранный набор пользователя.
  Future<int?> loadSelectedSetId(int userId) async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getInt(_selectedSetKey(userId));
  }

  /// Удаляет сохранённый выбор набора пользователя.
  Future<void> clearSelectedSetId(int userId) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_selectedSetKey(userId));
  }

  /// Удаляет сохранённую учётную запись.
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_userKey);
  }
}
