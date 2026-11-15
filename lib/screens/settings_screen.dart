import 'package:flutter/material.dart';

import '../localization/localization.dart';
import '../models/user_account.dart';
import '../models/user_set.dart';
import '../services/user_session.dart';
import '../services/local_session_storage.dart';

import 'login_screen.dart';
import 'set_selection_screen.dart';
import 'player_screen.dart';

class SettingsScreen extends StatelessWidget {
  final int setId;
  final String setName;
  final String setDescription;

  final Route<dynamic>? previousPlayerRoute;
  final Future<void> Function()? stopPreviousPlayer;

  const SettingsScreen({
    super.key,
    required this.setId,
    required this.setName,
    required this.setDescription,
    this.previousPlayerRoute,
    this.stopPreviousPlayer,
  });

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

    final navigator = Navigator.of(context);
    final oldPlayerRoute = previousPlayerRoute;
    final stopOldPlayer = stopPreviousPlayer;

    debugPrint(
      '[SETTINGS] Opening PlayerScreen with setId=${selectedSet.setId}',
    );

    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          setId: selectedSet.setId,
          useDefaultSession: false,
          onSessionReady: () async {
            debugPrint('[SETTINGS] New session loaded successfully');

            // Обновляем выбранный набор только после успешной загрузки.
            await UserSession.instance.selectSet(selectedSet.setId);

            // Останавливаем прежний плеер.
            if (stopOldPlayer != null) {
              await stopOldPlayer();
            }

            // Удаляем прежний PlayerScreen из стека навигации.
            if (navigator.mounted &&
                oldPlayerRoute != null &&
                oldPlayerRoute.isActive) {
              navigator.removeRoute(oldPlayerRoute);
            }

            debugPrint('[SETTINGS] Previous player route removed');
          },
        ),
      ),
    );
  }

  /// Выполняет выход и возвращает приложение к гостевой сессии.
  Future<void> _logout(BuildContext context) async {
    debugPrint('[SETTINGS] Logout started');

    // Сначала останавливаем прежнее воспроизведение.
    if (stopPreviousPlayer != null) {
      await stopPreviousPlayer!();
    }

    final localSessionStorage = LocalSessionStorage();

    await UserSession.instance.logout();
    await localSessionStorage.clearAllLearningSessions();

    if (!context.mounted) return;

    debugPrint('[SETTINGS] Opening guest session');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(setId: 69, useDefaultSession: true),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: lng,
      builder: (context, child) => _buildLocalizedContent(context),
    );
  }

  Widget _buildLocalizedContent(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(lng.t('settingsTitle'))),
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
                      title: Text(lng.t('settingsAccount')),
                      subtitle: Text(
                        account == null
                            ? lng.t('settingsGuest')
                            : lng.t('settingsSignedIn', params: {'nickname': account.nickname}),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: account == null
                          ? () => _openLogin(context)
                          : () => _logout(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.library_music_outlined),
                      title: Text(lng.t('settingsLearningSet')),
                      subtitle: Text(lng.t('settingsViewSets')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (account == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                lng.t('settingsLoginRequired'),
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
                          lng.t('settingsUserData'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text('${lng.t('settingsNickname')}: ${account.nickname}'),
                        Text('${lng.t('settingsUserId')}: ${account.userId}'),
                        if (account.firstName != null)
                          Text('${lng.t('settingsFirstName')}: ${account.firstName}'),
                        if (account.lastName != null)
                          Text('${lng.t('settingsLastName')}: ${account.lastName}'),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => _logout(context),
                          icon: const Icon(Icons.logout),
                          label: Text(lng.t('settingsLogout')),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lng.t('settingsCurrentSet'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text('${lng.t('settingsName')}: $setName'),
                      const SizedBox(height: 8),
                      Text('${lng.t('settingsDescription')}: $setDescription'),
                      const SizedBox(height: 8),
                      Text('${lng.t('settingsSetId')}: $setId'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(lng.t('settingsLanguage'))),
                      AnimatedBuilder(
                        animation: lng,
                        builder: (context, child) => DropdownButton<String>(
                          value: lng.languageCode,
                          items: Localization.languageNames.entries.map((entry) =>
                            DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)),
                          ).toList(),
                          onChanged: (value) {
                            if (value != null) lng.setLanguage(value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
