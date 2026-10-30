import 'package:flutter/material.dart';

import 'screens/player_screen.dart';

void main() {
  runApp(const SoundLanguageStudioApp());
}

class SoundLanguageStudioApp extends StatelessWidget {
  const SoundLanguageStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sound Language Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const PlayerScreen(setId: 69),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sound Language Studio')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.headphones, size: 72, color: Colors.teal),
              const SizedBox(height: 24),
              const Text(
                'Изучайте языки на слух',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Выберите готовый набор фраз '
                'и занимайтесь в удобном темпе.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.library_music),
                  label: const Text('Мои наборы'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
