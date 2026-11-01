import 'package:flutter/material.dart';

import '../models/user_account.dart';
import '../models/user_set.dart';
import '../services/user_session.dart';
import '../services/local_session_storage.dart';

import 'login_screen.dart';
import 'set_selection_screen.dart';
import 'player_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Открывает экран входа.
  Future<void> _openLogin(BuildContext context) async {
    final account = await Navigator.of(context).push<UserAccount>(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );

    if (account != null) {
      await UserSession.instance.login(account);
    }
  }

  /// Открывает выбор учебного набора.
  Future<void> _openSetSelection(BuildContext context) async {
    debugPrint('[SETTINGS] Opening set selection');

    final selectedSet = await Navigator.of(context).push<UserSet>(
      MaterialPageRoute(builder: (context) => const SetSelectionScreen()),
    );

    debugPrint(
      '[SETTINGS] Selection returned: '
      '${selectedSet?.setId} - ${selectedSet?.setName}',
    );

    if (selectedSet == null || !context.mounted) {
      debugPrint('[SETTINGS] Selection cancelled');
      return;
    }

    // Сохраняем выбранный набор для текущего пользователя.
    await UserSession.instance.selectSet(selectedSet.setId);

    if (!context.mounted) return;

    debugPrint(
      '[SETTINGS] Opening PlayerScreen with setId=${selectedSet.setId}',
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) =>
            PlayerScreen(setId: selectedSet.setId, useDefaultSession: false),
      ),
    );
  }

  /// Выполняет выход и возвращает приложение к гостевой сессии.
  Future<void> _logout(BuildContext context) async {
    debugPrint('[SETTINGS] Logout started');

    final localSessionStorage = LocalSessionStorage();
    // Удаляем учётную запись и выбранный набор пользователя.
    await UserSession.instance.logout();

    // Удаляем пользовательский набор и скачанные MP3.
    await localSessionStorage.clearLearningSession();

    if (!context.mounted) return;

    debugPrint('[SETTINGS] Opening guest session');

    // Удаляем предыдущие экраны из стека навигации.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(setId: 69, useDefaultSession: true),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: AnimatedBuilder(
        animation: UserSession.instance,
        builder: (context, child) {
          final account = UserSession.instance.account;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: const Text('Учётная запись'),
                      subtitle: Text(
                        account == null
                            ? 'Вход не выполнен. Активна гостевая сессия. '
                                  'Пользователь не определён.'
                            : 'Вход выполнен: ${account.nickname}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: account == null
                          ? () => _openLogin(context)
                          : () => _logout(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.library_music_outlined),
                      title: const Text('Учебный набор'),
                      subtitle: const Text('Просмотр и выбор набора'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (account == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Сначала необходимо войти в систему.',
                              ),
                            ),
                          );
                          return;
                        }

                        _openSetSelection(context);
                      },
                    ),
                  ],
                ),
              ),
              if (account != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Данные пользователя',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text('Nickname: ${account.nickname}'),
                        Text('User ID: ${account.userId}'),
                        if (account.firstName != null)
                          Text('Имя: ${account.firstName}'),
                        if (account.lastName != null)
                          Text('Фамилия: ${account.lastName}'),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => _logout(context),
                          icon: const Icon(Icons.logout),
                          label: const Text('Выйти'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
