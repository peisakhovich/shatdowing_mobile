import 'package:audio_service/audio_service.dart';

class ShadowingAudioHandler extends BaseAudioHandler {
  ShadowingAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.play,
          MediaControl.pause,
          MediaControl.stop,
        ],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> play() async {
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        controls: const [MediaControl.pause, MediaControl.stop],
      ),
    );
  }

  @override
  Future<void> pause() async {
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        controls: const [MediaControl.play, MediaControl.stop],
      ),
    );
  }

  @override
  Future<void> stop() async {
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        controls: const [MediaControl.play],
      ),
    );

    await super.stop();
  }
}
