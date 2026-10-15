# Train With Vimal — Design system

Source: live design canvas (`Main.dc.html` = design system board) + `design/screens/twv.css` (canvas v282, 14 Oct 2026).
Jo bhi yahan likha hai wo **asli CSS se nikala hua** hai, yaad se nahi.

> **Rule #1 — Flutter UI = canvas, same-to-same.** Screen banane se pehle uski `.dc.html` kholo, aur size, spacing, radius, colour, copy aur states copy karo. Design galat lage to **pehle poocho**, chup-chaap "improve" mat karo.
>
> **Rule #2 — hardcoded colour nahi.** Sab kuch `lib/core/theme` ke tokens se. Niche ki har value ek token banni chahiye.
>

---

## Contents

1. [Tokens](#1-tokens) — colours, type, radius, spacing, icons
2. [Shells](#2-shells) — web app, admin/trainer phone, client app
3. [Web components](#3-web-components-admin--trainer)
4. [Overlays](#4-overlays) — menu, modal, drawer, bottom sheet, toast, tooltip
5. [Client app components](#5-client-app-components)
6. [States aur interaction rules](#6-states-aur-interaction-rules)
7. [Do / Don't](#7-do--dont)
8. [Flutter mapping](#8-flutter-mapping)
9. [Screen banane se pehle ka checklist](#9-screen-banane-se-pehle-ka-checklist)

---

## 1. Tokens

### 1.1 Colours

Ek hi light theme hai (dark theme abhi nahi hai).

| Token | Value | Kahan |
|---|---|---|
| `--bg` | `#F5F5F5` | Page ka background **aur** sidebar (dono whitesmoke) |
| `--panel` | `#FFFFFF` | Content panel (sidebar se alag dikhne ke liye) |
| `--card` | `#FFFFFF` | Cards, menus, sheets, inputs |
| `--sub` | `#F1F1EE` | Tracks, chips at rest, segmented tab ka background, close button |
| `--hover` | `#EEF3FE` | Row hover — **soft blue tint, grey nahi** |
| `--line` | `#E6E6E1` | Borders, dividers |
| `--line2` | `#D4D4CE` | Strong border (inputs, outline buttons) |
| `--text` | `#171717` | Primary text |
| `--text2` | `#3F3F46` | Secondary text, nav items |
| `--muted` | `#6B6B70` | Captions, hints, labels |
| `--accent` | `#2563EB` | Brand blue — primary button, active icon, progress fill |
| `--accent-hover` | `#1D4ED8` | Primary button hover |
| `--accent-soft` | `#EAF0FE` | Accent ka halka background (icon tiles, focus ring) |
| `--accent-text` | `#1D4ED8` | Links aur accent text (contrast ke liye thoda gehra) |

**Status pairs** (background + text, hamesha jodi me):

| Kind | bg | text | Kahan |
|---|---|---|---|
| ok | `--ok-bg #E8F6EE` | `--ok-text #11663D` | Logged, Active, Approved, up delta |
| warn | `--warn-bg #FFF1E6` | `--warn-text #9A3A10` | Pending, Skipped, Missed, over capacity |
| bad | `--bad-bg #FDECEC` | `--bad-text #A4231B` | Error, delete, down delta |
| info | `--info-bg #EAF0FE` | `--info-text #1D4ED8` | Next, Planned, neutral info |
| neutral | `--sub` | `--text2` | Koi state nahi |

**Avatar colours** (naam ke hisaab se rotate karo, random nahi):

`c1 #E0EAFF/#1E40AF` · `c2 #E8F6EE/#11663D` · `c3 #FFF1E6/#9A3A10` · `c4 #F1EAFE/#5B21B6` · `c5 #FDECF3/#9D174D` · `c6 #E6F6F8/#0E6874`

**Client app toast fills:** ok/star `--accent` + white · info/water `#7CC4FF` + `#0E0F0C` · warn `#FFD166` + `#0E0F0C` · err `#FF7A45` + `#0E0F0C` · del `#2A2C25` + `#F2F3EC`.

**Shadows:** menu `0 1px 2px rgba(23,23,23,.06), 0 8px 24px rgba(23,23,23,.10)` · panel `0 1px 2px rgba(23,23,23,.04), 0 4px 16px rgba(23,23,23,.04)` · modal `0 2px 6px rgba(23,23,23,.08), 0 24px 60px rgba(23,23,23,.22)`.

**Scrims:** modal `rgba(23,23,23,.36)` · drawer `rgba(23,23,23,.30)` · phone sheet `rgba(17,17,17,.38)`.

### 1.2 Type

Font: **Plus Jakarta Sans** (400–800). Base body 14px.

| Class | Size | Weight | Tracking | Kahan |
|---|---|---|---|---|
| `.h1` | 28 (phone 17–20, `clamp(20px, 2.6cqi, 28px)`) | 800 | −0.025em | Page title |
| `.h2` | 20 | 700 | −0.02em | Section |
| `.h3` | 15 | 700 | −0.01em | Card title |
| `.sub` | 13 | 500 | — | Page subtitle (muted) |
| `.cap` | 12 | 500 | — | Caption / hint (muted) |
| `.over` | 11 | 700 | .08em, UPPERCASE | Group labels (sidebar, More page) |
| body | 14 | 400–500 | — | Normal text |
| row title | 13.5 | 700 | — | List row ka naam |
| row sub | 12.5 | 500 | — | List row ki doosri line |
| stat number | 24 | 800 | −0.02em | Stats card |

Numbers wale columns pe `font-variant-numeric: tabular-nums`.

### 1.3 Radius

Nested cheez hamesha chhoti radius leti hai:

| Token | px | Kahan |
|---|---|---|
| `--r-modal` | 16 | Modal, drawer, content panel |
| `--r-card` | 12 | Cards, stats, glance tiles |
| `--r-menu` | 12 | Dropdown / filter menu |
| `--r-btn` / `--r-input` / `--r-chip` / `--r-item` | 8 | Buttons, inputs, chips, nav items, menu items |
| `--r-tab` | 6 | Segmented tab |
| `--r-badge` | 6 | Badge |
| — | 999 / 50% | Avatar, count pill, edge toggle |

Client app alag hai (phone pe sab thoda bada): card **14**, button **12** (sm 10), icon button **12** (sm 10), sheet **20 20 0 0**, toast **14**, chip 7.

### 1.4 Spacing & sizing

- 4-pt grid. Web page padding `24px 32px 48px`, content `max-width 1200`, sections ke beech gap **20**.
- Card padding `18px 20px`; card header `16px 20px 8px`; card body `4px 8px 10px`.
- Phone page padding **16**, cards ke beech gap **12** (client app) / **14** (admin phone).
- Artboards: phone **390×844**, web **1440×1000**.
- Touch target ≥ 44 (client app ke primary button 44 high isliye hai).

### 1.5 Icons

Inline stroke SVG, `viewBox 0 0 24 24`, **stroke-width 1.8**, round cap aur join, `fill: none`, colour `currentColor`.
Sizes: `.i` **16** · `.i.lg` **18** · nav/bottom-bar **22** · 3-dot `.i.dots` **20** (sm 18) · client app button **17** (sm 15).
Emoji kabhi icon ki jagah nahi.

---

## 2. Shells

### 2.1 Web app shell (admin + trainer)

```
.app  = sidebar (whitesmoke) + .main (white rounded panel)
```

- `.side` — width **240**, padding `16px 12px`, background wahi `--bg`, items ke beech gap 2.
- `.main` — white panel, 1px `--line` border, radius **16**, margin `8px 8px 8px 0`, soft shadow. Padding `24px 32px 48px`.
- Collapse: `.app.mini .side` → **68** wide, sirf icons. **Width animate nahi hoti** (warna naam beech me toot-ta hai).
- Edge toggle: panel ke kinare pe round **28px** button, `top 26px`, `right −14px`, white, 1px border. **Sirf sidebar pe hover karne par dikhta hai**. Mini me iska chevron 180° ghoom jata hai.
- Brand: 36px logo + naam (800/15) + role line (12, muted) — "Owner workspace" / "Trainer workspace". Mini me sirf logo (32px).
- `.nav` — height **34**, radius 8, gap 10, 600/13.5, colour `--text2`.
  - hover **aur** active dono ka background `#FAFAFA` + `inset 0 0 0 1px --line` (active pe thoda shadow extra).
  - Active ka **icon accent blue** ho jata hai, text nahi.
  - Count chip (`.count`) sirf Approvals pe. Mini me wo badge ban ke icon ke upar-right chipak jata hai.
- Group label `.grp` = `.over` style; mini me label ki jagah **1px line** aa jati hai.
- Mini me har nav pe hover karne par **tooltip** right me (white card, niche §4.6).
- Sidebar me **search nahi** — search page header me hai.

**Sidebar order (admin):** Dashboard · Clients · Approvals · Trainers · Calendar · Activity log — *Build:* Programs · Exercises · Nutrition & foods · Habits & supplements · Forms & check-ins · Content library — *Engage:* Automations · Emails & alerts — *Workspace:* Settings.

**Sidebar order (trainer):** Dashboard · My clients · Check-ins (count) · Calendar — *Library:* Programs · Exercises · Nutrition & foods · Habits & supplements · Content library — *You:* My profile.

### 2.2 Admin / trainer phone shell

`.app.mob` — column layout, upar fake status bar (`.ca-sb`, 34 high), beech me scrolling `.main` (border/radius hat jate hai, padding `6px 16px 24px`), niche `.mb-nav`.

- `.mb-nav` — 5 columns, white, upar 1px line, padding `6px 4px 18px` (neeche ka 18 home-indicator ke liye). Total height ~**71**.
- `.mb-tab` — icon 22 + label 11/600, muted; active `--accent`.
- `.mb-badge` — red `#E5484D` pill, icon ke upar-left, white ring.
- Phone pe modal **bottom sheet** ban jata hai: `max-width` hat jata hai, radius `18 18 0 0`, `max-height 88vh`, footer ka padding-bottom 22.
- More page: `.mb-me` (44px avatar + naam + role), `.mb-grp` (uppercase label + card), `.mb-row` height **48**, rows ke beech sirf line, icon tile `.mb-ric` 32px radius 9 accent-soft. Log out row red.

### 2.3 Client app shell

`.ca` — poori height, column: status bar → `.ca-scroll` → `.ca-tabs`.

- `.ca-scroll` — padding `6px 16px 20px`, cards ke beech gap **12**, **scrollbar chhupa hua**.
- `.ca-tabs` — 5 tabs: **Home · Train · Food · Progress · More**. Wahi 71 height, active accent.
- Background `#F5F5F3`, cards white.

---

## 3. Web components (admin + trainer)

### 3.1 Buttons

| Variant | Background | Text | Border |
|---|---|---|---|
| `.btn.pri` | `--accent` → hover `--accent-hover` | white | — |
| `.btn.dark` | `--text` → hover `#333` | white | — |
| `.btn.out` | white → hover `#F6F6F3` | `--text` | `--line2` → hover `#BDBDB6` |
| `.btn.danger` | `--bad-bg` → hover `#F9DCDA` | `--bad-text` | — |
| `.btn.text` | none | `--accent-text` → hover underline (offset 3) | — |

Heights: **36** default, `.sm` **30**, `.lg` **42**. Padding `0 14px` (icon ho to `0 12px`), gap 7, font 700/13.5, radius 8.
**Hover hamesha solid — kabhi see-through nahi.**

`.ibtn` icon button — **36×36**, radius 10, 1px `--line`, white; `.sm` 30×30 radius 8; `.ghost` me border transparent jab tak hover na ho. Red dot notification ke liye.

### 3.2 Inputs

- `.inp` — height **36**, radius 8, border `--line2`, white, font 500/14.
  - hover border `#BDBDB6` · focus border `--accent` + ring `0 0 0 3px --accent-soft` · error border `--bad-text`.
- `.field` = label (12.5/700, `--text2`) + input + hint (12 muted) ya error (12/600 red).
- Textarea: `min-height 92`, padding `10px 12px`.
- `.search` — same box, min-width 260, magnifier icon + muted placeholder, right me `.kbd` (⌘K).
- `.select` — height 36, min-width 160, 600/13.5, right me chevron; `.lead` se "Sort" jaisa prefix muted me.
- Checkbox `.box` — 16×16, radius 5, 1.5px border; checked = accent fill + white tick.
- Radio `.dr-radio` — 18×18 circle; selected = **5px accent border** (fill nahi).
- Toggle `.cp-tog` — 30×18 pill, knob 14, on = accent.

### 3.3 Tabs

- **Segmented** `.tabs` — `--sub` background, padding 4, radius 8. `.tab` height **32**, radius 6, 600/13; hover `rgba(255,255,255,.7)`; active white + `0 0 0 1px --line` + halka shadow. `.n` me count muted.
- **Underline** `.utabs` — niche 1px line, gap 20. `.utab` padding `10px 2px`, muted; active text dark + **2px dark underline**. Page ke sections ke liye.

### 3.4 Chips aur badges

- `.chip` (set filter) — height 30, radius 8, white + `--line2`, label muted + value bold, right me `×` (hover pe `--sub`).
- `.fchip` (kind filter) — height 28, radius 8; active = **dark fill** (`--text`) + white text.
- `.badge` — height **22**, radius 6, 700/11.5, aage **6px dot** (`.plain` me dot nahi). Kinds `b-ok` / `b-warn` / `b-bad` / `b-info` / `b-neu`.
- `.count` — min-width 20, height 20, radius 10, **dark fill**, white 700/11.

### 3.5 Cards aur rows

- `.card` — white, 1px `--line`, radius 12. `.pad` = `18px 20px`.
- `.card-h` — title left, action right, padding `16px 20px 8px`.
- `.row` — padding `10px 12px`, radius 8, gap 12; title 700/13.5, sub 12.5 muted; hover **`--hover` (soft blue)**, aur chevron `.go` accent ho jata hai.
- `.row.cmp` — compact (padding `7px 12px`).

### 3.6 Stats aur glance

- `.stats` — 4 columns (≤900px pe 2). `.stat` padding `12px 16px`: label (icon tile 26px accent-soft + 12.5/600 muted), phir **number 24/800 aur delta uske bagal me** (upar-niche nahi). Delta up = green, down = red.
- `.glance` — 6 chhote tiles (Clients, Trainers, Check-ins to review, Onboarding pending, Nutrition plans pending, Programs ending). Har tile: 28px icon tile, bada number 18/800, label, aur ek sub-line. `warn` variant me icon aur sub-line orange. Poora tile link hai.

### 3.7 Data table

- `.tbl` — font 13.5. `th` 12/700 muted, padding `13px 14px`, background `#FBFBF9`, niche 1px line; **vertical scroll pe header band sticky**. Card ke top pe ho to header ke corners round.
- `td` padding `12px 14px`, niche line; last row ki line nahi. Row hover `--hover`.
- `.num` right-aligned + tabular numbers.
- Pehla column checkbox, aakhri column **3-dot** `.row-dots` → menu `.row-menu` (width 200, uske neeche khulta hai).
- `.who` = avatar + naam. `.bar` = 90×6 progress, fill accent.
- Toolbar card ke andar (search; Filter, Export, main action) — **page ka main "Add" action header me, toolbar me nahi**.
- Pager card ke **bahar** niche. Pinned columns nahi.
- **Phone pe:** rows → cards, tabs → Filter, row tap → actions bottom sheet.

### 3.8 Page header (`.top`)

Left me title + subtitle, right me actions — `container-type: inline-size` se width ke hisaab se khud adjust:

| Container width | Kya hota hai |
|---|---|
| Full | H1 28, poore buttons |
| ≤ 760 | Outline buttons **icon-only** (36×36), select chhup jata hai |
| ≤ 480 | Saare buttons icon-only 32×32, H1 **17**, subtitle 11.5 |

Actions hamesha right me rehte hai, wrap nahi hote. Title 2 line tak clamp.
Profile button = **round 36px photo**, naam tooltip me (option A, 9 Oct ko choose kiya).

### 3.9 Details list (`.dl`)

2 columns, **koi box nahi**: label upar (12/600 muted), value niche (14/700), har row ke niche 1px line (card ke andar aakhri 2 rows ki line nahi).

### 3.10 Steps aur meters

- `.steps` — 26px square (radius 6, `--sub`) + text 14/1.5. Numbered (How to) ya tick (Form cues).
- `.meter` — 3 segments 16×6 radius 3; `on` = accent. `.big` me 20×7 aur off state `#C9D8FA`.
- `.mprim` — primary muscle block: accent-soft background, 44px white icon tile, naam 18/800.

---

## 4. Overlays

### 4.1 Dropdown / filter menu

`.menu` — white, radius 12, 1px line, menu shadow, padding 6, items ke beech gap **3**, min-width 200.
`.mi` — height **34**, radius 8, 500/13.5; hover/active `--sub`; icon muted; right me `.end` (muted meta) aur `.tk` (accent tick).
**Filter options me checkbox nahi — picked option ke right me tick.** Picked item ka text 700 ho jata hai.
`.mhead` uppercase 11 muted · `.msep` 1px line · `.mi.danger` red (hover `--bad-bg`).

### 4.2 Modal

`.modal-back` fixed, scrim `rgba(23,23,23,.36)`, center.
`.modal` — **max-width 440** (confirm), `.wide` **560** (form), radius **16**, white, strong shadow.
- Header `18px 18px 6px 20px`: 36px icon tile (accent-soft; `.bad` me red), title 16.5/800, body 13/1.5 muted, right me ghost close.
- Body `10px 20px 4px`, gap 12.
- Footer `16px 20px 18px`, buttons **right me**, `.lead` se koi note left me.

### 4.3 Drawer (right side)

`.drawer` — right se slide, **max-width 520** (`.wide` 640), poori height, radius `16 0 0 16`.
Header aur footer fix, beech ka body scroll. Lambe form aur "list me se chuno" flows ke liye; **chhoti choice modal hi rehti hai**.
`.dr-sec` = sections with bottom line. `.dr-opt` = pickable row (radius 12, border `--line2`; selected = accent border + `#F7FAFF` + 3px accent-soft ring).

> **Probid ka rule:** drawer ke andar ke list (Q&A, forms, meals, plans) **plain rows** hote hai — na outer box, na radius, na selected border. Rows ke beech sirf line, aur pick sirf radio (single) ya square check (multi) se dikhta hai.

### 4.4 Bottom sheet (phone)

`.ca-back` (scrim `rgba(17,17,17,.38)`) + `.ca-sheet` — white, radius **20 20 0 0**, `max-height 82%`, padding-bottom 18.
- `.ca-grab` — 38×4 grey pill upar.
- `.ca-sh` — title 17/800 + sub 12.5 muted, right me **round 32px close** (`--sub` background).
- `.ca-sbody` scroll karta hai, `.ca-sf` footer.
- **Web board pe wahi sheet center me 520px ka modal ban jata hai** (`.ca-web .ca-sheet`) — isliye sheets ka markup `main.ca-web` ke **andar** hona chahiye, bahar rakhoge to poori width ki patti ban jati hai.

### 4.5 Toast

Dono families ka **box ek jaisa**: width **360** (`max-width: calc(100% - 24px)`), height ~**49**, radius **14**, padding `8px 10px 8px 16px`. Sirf fill alag.

| Family | Class | Fill |
|---|---|---|
| Admin / trainer | `.pg-toast` | dark `#1F1F1F`, text white, sub `#B5B5B0`, action `#93B4FF` |
| Client app | `.ca-toast` | 6 kinds (upar §1.1) |

Andar: round 32px icon circle (`currentColor` ka 14%), title 14/800, sub 12/600 (opacity .78), optional **Undo**, phir close.

**Placement dynamic hai — kabhi fixed px mat likhna.** Ek variable `--toast-b` sab decide karta hai:

| Screen pe kya hai | bottom |
|---|---|
| Koi bottom bar nahi | **20** |
| Bottom bar hai (client ke 5 tabs ya admin phone nav, dono 71) | **83** (bar + 12 gap) |
| Bottom sheet khuli hai | **20**, aur toast sheet ke **upar** float karta hai |

Sheet khulte hi uska `padding-bottom` **78** ho jata hai taaki toast uske buttons na dhake.
Duration: normal **5s**, Undo wala **10s** (Gautam, 2026-10-15; pehle 7s). Aate waqt 320 ms me fade + slide
(phone par neeche se, tablet/web par right se), jaate waqt 200 ms.

**Side (Gautam, 2026-10-15 — board se alag):** phone (< 600) par toast **beech me** (center). Tablet aur web (≥ 600)
par toast **neeche right** me, right se **24** door, width **400**. Phone par toast **poori width** ka (dono taraf 12) — boards me web toast center me hai, par app me right-bottom.
Login pages ka `dx: 60` shift sirf phone par lagta hai. Code: `ToastHost` in `app/lib/core/widgets/overlays.dart`.

### 4.6 Tooltip

App ke `AppTooltip` jaisa — **white card**, 1px `--line` border, dark text 600/12.5, radius 8, soft shadow, **arrow nahi**.
Icon buttons pe upar khulta hai, collapsed sidebar me right me.
Sirf **kata hua text** dark tooltip leta hai (`.trunc[data-full]` → `#1F1F22`, white, radius 6, max-width 340).

---

## 5. Client app components

| Cheez | Class | Spec |
|---|---|---|
| Card | `.ca-card` | white, 1px line, radius **14**, padding 14, gap 12 |
| Button | `.ca-btn` | height **44**, radius 12, 700/14.5 · `.sm` 34/radius 10/13 · variants `pri` (accent), `out` (white+line), `dark` (`#171717`), `danger` (`#E5484D`), `dis` (opacity .45) |
| Icon button | `.ca-ib` | 38×38 radius 12 · `.sm` 34 radius 10 |
| Avatar | `.ca-av` | 38px circle, `#E0E7FF` / `#3730A3` |
| Chip | `.ca-chip` | height 24, radius 7, 700/12 · `green` / `blue` variants |
| Search | `.ca-search` | height 42, radius 12, muted |
| Week strip | `.ch-week` + `.ch-d` | 7 cells; har cell me din (11/600 muted), date (15/800), aur ek 16px marker — done = green tick, rest = dashed, today = accent ring |
| Bottom tabs | `.ca-tabs` | 5 tabs, icon 22, label 11/600, active accent |
| Sheet / toast | §4.4 / §4.5 | |

Client app ka mock data poore canvas me ek jaisa: **Riya Sharma** (client), **Aman Verma** (coach), plan **Vegetarian · 1,650 kcal**, targets 1650 kcal / 120 g P / 170 g C / 52 g F.

---

## 6. States aur interaction rules

- **Har tap kuch dikhata hai** — sheet, modal, toast ya navigation. 3-dot hamesha menu kholta hai, dead button kabhi nahi.
- **Destructive cheez pe hamesha Undo** (toast me), ya confirm modal.
- **Draft vs saved:** portions jaisi cheezein sheet ke andar draft rehti hai, `Save` dabane par hi lagti hai. Badla hua ho to hi button active.
- **Empty state:** ek saaf line (jaise *"Nothing logged on Mon, 5 Oct."*), aur aage kya karein wo bhi.
- **Lambe text:** rows me ellipsis + hover pe dark tooltip. Button groups wrap karte hai.
- **Loading / disabled:** `.dis` = opacity .45 + pointer-events none.
- **Hover:** rows aur tiles pe `--hover` (soft blue), buttons pe solid fill. Grey hover kahin nahi.
- **Focus:** accent border + 3px `--accent-soft` ring.
- **Scroll:** scroll area kabhi content nahi kaat-ta; cards khali jagah bharne ke liye stretch nahi hote.

---

## 7. Do / Don't

✅ Theme tokens hi use karo — har colour `lib/core/theme` se.
✅ Radius hierarchy maano — andar wali cheez hamesha chhoti radius.
✅ Icon stroke 1.8, inline SVG.
✅ Touch target ≥ 44 (client app), ≥ 36 (web).
✅ Numbers tabular, dates chhote format me (`Fri, 9 Oct`).

❌ Coloured left-border stripe cards/rows/nav pe — **kabhi nahi**.
❌ Emoji icon ki jagah, gradient wash, fake stats ya testimonials, doosron ke brand logo.
❌ Hardcoded hex widget me.
❌ Toast ka bottom fixed px me.
❌ Sidebar me search.
❌ Table me pinned columns.
❌ Drawer ke andar boxed/card-style picker list.

---

## 8. Flutter mapping

| Canvas | Flutter |
|---|---|
| `twv.css` `:root` | `lib/core/theme/app_colors.dart` + `app_radius.dart` + `app_spacing.dart` |
| `.h1 .h2 .h3 .sub .cap .over` | `app_text_styles.dart` (ek-ek `TextStyle`) |
| `.btn.*` | `AppButton(variant: primary / dark / outline / danger / text, size: sm/md/lg)` |
| `.ibtn` | `AppIconButton(size, ghost)` |
| `.inp` / `.field` | `AppTextField` (label + hint + error + focus ring) |
| `.tabs` / `.utabs` | `AppSegmentedTabs` / `AppUnderlineTabs` |
| `.badge` / `.chip` / `.count` | `AppBadge` / `AppChip` / `AppCountPill` |
| `.card` + `.card-h` + `.card-b` | `AppCard(header:, child:)` |
| `.tbl` | `AppDataTable` (sticky header, row menu; phone pe cards) |
| `.menu` / `.mi` | `AppMenu` + `AppMenuItem` (tick, no checkbox) |
| `.modal` | `showDialog` → `AppModal(width: 440/560)` |
| `.drawer` | `showGeneralDialog` right slide → `AppDrawer(width: 520/640)` |
| `.ca-sheet` | `showModalBottomSheet(isScrollControlled: true)` → `AppSheet` |
| `.pg-toast` / `.ca-toast` | `AppToast(kind:)` — offset `bottomNavigationBar.height + 12`, sheet khuli ho to uske upar |
| `.side` + `.main` | `AppShell` (NavigationRail jaisa, par custom — 240/68, no animation) |
| `.ca-tabs` / `.mb-nav` | `AppBottomNav` (5 tabs, badge) |
| `.av` | `AppAvatar(name)` — colour naam se |

---

## 9. Screen banane se pehle ka checklist

1. `design/screens/<Name>.dc.html` kholo (phone + web dono).
2. `docs/screens/behaviour.md` me us screen ka section padho — har button kya karta hai.
3. Har field, tab, drawer, menu item aur state ki list banao — **koi khali ya dead button na bache**.
4. Mock data wahi lo jo canvas me hai (Riya / Aman / 1,650 kcal).
5. Theme tokens use karo, hex nahi.
6. Chrome + Android phone dono pe test, phir canvas ke screenshot se side-by-side milao.
7. `flutter analyze` clean + tests pass → tabhi commit.

---

*Reference: `design/screens/twv.css` (tokens aur components), `design/screens/Main.dc.html` (design system board), `docs/screens/behaviour.md` (har screen ka behaviour). Canvas: https://claude.ai/artifact/3xeZtZYPoU5NPKqyKk1Wah*