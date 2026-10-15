# Changes log — kya tha → kya hua

Jab bhi pehle ka koi decision, design ya rule badle, yahan **sabse upar** ek naya entry add karo (newest first). Saath mein jo docs, screens ya code affect hue, unhe usi commit mein update karo. Bade change ke liye `decisions/` mein detailed file bhi banao.

**Naya entry ka format (copy karo):**

```md
### 2026-10-15 · Responsive — tablet never gets the phone layout; Log out
- **Pehle:** Login / account pages 1000 px se chhoti width par phone layout dikhate the, isliye tablet aur chhoti browser window me mobile screen khulti thi. Login ke baad Log out ka koi button nahi tha.
- **Ab:** Phone layout sirf 600 se kam par. 600–899 par web layout (logo upar, page white card me). 900 se upar side panel page ke saath, window ke saath chhota-bada hota hai (360–520), chhoti height par picture chhoti. Settings (admin), My profile (trainer), My account (client) par Log out button, board ka "Log out?" confirm ke saath.
- **Kyun:** Gautam: mobile wala sirf mobile screen par; tablet aur web acche se aaye, window resize par bhi.
- **Updated:** app/lib/features/auth/auth_frame.dart, account_widgets.dart, permissions_screen.dart, app/lib/app/router.dart, docs/memory/README.md · Decision D-11

### YYYY-MM-DD · <Area> — <short title>
- **Pehle:** …
- **Ab:** …
- **Kyun:** …
- **Updated:** docs / screens / code ki list · Decision D-xx
```

---

### 2026-10-15 · Auth — whole login flow (reset, invite, login link, verify, permissions)
- **Pehle:** "Forgot password?" ek chhota modal tha; email links (`/reset/…`, `/join/…`, `/verify`) "This page is on the way" dikhate the. Reset link 1 ghanta, verify 48 ghante chalta tha. Forgot page har email ke liye same jawab deta tha.
- **Ab:** Har link ka apna page board jaisa: `/forgot` + `/reset-password?token=` (ClientResetPassword), `/join/<code>` (ClientJoinLink), `/start?token=` login link, `/verify` + `/verify-email?token=` (ClientVerifyEmail), `/permissions` (ClientPermissions). Intro slides (ClientIntro) pehli baar phone par. Health step me health conditions + heart condition par doctor’s OK zaroori. Reset link 15 minute, verify 24 ghante (board ke hisaab se). Forgot page board ki tarah "No account uses this email" dikhata hai. Invite link batata hai kyun band hua (expired / off / full). Login link par "This is not me". Web app ab real paths use karta hai.
- **Kyun:** Gautam: login ka poora flow complete karo; har button / link / email ka page bana ho.
- **Updated:** app/lib/features/auth/*, app/lib/app/router.dart, backend accounts + clients, docs/screens/status.md, docs/rulebooks/flutter.md, docs/rulebooks/local-setup.md, README.md · Decision D-15

### 2026-10-15 · Process — whole flow and board status list
- **Pehle:** Screens flow ke first pages tak bante the; reset password page (email link wala) chhut gaya aur CURRENT.md me "Reset password" likha tha, jo done jaisa lagta tha.
- **Ab:** Flow tabhi done jab uske har button / link / email se khulne wala page bhi bana ho. Har board ka status `docs/screens/status.md` me; Done sirf browser check (phone + desktop) ke baad. Jo nahi bana, uska board naam likhna zaroori.
- **Kyun:** Gautam ne testing me pakda; aisi galti dobara na ho.
- **Updated:** docs/rulebooks/definition-of-done.md, docs/screens/status.md, CLAUDE.md, docs/memory/README.md, docs/phases/CURRENT.md

### 2026-10-14 · Docs — one file per topic
- **Pehle:** decisions, rulebooks, prd, phases ek-ek README me the.
- **Ab:** Har decision ki alag file (`decisions/0001-…`), har rulebook alag (`api, backend, flutter, git, local-setup, notifications`), PRD alag-alag (roles, auth, admin, trainer, client, notifications), phases alag files, aur architecture me poori API list + data model. `design-system.md` ka naam ab `design.md`.
- **Kyun:** Gautam: docs detail me aur alag files me chahiye.
- **Updated:** docs/*, CLAUDE.md

### 2026-10-14 · Fresh start — backend built, scope reset
- **Pehle:** Purane docs me SaaS / independent coaches, payouts, branches the.
- **Ab:** Scratch se build. Sirf ek gym (Admin = Vimal, Trainer, Client). Django backend poora bana (sab modules), offline-first client logging, realtime notifications, seeds aur tests. Neeche ke purane entries sirf history hain.
- **Kyun:** Gautam ka decision (2026-10-14).
- **Updated:** prd, architecture, decisions (D-01…D-13), rules, rulebooks, phases, memory, CLAUDE.md, README

### 2026-10-02 · Git — `develop` branch
- **Pehle:** Phase branches `main` se bante the aur `main` mein merge hote the.
- **Ab:** `develop` pe roz ka kaam. Phase branches `develop` se bante hain aur `develop` mein merge hote hain. Phase poora hone pe `develop` → `main` + tag.
- **Kyun:** `main` hamesha stable rahe.
- **Updated:** rules.md, runbook.md, git-commands.md, CLAUDE.md · D-29

### 2026-10-01 · Plans — Coach plan limits
- **Pehle:** Storage 5 / 25 / 100 GB + alag video quota; Starter aur Pro mein assistant coaches.
- **Ab:** Storage 5 / 10 / 50 GB (video included). Starter & Pro: 0 trainers, 1 branch. Studio: 5 trainers, 3 branches.
- **Kyun:** Clear, simple limits.
- **Updated:** CoachPlans, CoachPricing, CoachMyPlan, PRD · D-13

### 2026-10-01 · Coach billing — 3 models
- **Pehle:** Har coach pe sirf ek platform share %.
- **Ab:** Admin har coach ke liye chunta hai: revenue share only / plan only / plan + share.
- **Kyun:** Alag-alag coaches se alag deal.
- **Updated:** IndependentCoaches, CoachPlans, CoachMyPlan, CoachAccess · D-12

### 2026-10-01 · Payouts — Admin approval
- **Pehle:** Trainer payouts sirf "Due / Paid" dikhte the.
- **Ab:** Calculated → Pending approval → Approved → Paid (UTR ke saath). Kabhi automatic nahi. Coach apne trainers ke payouts khud approve karta hai.
- **Kyun:** Paise pe control.
- **Updated:** AdminPayments, TrainerDetail, CoachTeam · D-14

### 2026-10-01 · Branches — Ek trainer, ek branch
- **Pehle:** Trainer multiple branches mein ho sakta tha (primary + shifts).
- **Ab:** Ek trainer = ek branch. Admin "Move branch" se shift kar sakta hai.
- **Kyun:** Simple ownership, payouts aur schedule clear.
- **Updated:** AdminTrainers, TrainerDetail, BranchDetail, Branches, CoachTeam · D-11 · `decisions/0011-one-trainer-one-branch.md`

### 2026-10-01 · Search — Header search
- **Pehle:** Search field sidebar ke andar tha.
- **Ab:** Page header mein search icon → command palette (Ctrl+K).
- **Kyun:** User feedback.
- **Updated:** SearchPalette (44 web screens), WebSidebarNew · D-18

### 2026-09-30 · Roles — Cleanup
- **Pehle:** "Head coach" aur "Nutritionist" roles; Meera Shah coach bhi thi.
- **Ab:** Gym mein sirf Admin / Trainer / Client. Meera Shah = trainer. Independent coach = Ishita Verma Coaching.
- **Kyun:** Ek insaan do jagah same email/mobile se nahi.
- **Updated:** Kai screens (settings, permissions, coach screens, activity log) · D-08, D-10

### 2026-09-30 · Coach — Independent workspace
- **Pehle:** Coach workspace admin ke under, 70/30 split.
- **Ab:** Independent coach alag workspace; platform share admin set karta hai.
- **Kyun:** Model clear kiya ("coach ka hissa").
- **Updated:** Coach screens · D-09, D-27

### 2026-09-30 · Design — Cards & radius
- **Pehle:** Cards pe coloured left border, har jagah same radius.
- **Ab:** Koi left border nahi; radius hierarchy (4–6px sharp tak).
- **Kyun:** Design quality.
- **Updated:** design.md, kai screens · D-19

### 2026-09-30 · Web sidebar — Naya design
- **Pehle:** Search field, neeche profile naam, active item pe left border.
- **Ab:** Pin / collapse / rail, active item filled pill, profile block nahi.
- **Kyun:** User feedback.
- **Updated:** WebSidebarNew (saari web screens) · D-18

### 2026-09-30 · Login — Register link hataya
- **Pehle:** Login pe "invite nahi hai → register" link.
- **Ab:** Register sirf invite link se.
- **Kyun:** Controlled access.
- **Updated:** Login, LoginWeb · D-06

### 2026-09-30 · Notifications — View all
- **Pehle:** Bell panel ka "View all activity" → Activity log.
- **Ab:** "View all notifications" → date-wise Notifications page.
- **Kyun:** Activity aur notifications alag cheezein hain.
- **Updated:** NotificationPanelWeb, NotificationsWeb

### 2026-09-29 · Design — Theme toggle
- **Pehle:** Theme toggle sirf sidebar badalta tha.
- **Ab:** Poori screen ka theme badalta hai.
- **Kyun:** Bug / UX.
- **Updated:** Saari screens

### 2026-09-29 · Design — Illustrations
- **Pehle:** Khud draw kiye illustrations.
- **Ab:** unDraw illustrations (recoloured).
- **Kyun:** Professional look.
- **Updated:** Illus wali screens, design.md · D-20

### 2026-09-29 · Product — Solo mode hataya
- **Pehle:** Client khud apna plan chala sakta tha (solo mode).
- **Ab:** Har client admin/trainer ya independent coach ke under.
- **Kyun:** Business model.
- **Updated:** PRD · D-04

### 2026-10-13 · Design system — Sidebar aur Toast add kiye
- **Pehle:** Design system board (canvas page `system`, `Main.dc.html`) me Colours, Type, Radius, Buttons, Inputs, Tabs, Filter/dropdown/3-dot, Badges, Breadcrumbs, Stats cards, Data table, Page header, Profile button aur Modal the. **Sidebar aur Toast miss the** — har screen pe use hote hain par kahin documented nahi the.
- **Ab:** Board pe do nayi sections hain, dono live rendered:
  - **Sidebar** — open (240) aur mini (68) dono rails, plus ek "Rules" card (admin order, trainer list, phone bottom bar, "Never" rules).
  - **Toast** — `pg-toast` (admin/trainer, 3 examples) aur `ca-toast` (client app, 6 kinds: ok / info / warn / err / del / star).
- **Kyun:** Gautam ne bola — dono design system me hone chahiye taaki Flutter me ek baar banake reuse ho.
- **Updated:** canvas `Main.dc.html` (v275, board height 4335 → 5900), `canvas.json`, `docs/design.md` (Sidebar aur Toast ka poora spec), `docs/screens/behaviour.md` (§1 aur §6.5)

### 2026-10-13 · Docs — behaviour.md (har screen, har button)
- **Pehle:** Screens ka record sirf `docs/screens/use-cases.md` me tha, jo **purane** repo boards (118 artboards, Community/Coach workspace/website wale parked screens ke saath) se bana tha. Live canvas se match nahi karta tha, aur usme "button click pe kya hota hai" nahi tha.
- **Ab:** Naya file **`docs/screens/behaviour.md`** — live canvas ke 102 boards se banaya. Har screen ka ek section: kya hai → har control ka `| Control | Click pe |` table → modals / drawers / sheets aur unke saare fields aur options → mock data. 6 areas: Shell, Admin (25), Trainer (7), Client app (12), Login/join/onboarding (7), Common patterns.
- **Kyun:** Flutter build karte waqt har screen ka behaviour ek jagah chahiye tha. Clash hone pe **behaviour.md jeetti hai**, `use-cases.md` nahi.
- **Updated:** naya `docs/screens/behaviour.md`; `use-cases.md` ko purana mark kiya (behaviour.md ke intro me)

### 2026-10-13 · Design system — Toast ka size aur radius ek jaisa
- **Pehle:** Admin/trainer toast (`.pg-toast`) 380 wide / min 320, radius 12, padding 10. Client app toast (`.ca-toast`) 366 wide (phone pe left/right 12 pe edge-to-edge), radius 8, padding 12. Do alag-alag box.
- **Ab:** Dono ka **width 360** (`max-width: calc(100% - 24px)`), **height ~49**, **radius 14**, padding `8px 10px 8px 16px`. Sirf fill alag — admin dark `#1F1F1F`, client me 6 colour kinds.
- **Kyun:** Gautam ne canvas pe comment kiya — height thodi kam, thoda zyada rounded, aur "ye wale toast ki style lo sabhi me: width, height aur radius".
- **Updated:** canvas `twv.css` + `Main.dc.html` captions (v276), `docs/design.md`, `docs/screens/behaviour.md` §6.5

### 2026-10-13 · Design system — Toast ki jagah ab dynamic
- **Pehle:** Har board apna bottom hardcode karta tha. Client phone boards 82, admin web 24, kuch phone boards 92/96. Nateeja: `ActivityMobile`, `AdminDashboardMobile`, `ClientsMobile`, `ApprovalsMobile`, `CalendarMobile`, `TrainerMoreMobile`, `AdminMoreMobile` pe toast 24 pe tha — **bottom nav ke upar chipka hua**. Aur login/welcome/join/verify/reset/permissions wale phone boards pe toast **top 40** pe aa raha tha, bottom pe nahi. Bottom sheet khulne pe toast sheet ke beech me aa jata tha.
- **Ab:** Ek variable `--toast-b` sab decide karta hai: bar nahi to **20**, bar hai to **83** (bar 71 + 12 gap), sheet khuli to wapas **20** aur sheet ke upar float. Sheet apna `padding-bottom` **78** kar leti hai taaki uske buttons na dhakein. `:root:has(.ca-tabs)` / `:has(.mb-nav)` / `:has(.ca-back)` se — ek board = ek screen, to CSS khud dekh leta hai.
- **Kyun:** Gautam: *"toast appears correct dynamically at bottom… agar bottom navbar hai to uske thoda sa uper hi… and bottom sheet ho to ache se aae."*
- **Updated:** canvas `twv.css` + `Main.dc.html` captions (v278), `docs/design.md` (placement table), `docs/screens/behaviour.md` §6.5

## 2026-10-14 · Flutter foundation done
- App entry (`main.dart`, `app/app.dart`), go_router with role redirect and one shell route.
- Shared widgets, API client, offline outbox, read cache, realtime socket, session.
- Font + logo declared in `pubspec.yaml`. Analyzer clean, web build compiles.

## 2026-10-14 · Login and setup backend
- Setup steps follow the client boards (goal, about, schedule, health, food); staff checklist filled from them (D-14).
- New goal `event` (Event prep). Migration `clients/0002`.
- "Finish setup later?" reminder choice (Tonight / Tomorrow / In 3 days / Off).
- Login: 5 wrong tries → 15 minute lock; error code `invalid_login` with `tries_left`, then `locked`.
- Errors now carry our own code (e.g. `invalid_login`, `locked`) instead of always `validation_error`.
- `user.client` in login and `auth/me/`: setup progress and coach name.
- `gym/` is public (help sheet on the login screen).

## 2026-10-14 · Login and setup screens (Flutter)
- Welcome, Log in, Need help, Reset password, Terms, Approval wait, 5 setup steps, Finish later, Checklist, All set.
- Client components in `core/widgets/client.dart`. "Keep me logged in" off keeps tokens in memory only.
- Seed: pending sign-ups (Neha, Karan) and a client with setup to do (Isha).
- `user.client.setup_later` so log in skips the setup steps after "Save & leave".
