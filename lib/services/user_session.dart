import 'package:flutter/foundation.dart';

import '../models/user_account.dart';
import 'user_storage.dart';

class UserSession extends ChangeNotifier {
  UserSession._();

  static final UserSession instance = UserSession._();

  final UserStorage _userStorage = UserStorage();

  UserAccount? _account;

  UserAccount? get account => _account;

  bool get isLoggedIn => _account != null;

  /// Восстанавливает пользователя при запуске приложения.
  Future<void> restoreSession() async {
    _account = await _userStorage.loadUser();
    notifyListeners();
  }

  /// Выполняет вход и сохраняет пользователя.
  Future<void> login(UserAccount account) async {
    _account = account;

    await _userStorage.saveUser(account);

    notifyListeners();
  }

  /// Выполняет выход и удаляет сохранённую учётную запись.
  Future<void> logout() async {
    _account = null;

    await _userStorage.clearUser();

    notifyListeners();
  }
}
