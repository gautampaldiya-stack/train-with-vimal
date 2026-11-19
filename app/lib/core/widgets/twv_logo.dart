import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// App logo. Uses the white-letter version on dark theme so it stays readable on black.
class TwvLogo extends StatelessWidget {
  const TwvLogo({super.key, this.size});
  final double? size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(dark ? 'assets/logo_dark.svg' : 'assets/logo.svg', width: size, height: size);
  }
}
