import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sound and vibration in the logger (tracker G50): a tick on "set complete", a buzz and the "Rest is over"
/// notification sound when the rest ends. Both can be turned off in My account → Workout. The phone's own silent /
/// vibrate / do-not-disturb modes always win: Android plays these only when the phone allows them.
class WorkoutFeel {
  WorkoutFeel._();

  static const _soundKey = 'twv.workout.sound', _hapticsKey = 'twv.workout.haptics';
  static bool sound = true, haptics = true;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      sound = p.getBool(_soundKey) ?? true;
      haptics = p.getBool(_hapticsKey) ?? true;
      _loaded = true;
    } catch (_) {}
  }

  static Future<void> save({bool? sound, bool? haptics}) async {
    if (sound != null) WorkoutFeel.sound = sound;
    if (haptics != null) WorkoutFeel.haptics = haptics;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_soundKey, WorkoutFeel.sound);
      await p.setBool(_hapticsKey, WorkoutFeel.haptics);
    } catch (_) {}
  }

  // short sounds like Strong (Probid 17 Nov): a set ticked, a rest skipped or removed, a rest over (the ring bell
  // Probid sent). They play on the MEDIA volume, not the notification / ring volume (the bell was too loud there),
  // and over music without stopping it.
  static final _players = <String, Future<AudioPlayer?>>{};
  static final _ctx = AudioContext(
    android: const AudioContextAndroid(usageType: AndroidUsageType.media, contentType: AndroidContentType.sonification, audioFocus: AndroidAudioFocus.none),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: const {AVAudioSessionOptions.mixWithOthers}),
  );
  static const _files = {'set_done': 'set_done.wav', 'rest_skip': 'rest_skip.wav', 'rest_over': 'rest_over.mp3'};

  /// One ready player per sound: audio context, mode and file are set (and awaited) before the first play, so the
  /// first tick is not silent (Probid 17 Nov: no sound on the phone). The media player is used for all three; the
  /// low-latency pool dropped sounds that were played before they had loaded.
  static Future<AudioPlayer?> _ready(String name) => _players[name] ??= () async {
        try {
          final p = AudioPlayer(playerId: 'twv_$name');
          await p.setAudioContext(_ctx);
          await p.setPlayerMode(PlayerMode.mediaPlayer);
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource('sounds/${_files[name]}'));
          return p;
        } catch (e) {
          debugPrint('Workout sound $name: $e');
          _players.remove(name); // try again next time
          return null;
        }
      }();

  /// Loads the three sounds when the logger opens, so the first one plays at once.
  static Future<void> warm() async {
    if (!sound || kIsWeb) return;
    for (final n in _files.keys) {
      await _ready(n);
    }
  }

  static Future<void> _play(String name, {double volume = .8}) async {
    if (!sound) return;
    try {
      final p = await _ready(name);
      if (p == null) return;
      await p.stop(); // back to the start (the file stays loaded)
      await p.setVolume(volume);
      await p.resume();
    } catch (e) {
      debugPrint('Workout sound $name: $e');
    }
  }

  /// A set was ticked.
  static void setDone() {
    if (haptics) HapticFeedback.mediumImpact();
    _play('set_done');
  }

  /// A rest was skipped, or the rest of a set was removed.
  static void restSkipped() {
    if (haptics) HapticFeedback.lightImpact();
    _play('rest_skip');
  }

  /// 3, 2, 1 seconds before the rest ends: one buzz each (Probid 17 Nov: 3 times, then the bell).
  static void restCountdown() {
    if (haptics) HapticFeedback.vibrate();
  }

  /// The rest ran out while the app is open: a ring bell like a fight starting (Probid 17 Nov). In the background
  /// the notification rings.
  static void restOver() {
    if (haptics) HapticFeedback.heavyImpact();
    _play('rest_over', volume: .7);
  }

  /// Tick with an empty box: the tick button shakes (Strong).
  static void refused() {
    if (haptics) HapticFeedback.vibrate();
  }
}
