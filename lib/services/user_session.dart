import 'package:flutter/foundation.dart';

import '../models/user_account.dart';

class UserSession extends ChangeNotifier {
  UserSession._();

  static final UserSession instance = UserSession._();

  UserAccount? _account;

  UserAccount? get account => _account;

  bool get isLoggedIn => _account != null;

  void login(UserAccount account) {
    _account = account;
    notifyListeners();
  }

  void logout() {
    _account = null;
    notifyListeners();
  }
}
