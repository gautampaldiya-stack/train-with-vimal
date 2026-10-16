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

### 2026-10-16 · Body measurements — client logs any of 12, coach picks the set
- **Pehle:** Measurements me sirf 5 fixed column (chest, waist, hips, arm, body fat) the, aur client unhe log nahi kar sakta tha; sirf seed / check-in se aate the.
- **Ab:** `Measurement.values` ek map hai: neck, chest, abdomen, waist, hips, bicep L / R, thigh L / R, calf L / R (cm) + body fat (%). Client ke liye coach ka set `ClientProfile.measure_keys` (khali = waist, hips, chest, biceps, body fat). Progress → Body tab me `Log` → *Log measurements* sheet (date chips, har measurement ka stepper, sirf badle hue save, Undo). `POST me/measurements/` usi din ki row me merge karta hai, `null` value hatati hai. Check-in ka number answer agar measurement metric hai to wahi measurement ban jata hai. Compare table aur First day vs now naye keys dikhate hain, L / R ek line me ("28.5 · 28.5 cm"). Migration purane columns ka data copy karta hai (arm → dono biceps).
- **Kyun:** Gautam ne measurement list ka screenshot bheja; decision card par "Client side now" chuna. Coach ka checkbox picker aur check-in form me measurement block trainer screens ke saath.
- **Updated:** backend checkins models / serializers / services / views / progress, migrations checkins 0003 + clients 0003, seed_demo, tests/test_client_progress.py; app progress_model / screen / pages / sheets; docs/screens/behaviour.md, architecture docs · Decision D-22

### 2026-10-16 · Progress round 2, Check-ins count, Windows dates
- **Pehle:** Windows par History khulte hi 500 (`strftime("%-I")` Windows par nahi chalta; yahi baaki session / notification texts me bhi tha). Progress / History / Photos / Compare ke tabs board jitne chaude. Progress photos me Compare neeche sticky bar me tha, "Next set due" measurements ki date se aata tha. Past check-ins me total pata nahi chalta tha aur scroll ka ishara nahi tha.
- **Ab:** `dfmt()` helper (apps/common/utils.py) har jagah, aur ek test jo `%-` wapas aane nahi deta. Web par tabs label jitne chhote (`PxTabs.fit`), Progress me Compare tabs ke saath. Progress photos: Compare + "2 of 2 selected" upar, pose tabs ke right (phone par tabs ke saath button, neeche line). "Next set due" = last photo set + 2 hafte, us hafte ka Sunday (`next_photos`). Past check-ins header me *"20 check-ins · 8 sent · 12 missed"* (`history_total`), scrollbar dikhta hai, neeche fade + *"Scroll for older · 20 of 45 shown"*.
- **Kyun:** Gautam ka feedback (screenshots, 2026-10-16).
- **Updated:** backend apps/common/utils.py, checkins/progress.py, client_page.py, scheduling/views.py, notifications/*, clients/metrics.py, habits/views.py, tests/test_dates_portable.py, test_client_checkins.py; app progress_parts / screen / pages / sheets / model, checkins_screen / model; docs/screens/behaviour.md

### 2026-10-16 · Progress — tab, History, Photos, Compare
- **Pehle:** `/progress` par holding page tha. Weight / photos ka API tha, par History, measurements, lifts ka nahi.
- **Ab:** Board jaisa Progress tab (phone + web): goal, Weight / Body / Strength, First day vs now, photos, stats, adherence; sheets Log weight (Undo, milestone), Workouts, Lift, Photo set, Add photos. Naye pages History (range, type, summary, day sheet, paging), Progress photos (do set chuno), Compare (A / B, measurements). API `GET me/progress/` (poora tab), `GET me/history/`, `POST me/photos/` data URL bhi leta hai. Demo me Riya ke measurements aur photo sets.
- **Kyun:** Gautam: "next image ka karo start" — next board ClientProgress.
- **Updated:** backend/apps/checkins/progress.py, views.py, urls.py, seed_demo.py, tests/test_client_progress.py, app/lib/features/client/progress/*, app/lib/app/router.dart, theme colors / metrics, docs/screens/behaviour.md §4.7, status.md, phases/CURRENT.md, memory/README.md · Decision D-21

### 2026-10-16 · Habits — Day / Week tabs chhote
- **Pehle:** Habits & supplements ke Day / Week tabs 34 px oonche, 13.5 px text, tabs ke beech gap nahi.
- **Ab:** Board jaisa: 32 px oonche, 13 px text, 4 px gap, track radius 8, tab radius 6 (web par har tab 110 px).
- **Kyun:** Gautam: "habit and supplement me ye tab thoda chota karo".
- **Updated:** app/lib/features/client/habits/habits_screen.dart

---

### 2026-10-16 · Log food — "Other time" in Add to
- **Pehle:** Log food har food ko kisi plan meal (Breakfast, Lunch…) me daalta tha. Meal times ke bahar khaya khana kisi meal me hi jaata tha.
- **Ab:** `Add to ▾` ke last me `Other time`. Sheet: Name (*"e.g. Evening chai"*), Time (−/+ 15 min, Now / 30 min ago / 1 h ago / 2 h ago; aaj ka, abhi se baad ka nahi), `Use this time`. Phir library, Recent, My foods ya Quick add se jo add ho woh seedha Food log me us time par jaata hai, naam ke saath, hamesha off-plan. Meal card me nahi dikhta. Header me *"Other time · 4:30 pm · off-plan"* (tap = change). Backend: `FoodLogEntry.other_time` (migration nutrition 0003), `POST me/food-log/` `{other_time, logged_at, meal_name}`.
- **Kyun:** Gautam ka idea, card par "Build it" chuna.
- **Updated:** app/lib/features/client/food/food_log_screen.dart, food_model.dart, food_sheets.dart, food_screen.dart, app/router.dart; backend/apps/nutrition (models, services, serializers, migration 0003), tests/test_client_food.py; docs/screens/behaviour.md §4.5, status.md, decisions/0020 · Decision D-20

### 2026-10-16 · Food page round 2 — photo then confirm, extras in the meal, Copy yesterday Undo
- **Pehle:** `Upload photo and mark as eaten` photo chunte hi meal mark kar deta tha, photo badal nahi sakte the. Log food se kisi meal me jo extra khaya (Apple in Breakfast) woh sirf Food log me dikhta tha, meal card me nahi. Copy yesterday ka Undo nahi tha, aur wo aaj ke already logged meal ko dobara copy kar deta tha. Log food (web) par poora page scroll hota tha; tabs poori width me khinche hue the. Rest day par Train card aadhi width leta tha. Daily answers edit karte waqt button "Send to Aman" bolta tha.
- **Ab:** Photo chunne par meal mark nahi hota: photo header me pill ke paas dikhti hai, "Photo ready" bar me Change / × hai, aur alag `Mark as eaten` button photo ke saath log karta hai. Bina photo wala option turant mark karta hai. Logged meal ke ☰ me Add / Change / Remove photo (`photo` op). Meal card me "ALSO LOGGED · OUTSIDE THE PLAN" section (+N kcal), har row tap pe details. Copy yesterday toast me Undo (`POST me/food-log/undo-copy/`), aur already logged meals copy nahi hote. Log food web: header, search, chips, tabs fixed, sirf food list apne card me scroll. Tabs chhote, fit width (phone par full). Rest day = poori width. Edit me button `Save changes`.
- **Kyun:** Gautam ka round 2 feedback (5 screenshots).
- **Updated:** app/lib/features/client/food/*, train/train_parts.dart (`TwoTabs.fit`), train/train_screen.dart, checkins/checkins_daily.dart; backend/apps/nutrition/services.py, views.py, tests/test_client_food.py; docs/screens/behaviour.md §4.5 §4.13, status.md, phases/CURRENT.md, decisions/0020 · Decision D-20

### 2026-10-15 · Food page + Log food built (meal photo, typeable numbers)
- **Pehle:** `/food` aur `/food/log` par "This page is on the way" tha. Mark as eaten ke saath photo nahi ja sakti thi; off-plan ka reason save nahi hota tha; custom food per-100 g maangta tha.
- **Ab:** Combined Food page (strip, calories, This week, Water, My plan / Food log) aur Log food page bane. `Mark as eaten ▾` dropdown: photo upload karke ya bina photo; photo card, food log aur details me dikhti hai. Web par header, strip aur tabs fixed, sirf meal cards scroll. Log food: search, Recent / My foods, + se turant log, portion sheet, Quick add, Create custom food, Off-plan + reason. Har stepper ka number tap karke type ho sakta hai, −/+ bhi rehte hai. Backend: meal photo (`MealDayState.photo`), `FoodLogEntry.reason`, custom food per serving, day view me coach / photo / week done.
- **Kyun:** Gautam: nutrition + meal plan combined page, mark as eaten dropdown with photo, web me tabs static, log food me number field.
- **Updated:** app/lib/features/client/food/* (naya), router.dart, home_parts.dart (`ChRing` colour), home_sheets.dart, colors.dart; backend/apps/nutrition/* (+ migration 0002), common/utils.py, tests/test_client_food.py; docs/screens/behaviour.md §4.5 §4.13, status.md, decisions/0020 · Decision D-20

### 2026-10-15 · Check-ins fixes (Gautam's round) + named photos + autofocus
- **Pehle:** Daily card par `Edit answers` crash karta tha jab sleep ek 5-point scale ho (purane form). Form bhej ke `Back to check-ins` par card abhi bhi "Start" dikhata tha (neeche wala page purana data rakhta tha). Weekly card ek pal "Continue check-in" dikhata, phir "Start weekly check-in" (reload draft mita deta tha). Daily form ka top bar sawalon ke saath scroll hota tha. Past check-ins ki list poore page ko lamba karti thi. Weekly "sent" card me sirf Weight / Change / scale / Photos (chip text, "How was your ener…") aate the. Photos ka sawal hamesha Front / Side / Back (3 photo) leta tha; review / sent par photo nahi dikhti thi; sheet me photo chhoti thi, khulti nahi thi. Login / forgot me cursor field me nahi hota tha.
- **Ab:** Edit answers bheje gaye jawab (`answers`) se bharta hai; purane rows ke numbers sawal ke type ke hisaab se fit hote hain (sleep hours → scale label). Check-ins aur Home outbox ka har sync suun ke reload karte hain; queued check-in aur weekly draft sab pages me ek hi hai, isliye card turant badalta hai aur blink nahi karta. Daily aur weekly form: top bar + progress fixed, sawal scroll. Past check-ins card ki height fixed (phone par screen ka 60%, web 560 px), rows andar scroll, aage ke rows wahi load hote hain. Weekly "sent" card me har sawal pura text, lamba sawal upar aur jawab neeche, aur photos chhote thumbnails. Photo sawal ke `options` = kaun si photos chahiye (jaise `Meal`, `Label`), khali ho to Front / Side / Back; har slot alag naam ka, 1–6 photos. Review aur sent card par thumbnails, sheet me photo badi (contain) aur tap par full-size viewer (swipe / arrows / zoom / Esc). Login, forgot, set password, join aur new email par main field me autofocus.
- **Kyun:** Gautam ke 9 screenshots wala feedback (2026-10-15).
- **Updated:** app/lib/features/client/checkins/*, app/lib/core/widgets/photo_viewer.dart (naya), client.dart (`CaField.autofocus`), colors, home_model.dart, auth screens; backend/apps/checkins/client_page.py, services.py, serializers.py, views.py, tests/test_client_checkins.py; docs/screens/behaviour.md §4.9, docs/decisions/0019 · Decision D-19

### 2026-10-15 · Check-ins page built
- **Pehle:** `/checkins` par "This page is on the way" tha. `me/checkins/` me missed weeks / days, on-time count, weight change, steps / water nahi the; photos sirf multipart se jaate the (offline nahi); Undo nahi tha. Built-in weekly / daily forms ke sawal board se alag the (sleep 5 option, soreness "A bit / Barely").
- **Ab:** ClientCheckin (phone) aur ClientCheckinWeb board jaise: upar 3 numbers, Daily aur Weekly cards, Past check-ins (Weekly / Daily, Missed rows, coach reply), daily form ek page par, weekly form ek sawal ek page + review, photo slots (camera / gallery), draft phone par, Undo, past check-in sheet Newer / Older ke saath. Weekly check-in har Sunday 6:00 pm due. Forms board ke sawal poochte hain (migration). Seed me Riya ke 6 weekly + 10 din ke daily check-ins.
- **Kyun:** Gautam: Habits ke baad agla screen (coordinator ne bola ek ke baad ek screens banate raho).
- **Updated:** app/lib/features/client/checkins/*, router, overlays (sheet title can change), app shell (More lit on More pages), colors, pubspec (image_picker), backend/apps/checkins/* (client_page.py, migration 0002), seed_demo, tests/test_client_checkins.py, docs/screens/status.md + behaviour.md, CURRENT.md, api-endpoints · Decision D-19

### 2026-10-15 · Habits & supplements page built
- **Pehle:** `/habits` par "This page is on the way" tha. `me/habits/` sirf ek din ka data deta tha, week grid ya start date nahi.
- **Ab:** ClientHabits (phone) aur ClientHabitsWeb board jaise: Day / Week tabs, week strip, habits (water, steps, sleep, tick), Details sheets, supplements (Take / Undo / Took it, stock, running low), Week grids. API me `week`, `starts_on`, `set_by`, supplement `group`, `taken_at`, `last_7`. Seed me supplement stock.
- **Kyun:** Gautam: next screen (Home ke "See all" yahan aate hain).
- **Updated:** app/lib/features/client/habits/*, router, colors, backend/apps/habits/views.py, seed_demo, tests, docs/screens/status.md + behaviour.md, CURRENT.md · Decision D-18

### 2026-10-15 · Train — workout options on the banner; toast above sheets
- **Pehle:** Train par chal rahe workout ke banner me sirf Continue tha. Past workout detail me "3 sets" beech me aata tha. Phone par sheet khuli ho to toast sheet ke andar neeche aata tha aur sheet khaali jagah ke saath badi ho jaati thi. Timer sheet kehta tha "Leaving this screen does not stop it".
- **Ab:** Banner / bar par `⋯`: Pause / Resume timer, Finish, Restart, Discard (confirm ke saath). "3 sets" right edge par. Sheet khuli ho to toast upar aata hai, sheet ka size nahi badalta. Timer sheet: "The timer stops when you finish the workout, or when you leave Train. Continue workout starts it again."
- **Kyun:** Gautam ke screenshots (2026-10-15).
- **Updated:** app/lib/features/client/train/*, app/lib/core/widgets/overlays.dart, app/lib/app/router.dart, docs/screens/behaviour.md + status.md · Decision D-17

### 2026-10-15 · Train — day tap, exercise pictures, logger history, Use last time, timer pause
- **Pehle:** Web par exercise guide ke peeche dark patti aati thi. Past workouts sheet me title aur tabs bhi list ke saath scroll hote the. Week strip ke din tap nahi hote the. Exercise row par hamesha dumbbell. Logger ke menu me Past workouts poore workouts dikhata tha. Pichhli values bharne ka koi ek-click tarika nahi tha. Train se bahar jaane par bhi workout timer chalta rehta tha.
- **Ab:** Guide dialog saaf (shadow bahar). Past workouts sheet ka header aur tabs fixed, sirf list scroll. Din pe tap → us din ka workout (Done / Not done / Planned) + Back to today. Video cover / YouTube thumbnail ho to wahi dikhta hai. Logger ka Past workouts sirf us exercise ka, har row par Use these sets; sets box me Use last time (Undo ke saath). Train aur logger se bahar jaate hi timer rukta hai, Continue workout par chalta hai.
- **Kyun:** Gautam ke screenshots (2026-10-15).
- **Updated:** app/lib/features/client/train/*, app/lib/app/shell/app_shell.dart, backend/apps/training/views.py + serializers.py, tests, docs/screens/behaviour.md + status.md, docs/phases/CURRENT.md, docs/architecture/api-endpoints.md · Decision D-17

### 2026-10-15 · Train tab and workout logger built; bottom nav; Android build
- **Pehle:** `/train` par "This page is on the way" tha, workout log karne ka koi screen nahi tha. API me poore workout ko ek saath save karne, "Log more sets" aur effort / note bhejne ka endpoint nahi tha. Android par `flutter run` "Could not close incremental caches" ke saath fail hota tha. Bottom nav 8 px uncha tha.
- **Ab:** ClientTrain(Web) aur ClientWorkout(Web) board jaise bane: week, Today card, coach note, blocks, exercise guide (body map ke saath), Past workouts, logger (sets, −/+, BW, warm-up, delete + Undo, hold timer, rest timer, workout timer, restart, remove / discard), Finish aur Workout done page (effort, note, Send). Har change phone par turant save hota hai aur outbox se jaata hai (offline bhi). Finish ke baad "Log more sets" wahi workout dobara kholta hai; uske baad Discard sirf naye sets hatata hai, purana workout waisa hi rehta hai. Dobara Finish par effort / note nahi mitte. Android: `kotlin.incremental=false`. Bottom nav padding Gautam wali (top 4, bottom 12).
- **Kyun:** Gautam: Home ke baad agla screen. Board ka "He usually replies" ki jagah "You will usually get a reply" (har trainer ke liye sahi).
- **Updated:** backend/apps/training/{models,serializers,services,views}.py, migrations/0002_logger_fields.py, apps/common/seed_data.py, seed_defaults.py, seed_demo.py, tests/test_client_train.py, app/lib/features/client/train/*, app/lib/app/router.dart, app/lib/app/shell/app_shell.dart, core/icons, core/theme, app/android/gradle.properties, docs/screens/status.md, docs/architecture/*, docs/phases/CURRENT.md · Decision D-16

### 2026-10-15 · Home sheets crash on web; toast on the right for tablet / web
- **Pehle:** Web / tablet par Habits ke "Add steps" aur sleep ke "Change" dabane par sheet nahi khulti thi, layout error aata tha ("RenderFlex children have non-zero flex but incoming width constraints are unbounded"). Sheet ka button web par Row me tha, jo poori width wale button ko jagah nahi deta. Toast har screen par neeche beech me aata tha (board jaisa).
- **Ab:** Home ki saari sheets (Add steps, Sleep, Notifications) ka button poori width ka (`footerStretch`), web par bhi crash nahi. Tablet aur web (≥ 600) par toast neeche **right** me, phone par beech me hi. Hot restart par aane wala `sembast_web` `JdbNotificationRevision` error sirf debug ka hai, docs me note kiya.
- **Aur:** Undo wale toast ab 10s rehte hain (pehle 7s), aate waqt smooth fade + slide. Phone par toast poori width ka, tablet/web par 400 wide. Client Home ke upar se RS profile avatar hata diya (phone aur web dono, board me tha).
- **Kyun:** Gautam ne crash bheja, aur kaha web/tablet me toast right bottom me ho; toast zyada der rahe, phone par full width, avatar kahin nahi.
- **Updated:** app/lib/core/widgets/overlays.dart, app/lib/features/client/home/home_sheets.dart, home_screen.dart, docs/screens/status.md, docs/design.md §4.5, docs/rulebooks/flutter.md, docs/memory/README.md

### 2026-10-15 · Client Home built (phone + web)
- **Pehle:** Client login ke baad `/home` par "This page is on the way" aata tha. Home API me week strip, meals list, aane wali habits, check-in ke sawal, coach ka reply aur unread count nahi the. Paani log karne se water habit nahi badhti thi.
- **Ab:** ClientHome aur ClientHomeWeb board jaise bane: week strip, workout card, water, food, habits, supplements, coach card, Coming up, saari sheets (Notifications, Log food, workout preview, Add steps, Sleep) aur toasts Undo ke saath. Web par bell ka dropdown. Har log outbox se jaata hai (offline bhi). `me/home/` me naye fields; water log ab water habit bhi update karta hai. `seed_demo` Riya ke liye supplements, session, coach reply, notifications aur "Sleep 7 hours" habit banata hai. Naya habit "Sleep 7 hours" defaults me.
- **Kyun:** Gautam: login ke baad client ka Home page se shuru karo.
- **Updated:** backend/apps/activity/dashboard.py, nutrition/services.py, common/seed_data.py, common/management/commands/seed_demo.py, tests/test_client_home.py, app/lib/features/client/home/*, core/widgets/client.dart (dark + web small button), core/widgets/overlays.dart (water toast icon), core/theme/colors.dart, core/icons/app_icons.dart, app/router.dart, docs/screens/status.md, docs/phases/*

### 2026-10-15 · Login boards — last 3 checked; text line height
- **Pehle:** ClientLogin, ClientLoginWeb, ClientWelcome Partial the. Desktop setup panel me neeche ka "Only you and your coach see your answers" card nahi tha, steps 12 px door the (board 4). Finish later sheet me buttons body me the aur web par 44 high the (board 40). All set desktop par 560 chauda tha aur button ke upar line thi. Har text board se ~10% uncha tha (Flutter font ka Windows descent jod raha tha). Approval wait wale account ke liye realtime socket baar baar refuse hota tha aur browser me error aata tha.
- **Ab:** Teeno boards Done (390, 600, 768, 900, 1024, 1280, 1440 par check). Text ka default line height 1.26 = browser ka `normal`. Question ke neeche 10 px, caption 6 px (board ke negative margins, `Pull` widget). Toast dikh raha ho to sheet neeche 78 px jagah chhodti hai (board rule). "Profile complete" toast me star. Training experience / Where will you train ke tiles board jaise (dono line 11 px grey). Realtime sirf approved account ke liye, approve hote hi connect.
- **Kyun:** Gautam: Partial boards browser me check karke poore karo.
- **Updated:** app/lib/core/theme/text.dart, core/widgets/client.dart, core/widgets/overlays.dart, core/realtime/realtime.dart, app/services.dart, features/auth/auth_frame.dart, features/auth/setup/*, docs/screens/status.md, docs/phases/*

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
