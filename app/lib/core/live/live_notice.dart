/// The workout's own notification while a workout runs (tracker F34): Android shows it in the shade with the
/// workout clock, the exercise and the set ("Overhead press · 88 kg × 5 (2 of 7)") and a Complete set button;
/// during rest a bar with Pause / Skip / +30 sec. Web and iOS: nothing (iOS Live Activity is parked).
library;

export 'live_notice_stub.dart' if (dart.library.io) 'live_notice_io.dart';
