# D-29 · Client About page from gym settings; phone Home uses the hero

Date: 2026-10-16 · Asked by: Gautam ("client about banado", "homehero ye hero wala rakhna hai")

## Decision
1. **About page** (`/more/about`, boards ClientAbout / ClientAboutWeb). No board links to it, so Help & about gets
   one extra row "About Train With Vimal". Web shows it in two columns.
2. **Contact and coach words live in gym settings**, not in the app: `GymSettings` gets `tagline`, `website`,
   `whatsapp` (blank = phone), `support_hours`, `coach_role`, `coach_intro`, `coach_stats`. The public `gym/` API
   returns them with the head coach (the admin's first name and photo). Admin edits them through
   `PATCH settings/gym/`; the Settings screen for that comes with the admin boards. My account's "Gym front desk"
   uses the same support hours.
3. **App facts stay in the app**: version `1.0.0 (1)`, What's new, terms, privacy and licences text (they change
   with an app release).
4. **Rate the app** opens the Play Store page (`com.trainwithvimal.app`); on iOS it only shows the toast until the
   app is in the App Store.
5. **Home hero**: phone Home is the ClientHomeHero board (the blue hero runs under the status bar with light
   status-bar icons; the week strip overlaps it). Line under "Hey Riya" = today's workout name or "Rest day today."
   and "N of M workouts done this week." (rest days not counted). Web keeps ClientHomeWeb.
