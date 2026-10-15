import 'package:flutter/painting.dart';

/// Every colour in the app. Values come from design/screens/twv.css (:root) and docs/design.md §1.1.
/// Widgets never use a hex value directly — always one of these.
abstract final class AppColors {
  static const bg = Color(0xFFF5F5F5);
  static const panel = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const sub = Color(0xFFF1F1EE);
  static const hover = Color(0xFFEEF3FE);
  static const line = Color(0xFFE6E6E1);
  static const line2 = Color(0xFFD4D4CE);
  static const lineHover = Color(0xFFBDBDB6);
  static const text = Color(0xFF171717);
  static const text2 = Color(0xFF3F3F46);
  static const muted = Color(0xFF6B6B70);
  static const accent = Color(0xFF2563EB);
  static const accentHover = Color(0xFF1D4ED8);
  static const accentSoft = Color(0xFFEAF0FE);
  static const accentText = Color(0xFF1D4ED8);
  static const accentRing = Color(0xFFBFD3FB);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  static const okBg = Color(0xFFE8F6EE), okText = Color(0xFF11663D), okSolid = Color(0xFF22C55E);
  static const warnBg = Color(0xFFFFF1E6), warnText = Color(0xFF9A3A10);
  static const badBg = Color(0xFFFDECEC), badText = Color(0xFFA4231B), badHoverBg = Color(0xFFF9DCDA);
  static const infoBg = Color(0xFFEAF0FE), infoText = Color(0xFF1D4ED8);

  static const red = Color(0xFFE5484D), redHover = Color(0xFFCE2C31);
  static const darkHover = Color(0xFF333333);
  static const outlineHover = Color(0xFFF6F6F3);
  static const tableHead = Color(0xFFFBFBF9);
  static const navActive = Color(0xFFFAFAFA);

  // Client app
  static const caBg = Color(0xFFF5F5F3);
  static const caWebBg = Color(0xFFFAFAF8);
  static const caAvBg = Color(0xFFE0E7FF), caAvText = Color(0xFF3730A3);
  static const grab = Color(0xFFD9D9D4);

  // Login / setup boards (wl-*)
  static const amberBg = Color(0xFFFFF4DB), amberText = Color(0xFFA15C00), amberSolid = Color(0xFFF59E0B);
  static const sky = Color(0xFF4FB8EE), skyMid = Color(0xFF2F8FE6), skySoft = Color(0xFFE3F3FD), skyFade = Color(0xFFF7FBFE);
  static const brandSoft = Color(0xFFEEF3FD); // web login side panel
  static const purpleBg = Color(0xFFF1ECFE), purpleText = Color(0xFF6D28D9); // ch-ic purple
  static const dotOff = Color(0xFFCBD5E1); // intro slide dots
  static const shadowSoft = Color(0x0A171717), shadowBlue = Color(0x142563EB); // intro picture card
  static const pickBg = Color(0xFFF7FAFF); // selected goal / diet / option card
  static const segTrack = Color(0xFFE4E4DF); // setup progress segments
  static const dayOff = Color(0xFFE8E8E4);
  static const vegGreen = Color(0xFF16A34A), eggAmber = Color(0xFFD97706), meatRed = Color(0xFFB91C1C);
  static const track = Color(0xFFECECE8);

  // Toasts
  static const toastStaff = Color(0xFF1F1F1F), toastStaffSub = Color(0xFFB5B5B0), toastStaffAction = Color(0xFF93B4FF);
  static const toastInk = Color(0xFF0E0F0C);
  static const toastInfo = Color(0xFF7CC4FF), toastWarn = Color(0xFFFFD166), toastErr = Color(0xFFFF7A45);
  static const toastDel = Color(0xFF2A2C25), toastDelText = Color(0xFFF2F3EC);
  static const truncTip = Color(0xFF1F1F22);

  // Scrims
  static const scrimModal = Color(0x5C171717); // rgba(23,23,23,.36)
  static const scrimDrawer = Color(0x4D171717); // .30
  static const scrimSheet = Color(0x61111111); // rgba(17,17,17,.38)

  /// Avatar pairs (bg, text), picked from the name so a person keeps their colour.
  static const avatars = [
    (Color(0xFFE0EAFF), Color(0xFF1E40AF)),
    (Color(0xFFE8F6EE), Color(0xFF11663D)),
    (Color(0xFFFFF1E6), Color(0xFF9A3A10)),
    (Color(0xFFF1EAFE), Color(0xFF5B21B6)),
    (Color(0xFFFDECF3), Color(0xFF9D174D)),
    (Color(0xFFE6F6F8), Color(0xFF0E6874)),
  ];

  static (Color, Color) avatarFor(String name) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h + c) % avatars.length;
    }
    return avatars[h];
  }
}

enum Tone { ok, warn, bad, info, neutral }

extension ToneColors on Tone {
  Color get bg => switch (this) {
        Tone.ok => AppColors.okBg,
        Tone.warn => AppColors.warnBg,
        Tone.bad => AppColors.badBg,
        Tone.info => AppColors.infoBg,
        Tone.neutral => AppColors.sub,
      };
  Color get fg => switch (this) {
        Tone.ok => AppColors.okText,
        Tone.warn => AppColors.warnText,
        Tone.bad => AppColors.badText,
        Tone.info => AppColors.infoText,
        Tone.neutral => AppColors.text2,
      };
}
