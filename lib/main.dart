import 'package:flutter/material.dart';

import 'localization/localization.dart';
import 'screens/player_screen.dart';
import 'services/user_session.dart';
import 'services/bluetooth_audio_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await lng.initialize();
  await UserSession.instance.restoreSession();
  await BluetoothAudioService.initialize();
  runApp(const SoundLanguageStudioApp());
}

class SoundLanguageStudioApp extends StatelessWidget {
  const SoundLanguageStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: lng,
      builder: (context, child) => MaterialApp(
        title: lng.t('appTitle'),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const PlayerScreen(setId: 69),
      ),
    );
  }
}
