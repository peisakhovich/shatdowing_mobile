import 'package:flutter/material.dart';

import '../models/user_set.dart';
import '../services/api_client.dart';
import '../services/user_session.dart';

class SetSelectionScreen extends StatefulWidget {
  const SetSelectionScreen({super.key});

  @override
  State<SetSelectionScreen> createState() => _SetSelectionScreenState();
}

class _SetSelectionScreenState extends State<SetSelectionScreen> {
  final ApiClient _apiClient = ApiClient();

  late Future<List<UserSet>> _setsFuture;

  @override
  void initState() {
    super.initState();
    _loadSets();
  }

  void _loadSets() {
    final account = UserSession.instance.account;

    if (account == null) {
      _setsFuture = Future.value([]);
      return;
    }

    _setsFuture = _apiClient.getMobileReadySets(account.userId);
  }

  void _retryLoading() {
    setState(() {
      _loadSets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = UserSession.instance.account;

    return Scaffold(
      appBar: AppBar(title: const Text('Выбор учебного набора')),
      body: account == null
          ? const Center(
              child: Text('Для выбора набора необходимо войти в систему.'),
            )
          : FutureBuilder<List<UserSet>>(
              future: _setsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Не удалось загрузить учебные наборы.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _retryLoading,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final sets = snapshot.data ?? [];

                if (sets.isEmpty) {
                  return const Center(
                    child: Text('У пользователя пока нет учебных наборов.'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sets.length,
                  itemBuilder: (context, index) {
                    final set = sets[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.library_music_outlined),
                        title: Text(set.setName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (set.setDescription.isNotEmpty)
                              Text(set.setDescription),
                            const SizedBox(height: 4),
                            Text(
                              'Набор № ${set.setIndex} · '
                              '${set.itemsCount} фраз',
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).pop(set);
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
