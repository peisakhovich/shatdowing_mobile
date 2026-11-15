import 'package:flutter/material.dart';

import '../localization/localization.dart';
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
    return AnimatedBuilder(
      animation: lng,
      builder: (context, child) => _buildLocalizedContent(context),
    );
  }

  Widget _buildLocalizedContent(BuildContext context) {
    final account = UserSession.instance.account;

    return Scaffold(
      appBar: AppBar(title: Text(lng.t('setsTitle'))),
      body: account == null
          ? Center(
              child: Text(lng.t('setsLoginRequired')),
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
                          Text(lng.t('setsLoadError'), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _retryLoading,
                            icon: const Icon(Icons.refresh),
                            label: Text(lng.t('commonRetry')),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final sets = snapshot.data ?? [];

                if (sets.isEmpty) {
                  return Center(
                    child: Text(lng.t('setsEmpty')),
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
                              lng.t('setsCount', params: {'index': set.setIndex, 'count': set.itemsCount}),
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
