import 'package:audio_service/audio_service.dart';

class BluetoothAudioHandler extends BaseAudioHandler {
  BluetoothAudioHandler() {
    // Название аудиосессии для Bluetooth-устройств.
    mediaItem.add(
      const MediaItem(
        id: 'sound-language-studio',
        title: 'Sound Language Studio',
        artist: 'Shadowing Player',
        album: 'Language Practice',
      ),
    );

    _publishPlaybackState(playing: false);
  }

  void _publishPlaybackState({required bool playing}) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );
  }

  /// Обновление состояния из основного интерфейса.
  void updatePlayingState(bool playing) {
    _publishPlaybackState(playing: playing);
  }

  /// Обновляет название текущего учебного элемента.
  void updateTrack({required String title, required int trackNumber}) {
    mediaItem.add(
      MediaItem(
        id: 'track-$trackNumber',
        title: title.isEmpty ? 'Sound Language Studio' : title,
        artist: 'Track $trackNumber',
        album: 'Sound Language Studio',
      ),
    );
  }

  @override
  Future<void> play() async {
    customEvent.add('play');
    _publishPlaybackState(playing: true);
  }

  @override
  Future<void> pause() async {
    customEvent.add('pause');
    _publishPlaybackState(playing: false);
  }

  @override
  Future<void> skipToNext() async {
    customEvent.add('next');
  }

  @override
  Future<void> skipToPrevious() async {
    customEvent.add('previous');
  }
}
