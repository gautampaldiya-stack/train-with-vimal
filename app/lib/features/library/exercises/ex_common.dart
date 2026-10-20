import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';

/// Shared bits of the Exercise pages (boards `ExerciseLibrary`, `ExerciseDetail`, `ExerciseAdd`).

const muscleLabels = {'chest': 'Chest', 'back': 'Back', 'legs': 'Legs', 'shoulders': 'Shoulders', 'arms': 'Arms', 'core': 'Core', 'cardio': 'Cardio'};
const equipmentLabels = {
  'barbell': 'Barbell',
  'dumbbell': 'Dumbbell',
  'cable': 'Cable',
  'machine': 'Machine',
  'bodyweight': 'Bodyweight',
  'kettlebell': 'Kettlebell',
  'band': 'Band',
  'other': 'Other',
};
const levelLabels = {'beginner': 'Beginner', 'intermediate': 'Intermediate', 'advanced': 'Advanced'};

String exMuscleLabel(Map e) => muscleLabels['${e['muscle_group']}'] ?? '${e['muscle_group'] ?? ''}';
String exEquipLabel(Map e) => equipmentLabels['${e['equipment']}'] ?? '${e['equipment'] ?? ''}';
String exLevelLabel(Map e) => levelLabels['${e['level']}'] ?? '${e['level'] ?? ''}';

/// Level badge: Beginner green, Intermediate amber, Advanced red.
Tone levelTone(String level) => switch (level) { 'beginner' => Tone.ok, 'intermediate' => Tone.warn, _ => Tone.bad };

/// "2 programs" / "1 program" / "No program yet".
String usedLabel(Object? n) {
  final k = (n as num?)?.toInt() ?? 0;
  return k == 0 ? 'No program yet' : (k == 1 ? '1 program' : '$k programs');
}

/// "0:42".
String clock(Object? seconds) {
  final s = (seconds as num?)?.toInt() ?? 0;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Client logs line for a log type: "kg × reps", "Time", "Cardio".
String logLabel(Object? t) => switch ('$t') { 'time' => 'Time per set', 'distance' => 'Minutes and km', 'bodyweight_reps' => 'Bodyweight reps', _ => 'kg × reps' };

/// Tone index for the picture-less tiles (`.media.t1`–`t4`), steady per exercise.
int exTone(Map e) => '${e['id'] ?? e['name']}'.codeUnits.fold(0, (a, c) => a + c) % 4;

bool hasVideo(Map e) => e['media'] != null || '${e['youtube_url'] ?? ''}'.isNotEmpty;

/// `.media` cover: the exercise's picture when it has one, else the tinted tile with the dumbbell. Bottom left:
/// "▶ 0:42" for a video (red for YouTube), "Image" for a picture. [radius] 0 for the card top.
class ExCover extends StatelessWidget {
  const ExCover(this.e, {super.key, this.radius = 10, this.iconSize = 30, this.badge = true, this.inset = 8});
  final Map e;
  final double radius, iconSize, inset;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final (a, b) = AppColors.mediaTiles[exTone(e)];
    final thumb = e['thumb'] as String?;
    final media = e['media'] as Map?;
    final yt = media == null && '${e['youtube_url'] ?? ''}'.isNotEmpty;
    final dur = (media?['duration'] as num?)?.toInt() ?? 0;
    final tile = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b])),
      child: AppIcon(AppIcons.dumbbell, size: iconSize, color: AppColors.mediaFg, stroke: 1.6),
    );
    Widget? tag;
    if (badge && (media != null || yt)) {
      tag = Container(
        height: 18,
        padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
        decoration: BoxDecoration(color: yt ? AppColors.ytRed : AppColors.playBadge, borderRadius: AppRadius.all(9)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          const AppIcon(AppIcons.play, size: 10, color: AppColors.white, fill: true),
          Text(yt ? 'YouTube' : (dur > 0 ? clock(dur) : 'Video'), style: AppText.s(10, W.w7, color: AppColors.white)),
        ]),
      );
    } else if (badge && thumb != null) {
      tag = Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .85), borderRadius: AppRadius.all(9)),
        child: Text('Image', style: AppText.s(10, W.w7, color: AppColors.text2)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(fit: StackFit.expand, children: [
        tile,
        if (thumb != null) Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => tile),
        if (tag != null) Positioned(left: inset, bottom: inset, child: tag),
      ]),
    );
  }
}

/// `.ex-lvl` meter: three bars, blue up to [n].
class LevelBars extends StatelessWidget {
  const LevelBars(this.n, {super.key});
  final int n;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        for (var i = 0; i < 3; i++)
          Container(width: 16, height: 6, decoration: BoxDecoration(color: i < n ? AppColors.accent : AppColors.line, borderRadius: AppRadius.all(3))),
      ]);
}
