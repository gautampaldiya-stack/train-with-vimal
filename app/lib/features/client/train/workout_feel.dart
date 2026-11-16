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

  /// A set was ticked.
  static void setDone() {
    if (haptics) HapticFeedback.mediumImpact();
    if (sound) SystemSound.play(SystemSoundType.click);
  }

  /// The rest ran out while the logger is open (the notification brings the sound).
  static void restOver() {
    if (haptics) HapticFeedback.heavyImpact();
  }
}
