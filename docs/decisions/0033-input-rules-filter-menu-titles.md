# D-33 · Input rules, filter side menu, tab titles

Date: 2026-10-16

## Decision
- **Every field takes only its type.** `inputRules(keyboard)` (`app/lib/core/util/input_rules.dart`) is applied
  by `AppTextField` and `CaField` from the keyboard type, so a screen only has to pick the right keyboard:
  - `TextInputType.phone` → digits only, max 10 (the `+91` is shown in front, never typed).
  - `TextInputType.number` → digits only, max 6.
  - `numberWithOptions(decimal: true)` (kg, cm) → up to 4 digits, one `.` (a typed `,` becomes `.`), 2 decimals.
  - `emailAddress` → no spaces, max 254.
  Food quantity boxes (`NumStepper`) use the same rules.
- **Checked on save:** `isMobile` (10 digits starting 6–9, `91` prefix allowed) and `isEmail`. Used in the trainer
  Edit details drawer, the client Edit profile sheet and Join. Body ranges in Edit details: weight 25–300 kg,
  height 100–250 cm. The server still validates; its field errors show under the field.
- Join's Mobile now has a `+91` prefix like the other phone fields; the app sends `+91XXXXXXXXXX`.
- Date of birth is picked with the date picker (no typing), in Edit details as in the client Edit profile.
- **Filter menu** (`showFilterMenu`, `.fm-menu` + `.dr-submenu`): one row per group with its value and `›`;
  pointing at or tapping a row opens its options beside the menu (left if there is room). Phone: sheet → sheet.
- **My clients Export and select boxes are off for now** (Gautam). The code is commented out, not deleted, and
  the `clients/export/` API stays, so it can be switched back on.
- **Browser tab title** follows the page: sidebar name of the person's role + " · Train With Vimal"
  (`app/page_title.dart`); sign-in pages have their own names. Favicon, PWA icons and manifest use the TWV logo.
