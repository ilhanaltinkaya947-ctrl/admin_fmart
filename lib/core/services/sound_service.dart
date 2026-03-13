import 'package:audioplayers/audioplayers.dart';

class SoundService {
  final AudioPlayer _player = AudioPlayer();
  bool _isRinging = false;

  Future<void> ring() async {
    if (_isRinging) return;
    _isRinging = true;

    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    await _player.play(AssetSource('sounds/new_order.mp3'));
  }

  Future<void> stop() async {
    _isRinging = false;
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
