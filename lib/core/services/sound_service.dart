import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the new-order siren and GUARANTEES it keeps sounding until [stop] is
/// called, no matter what the OS does to the audio session.
///
/// History of why this is written the way it is:
///
/// v1 used a single `_isRinging` bool reset only in [stop]. Any OS audio
/// interruption (an incoming call, the co-firing OneSignal notification sound
/// `alarm_loop.caf`, another app grabbing the session, backgrounding) silently
/// stopped the player but left the flag TRUE, so every later `ring()` no-op'd —
/// the store heard the siren once and then went silent for every following
/// order until relaunch. That is the "плей 5-10 сек и нет звука / при проверке
/// работает, потом пропадает" report.
///
/// v2 tried to detect interruptions via the player STATE (`onPlayerStateChanged`
/// / `_player.state`). That is unreliable on iOS: audioplayers emits `completed`
/// on every loop wrap of the short asset and never reports `playing` back, and
/// its iOS plugin has NO interruption observers — so state cannot distinguish
/// "looping happily" from "interrupted". State-driven re-arming therefore either
/// thrashed during healthy play or missed real interruptions.
///
/// v3 (this) drops state detection entirely and relies on a single robust
/// primitive: while the alarm SHOULD be ringing, re-issue `play()` on a short
/// fixed interval. `play()` re-activates the audio session, so the siren:
///   * recovers from ANY interruption within one interval (no event needed);
///   * can never get permanently wedged (nothing to get stuck);
///   * is never left playing after [stop] (post-play `_shouldRing` re-check).
/// The interval is far longer than the short looping asset, so healthy playback
/// is not disturbed. Intent lives in [_shouldRing], flipped true by [ring] and
/// false ONLY by [stop]/[dispose]. The iOS `playback` category is — per Apple —
/// not silenced by the Ring/Silent switch or screen locking, so a muted or
/// locked iPad still sounds the alarm.
class SoundService {
  final AudioPlayer _player = AudioPlayer();
  Timer? _watchdog;

  /// Caller intent: true between [ring] and [stop]. The only latch, reset
  /// exclusively by [stop]/[dispose] — never by a playback event.
  bool _shouldRing = false;
  bool _rearming = false;
  bool _configured = false;

  // Re-assert cadence. Comfortably longer than the short looping asset so
  // healthy playback isn't disturbed, short enough that recovery from an
  // interruption is near-immediate.
  static const Duration _reassert = Duration(seconds: 3);

  static final AssetSource _asset = AssetSource('sounds/new_order.mp3');

  // iOS `playback`: not silenced by the mute switch or screen lock (per Apple).
  // No options — the alarm should take the output at full volume (duckOthers
  // here would only duck *our own* session and does not affect the separate
  // system notification-sound path). Android (defensive; admin is iPad-first):
  // route as an ALARM through the speaker.
  static final AudioContext _alarmContext = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
    android: const AudioContextAndroid(
      isSpeakerphoneOn: true,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.alarm,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _player.setAudioContext(_alarmContext);
      await _player.setReleaseMode(ReleaseMode.loop);
      _configured = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[SoundService] config failed: $e');
      // Leave _configured false so the next ring()/re-arm retries it.
    }
  }

  /// Start (or ensure) the looping siren. Idempotent and interruption-proof:
  /// safe to call repeatedly; once called it keeps sounding until [stop].
  Future<void> ring() async {
    _shouldRing = true;
    await _ensureConfigured();
    await _rearm();
    // Periodic re-assert (see class doc). One watchdog only.
    _watchdog ??= Timer.periodic(_reassert, (_) {
      if (_shouldRing) unawaited(_rearm());
    });
  }

  /// (Re)start playback iff we should be ringing. Guarded so overlapping
  /// re-asserts can't stack, and re-checks intent AFTER the async play so a
  /// [stop] that interleaves can't be undone (leaving the siren stuck ON).
  Future<void> _rearm() async {
    if (!_shouldRing || _rearming) return;
    _rearming = true;
    try {
      await _ensureConfigured();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(_asset, volume: 1.0, ctx: _alarmContext);
      if (!_shouldRing) {
        // stop() ran during the awaits above; undo the restart it couldn't see.
        await _player.stop();
      }
    } catch (e) {
      // Swallow — the watchdog retries within _reassert (e.g. the session is
      // still held by an in-progress interruption). Never throw upstream.
      if (kDebugMode) debugPrint('[SoundService] re-arm failed: $e');
    } finally {
      _rearming = false;
    }
  }

  /// Silence the siren and clear intent. The only place besides [dispose] where
  /// [_shouldRing] goes false.
  Future<void> stop() async {
    _shouldRing = false;
    _watchdog?.cancel();
    _watchdog = null;
    try {
      await _player.stop();
    } catch (_) {/* already stopped / disposed */}
  }

  Future<void> dispose() async {
    _shouldRing = false;
    _watchdog?.cancel();
    _watchdog = null;
    try {
      await _player.dispose();
    } catch (_) {/* already disposed */}
  }
}
