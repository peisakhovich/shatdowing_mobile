import 'package:flutter/foundation.dart';

import '../models/user_account.dart';
import 'user_storage.dart';

class UserSession extends ChangeNotifier {
  UserSession._();

  static final UserSession instance = UserSession._();

  final UserStorage _userStorage = UserStorage();

  UserAccount? _account;
  int? _selectedSetId;

  UserAccount? get account => _account;

  int? get selectedSetId => _selectedSetId;

  bool get isLoggedIn => _account != null;

  /// Восстанавливает пользователя и выбранный им набор.
  Future<void> restoreSession() async {
    _account = await _userStorage.loadUser();

    if (_account != null) {
      _selectedSetId = await _userStorage.loadSelectedSetId(_account!.userId);
    } else {
      _selectedSetId = null;
    }

    notifyListeners();
  }

  /// Выполняет вход и сохраняет пользователя.
  Future<void> login(UserAccount account) async {
    _account = account;

    _selectedSetId = await _userStorage.loadSelectedSetId(account.userId);

    await _userStorage.saveUser(account);

    notifyListeners();
  }

  /// Сохраняет выбранный учебный набор.
  Future<void> selectSet(int setId) async {
    final currentAccount = _account;

    if (currentAccount == null) {
      throw StateError('Нельзя выбрать набор без авторизации.');
    }

    await _userStorage.saveSelectedSetId(
      userId: currentAccount.userId,
      setId: setId,
    );

    _selectedSetId = setId;

    notifyListeners();
  }

  /// Выполняет выход и удаляет сохранённые данные пользователя.
  Future<void> logout() async {
    final currentAccount = _account;

    if (currentAccount != null) {
      await _userStorage.clearSelectedSetId(currentAccount.userId);
    }

    await _userStorage.clearUser();

    _account = null;
    _selectedSetId = null;

    notifyListeners();
  }
}
