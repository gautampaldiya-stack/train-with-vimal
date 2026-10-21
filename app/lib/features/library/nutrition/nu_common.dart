import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';

/// Shared bits of Nutrition & foods (`.nu-*`): diet marks, macro bar and legend, food tile, labels and maths.

double nd(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// `2,150` (Indian grouping, as the boards).
String kfmt(num v) => NumberFormat.decimalPattern('en_IN').format(v.round());

/// Board `nf`: 10 and up whole, under 10 one decimal ("7.9", "0").
String nf(num x) => x >= 10 ? '${x.round()}' : _one(x.toDouble());
String _one(double x) {
  final r = (x * 10).round() / 10;
  return r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(1);
}

/// Quantity: "1", "1.5".
String fq(num q) => _one(q.toDouble());

const dietKeys = ['veg', 'egg', 'nonveg', 'vegan'];

/// Plan cards and New plan tabs: Veg · Eggetarian · Non-veg · Vegan.
const dietPlan = {'veg': 'Veg', 'egg': 'Eggetarian', 'nonveg': 'Non-veg', 'vegan': 'Vegan'};

/// Food table Diet column: Veg · Egg · Non-veg · Vegan.
const dietShort = {'veg': 'Veg', 'egg': 'Egg', 'nonveg': 'Non-veg', 'vegan': 'Vegan'};

/// Diet select and the food drawer: Vegetarian · Eggetarian · Non-veg · Vegan.
const dietLong = {'veg': 'Vegetarian', 'egg': 'Eggetarian', 'nonveg': 'Non-veg', 'vegan': 'Vegan'};

/// Food library groups (API key → chip label). "mine" = foods your team made.
const foodGroups = {
  'protein': 'Protein',
  'carbs': 'Carbs',
  'fats': 'Fats',
  'veg': 'Veg',
  'fruits': 'Fruits',
  'dairy': 'Dairy',
  'indian': 'Indian dishes',
  'beverages': 'Beverages',
  'other': 'Other',
};

/// `.nu-fic` tone per group (t1–t4 = AppColors.mediaTiles).
int groupTone(String g) => switch (g) { 'carbs' || 'fats' || 'indian' => 2, 'veg' || 'fruits' => 1, 'dairy' => 3, _ => 0 };

/// Grams in the food's default serving (default unit × quantity; no unit = grams).
double servingGrams(Map f) {
  final u = f['default_unit'] as Map?;
  final q = nd(f['default_quantity'] ?? 1);
  return u == null || u['id'] == null ? q : nd(u['grams']) * q;
}

/// "1 glass · 350 g", "4 × 1 egg white · 132 g", "30 g".
String servingLabel(Map f) {
  final u = f['default_unit'] as Map?;
  final q = nd(f['default_quantity'] ?? 1);
  if (u == null || u['id'] == null) return '${fq(q)} g';
  final name = '${u['name']}';
  return '${q == 1 ? name : '${fq(q)} × $name'} · ${fq(nd(u['grams']) * q)} g';
}

/// Per-100 g value at [grams].
double at(Object? per100, double grams) => nd(per100) * grams / 100;

/// `.nu-dm`: the Indian food mark. Veg green dot, egg amber dot, non-veg red triangle, vegan green on a tint, any grey.
class DietMark extends StatelessWidget {
  const DietMark(this.diet, {super.key});
  final String diet;

  @override
  Widget build(BuildContext context) {
    final c = switch (diet) {
      'egg' => AppColors.eggAmber,
      'nonveg' => AppColors.meatRed,
      'vegan' => AppColors.mbGreenFg,
      'any' => AppColors.line2,
      _ => AppColors.vegGreen,
    };
    return Container(
      width: 13,
      height: 13,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: diet == 'vegan' ? AppColors.okBg : null,
        border: Border.all(color: c, width: 1.5),
        borderRadius: AppRadius.all(3),
      ),
      child: diet == 'nonveg'
          ? CustomPaint(size: const Size(7, 6), painter: _Tri(c))
          : Container(width: 5, height: 5, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    );
  }
}

class _Tri extends CustomPainter {
  const _Tri(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(
      Path()
        ..moveTo(s.width / 2, 0)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close(),
      Paint()..color = c);
  @override
  bool shouldRepaint(_Tri o) => o.c != c;
}

/// `.nu-dl`: mark + label.
class DietLabel extends StatelessWidget {
  const DietLabel(this.diet, {super.key, this.labels = dietShort});
  final String diet;
  final Map<String, String> labels;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, spacing: 7, children: [
        DietMark(diet),
        Text(labels[diet] ?? diet, style: AppText.s(13.5, W.w5)),
      ]);
}

/// `.nu-mb`: protein / carbs / fat split by calories (P × 4, C × 4, F × 9), 8 high, 2 apart.
class MacroBar extends StatelessWidget {
  const MacroBar({super.key, required this.p, required this.c, required this.f, this.height = 8});
  final double p, c, f, height;

  @override
  Widget build(BuildContext context) {
    final tot = p * 4 + c * 4 + f * 9;
    final parts = [(p * 4, AppColors.nuProtein), (c * 4, AppColors.nuCarbs), (f * 9, AppColors.nuFat)];
    return ClipRRect(
      borderRadius: AppRadius.all(height / 2),
      child: Container(
        height: height,
        color: AppColors.sub,
        child: tot <= 0
            ? null
            : Row(spacing: 2, children: [
                for (final (v, col) in parts)
                  if (v > 0) Expanded(flex: (v / tot * 1000).round().clamp(1, 1000), child: Container(color: col)),
              ]),
      ),
    );
  }
}

/// `.nu-ml`: "■ Protein 150 g  ■ Carbs 220 g  ■ Fat 65 g".
class MacroLegend extends StatelessWidget {
  const MacroLegend({super.key, required this.p, required this.c, required this.f});
  final num p, c, f;

  @override
  Widget build(BuildContext context) {
    Widget one(String l, num v, Color col) => Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: col, borderRadius: AppRadius.all(2))),
          Text.rich(TextSpan(children: [
            TextSpan(text: '$l '),
            TextSpan(text: '${nf(v)} g', style: AppText.s(12, W.w7, color: AppColors.text)),
          ]), style: AppText.s(12, W.w6, color: AppColors.muted)),
        ]);
    return Wrap(spacing: 14, runSpacing: 4, children: [
      one('Protein', p, AppColors.nuProtein),
      one('Carbs', c, AppColors.nuCarbs),
      one('Fat', f, AppColors.nuFat),
    ]);
  }
}

/// `.nu-fic`: the bowl on a soft gradient (tone 0–3).
class FoodTile extends StatelessWidget {
  const FoodTile({super.key, this.tone = 0, this.size = 34});
  final int tone;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = AppColors.mediaTiles[tone % 4];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: AppRadius.all(8),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [t.$1, t.$2]),
      ),
      child: AppIcon(AppIcons.bowl, size: 18, color: AppColors.mediaFg),
    );
  }
}
