import 'package:just_audio/just_audio.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playFile(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.play();
  }

  Future<void> playAsset(String assetPath) async {
    await _player.setAsset(assetPath);
    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
