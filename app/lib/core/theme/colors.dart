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
  static const amberLine = Color(0xFFF6D99B), amberDeep = Color(0xFF8A5300); // off-plan chip on
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

  // Client Home (ch-*)
  static const tickRing = Color(0xFFCFCFC9); // empty tick / rest-day dashed ring
  static const daySubOn = Color(0xFFC9C9C9); // weekday letter on the black picked day
  static const barTrack = Color(0xFFEDEDE9);
  static const carbs = Color(0xFFD9A100), fat = Color(0xFFDB2777);
  static const warmBg = Color(0xFFFFF1EA), warm = Color(0xFFFF7A45); // water
  static const icAmberBg = Color(0xFFFFF4E0), icAmberText = Color(0xFF9A5B00);
  static const nextBg = Color(0xFFF7F7F4);
  static const sessText = Color(0xFF1E3A8A);
  static const heroGreen = [Color(0xFFEEF6EF), Color(0xFFF8FBF8)];
  // Home hero (ClientHomeHero board, Gautam picked it 2026-10-16): sky → blue gradient, white text on it.
  static const homeHero = [Color(0xFF4FB8EE), Color(0xFF2F8FE6), Color(0xFF2563EB)];
  static const homeHeroBtn = Color(0x33FFFFFF); // bell button (white 20%)
  static const homeHeroDotRing = Color(0xFF3A9DEA);
  static const homeHeroSub = Color(0xE6FFFFFF); // 90% white
  static const weekShadow = Color(0x14171717); // 0 6 18 / .08 under the week strip
  static const heroBlue = [Color(0xFFEAF1FE), Color(0xFFF7FAFF)];
  static const heroGray = [Color(0xFFF1F1EE), Color(0xFFFAFAF8)];
  static const chevron = Color(0xFFA1A19B);
  static const strike = Color(0xFFB5B5AF);
  static const avGreenBg = Color(0xFFDCFCE7), avGreenText = Color(0xFF166534);

  // Client Train / Workout logger (tn-*, cg-*, bm-*, cl-*, cr-*, cd-*)
  static const tnBlueBg = Color(0xFFEAF1FE);
  static const noteBg = Color(0xFFE7EEFC), noteLine = Color(0xFFCFDDFA); // coach note in the guide
  static const videoScrim = [Color(0x00000000), Color(0x8C000000)]; // under the video controls
  static const videoDark = [Color(0xFF1F2937), Color(0xFF3F4A5A)];
  static const bmOff = Color(0xFFDCDCD5), bmStrong = Color(0xFF7FA3F0), bmLight = Color(0xFFC9D8FA);
  static const metOff = Color(0xFFE5E5E0);
  static const valPh = Color(0xFFA3A39C), tickOff = Color(0xFFC9C9C3), pressed = Color(0xFFE6E6E0);
  static const doneValBg = Color(0xFFEEF9F2), doneValLine = Color(0xFFBFE8CF);
  static const restAmber = Color(0xFFF5B544);
  static const goneGray = Color(0xFF6B6B66), goneRing = Color(0xFFEDEDEA);

  // Toasts
  static const toastStaff = Color(0xFF1F1F1F), toastStaffSub = Color(0xFFB5B5B0), toastStaffAction = Color(0xFF93B4FF);
  static const toastInk = Color(0xFF0E0F0C);
  static const toastInfo = Color(0xFF7CC4FF), toastWarn = Color(0xFFFFD166), toastErr = Color(0xFFFF7A45);
  static const toastDel = Color(0xFF2A2C25), toastDelText = Color(0xFFF2F3EC);
  static const truncTip = Color(0xFF1F1F22);

  // Scrims
  // Habits & supplements board (`hk-*`)
  static const missDot = Color(0xFFF6D2CF); // missed day dot, legend
  static const missBar = Color(0xFFF2A7A3); // missed day bar
  static const partDay = Color(0xFFFDE7C7); // week strip: some habits missed
  static const soonBg = Color(0xFFFCFCFA); // habit that starts later
  static const missTickBg = Color(0xFFFFF5F4);
  static const streak = Color(0xFFC2410C);
  static const cellBg = Color(0xFFF7F7F4); // stat cells, notes
  static const offA = Color(0xFFF3F3F0), offB = Color(0xFFFAFAF8); // not started stripes
  static const futCell = Color(0xFFF5F5F2), futLine = Color(0xFFD6D6D0), futLegend = Color(0xFFC9C9C3);
  static const lowText = Color(0xFF8A4B00); // running low

  // Food board (`nv-*`)
  static const nvCarbs = Color(0xFF38BDF8), nvFat = Color(0xFFF97316); // macro bars on the Food page
  static const wkBar = Color(0xFFD7DEEA), wkToday = Color(0xFF93B4F5), wkHi = Color(0xFFFCD38A); // This week bars; wkToday is also the target line

  // Check-ins board (`ck-*`)
  static const replyBg = Color(0xFFF2F7F3); // coach reply under a row / in the sheet
  static const slotOn = [Color(0xFFE9F1EA), Color(0xFFD7E6DA)], slotOnLine = Color(0xFF9AD8AE); // photo slot filled
  static const figBg = [Color(0xFFE9EEF0), Color(0xFFD5DEE2)], figText = Color(0xFF6B7B83); // photo placeholder
  static const scrimModal = Color(0x5C171717); // rgba(23,23,23,.36)
  static const scrimDrawer = Color(0x4D171717); // .30
  static const scrimSheet = Color(0x61111111); // rgba(17,17,17,.38)
  // Progress board (`px-*`)
  static const pxTiles = [ // photo placeholders t1–t4: (from, to, figure)
    (Color(0xFFEEF3FE), Color(0xFFD9E4FC), Color(0xFF7B95D6)),
    (Color(0xFFEDF7F1), Color(0xFFD3EEDD), Color(0xFF5E9F78)),
    (Color(0xFFFFF6E8), Color(0xFFFBE3BE), Color(0xFFC08A3A)),
    (Color(0xFFF4F0FE), Color(0xFFE1D7FB), Color(0xFF8B72CF)),
  ];
  static const pxNone = Color(0xFFFAFAF8), pxNone2 = Color(0xFFF3F3F0), pxNoneFig = Color(0xFFC9C9C4); // "No photo" stripes
  static const pxBar = Color(0xFFA8C2F7), pxBarLo = Color(0xFFF5C46B), pxBarLoOn = Color(0xFFE39B12); // adherence bars
  static const pxHist = Color(0xFF93B4F8); // older measurement bars
  static const pxGoal = Color(0xFF16A34A); // goal line on the weight chart
  static const pxPoseBg = Color(0xE0FFFFFF); // pose label on a photo
  static const moAvBg = Color(0xFFFFE4D6), moAvText = Color(0xFF9A3412); // More: the client's own avatar
  static const lbPlayShadow = Color(0x29171717); // Library video play button (0 4 16 / .16)
  static const lbImgBg = Color(0xFFF3FAF5), lbImgLine = Color(0xFFCFE9D9); // Library image box (lb-img)
  static const moBan = Color(0xFFFFF8E6); // "Account deletion on …" banner (border amberLine, text amberDeep)
  static const moSwOff = Color(0xFFD9D9D4); // switch track off
  static const moBadBox = Color(0xFFFFFAFA), moBadLine = Color(0xFFF3C6C7); // Delete my account box
  static const viewerBg = Color(0xF0111111), viewerBtn = Color(0x29FFFFFF), viewerBtnHover = Color(0x47FFFFFF), viewerBtnDark = Color(0x8C111111); // full-size photo viewer

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
