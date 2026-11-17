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

  // short sounds like Strong (Probid 17 Nov): a set ticked, a rest skipped or removed, a rest over.
  // They follow the phone's silent mode (respectSilence) and play over music without stopping it.
  static final _players = <String, AudioPlayer>{};

  static Future<void> _play(String name) async {
    if (!sound) return;
    try {
      final p = _players[name] ??= AudioPlayer()
        ..setPlayerMode(PlayerMode.lowLatency)
        ..setAudioContext(AudioContextConfig(respectSilence: true, focus: AudioContextConfigFocus.mixWithOthers).build())
        ..setReleaseMode(ReleaseMode.stop);
      await p.stop();
      await p.play(AssetSource('sounds/$name.wav'), volume: .8);
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

  /// The rest ran out while the app is open (in the background the notification rings).
  static void restOver() {
    if (haptics) HapticFeedback.heavyImpact();
    _play('rest_over');
  }

  /// Tick with an empty box: the tick button shakes (Strong).
  static void refused() {
    if (haptics) HapticFeedback.vibrate();
  }
}
