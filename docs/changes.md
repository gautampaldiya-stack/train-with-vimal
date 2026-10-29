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

### 2026-10-29 · Phase 1 — one calculation module for every number (D-82)
- **Pehle:** Har khaana save karte waqt round hota tha (kcal poora number), phir total judta tha, isliye 10 chhoti cheezon me total 4-5 kcal kam aata. Admin food diary me day total kat jaata tha (1799.6 → 1799). Volume ke teen alag formule the. Records me sirf sabse bhaari set.
- **Ab:** `backend/apps/common/calc.py` me saare formule (volume, duration, rest, records + Epley 1RM, nutrition total, 4/4/9 kcal check), har formula comment me. Food log bina round kiye save (3 decimal), sirf dikhate waqt round. Client app aur admin ka number same (Vikram: 1701 = 1701, 4778 kg = 4778 kg).
- **Kyun:** Probid ka batch 1, Phase 1: "numbers accurate chahiye".
- **Updated:** backend/apps/common/calc.py, nutrition/models.py + migration 0008, nutrition/services.py, serializers.py, views.py, training/services.py, models.py, serializers.py, views.py, clients/logs.py, account.py, checkins/progress.py, tests/test_calc.py, docs/architecture/data-model.md, docs/screenshots/batch1/phase1 · Decision D-82
- **Phone app (part 2):** Food page ring, macros aur meal card ab server ka total dikhate hain (unrounded se bana), phone par khaana log/undo karne par sirf badla hua hissa upar se jodta hai. Pehle phone khud rounded rows jodta tha (3 × 41 = 123, server 122). Workout volume ka ek hi rule (`setVolume`, server ke `calc.set_volume` jaisa). Tests: app/test/food_totals_test.dart (4 pass).

### 2026-10-29 · Tests — coach missed-workout test no longer fails on some days
- **Pehle:** `test_missed_workout_and_plan_end` kehta tha "admin ko koi missed-workout notice nahi". Par admin khud kuch demo clients ka trainer hai (D-57), to jis din unka workout miss hota, admin ko sahi notice milta aur test fail ho jaata (Deploy develop ruk gaya).
- **Ab:** test sirf Riya (Aman ki client) ke liye check karta hai ki admin ko notice nahi gaya. App ka code nahi badla.
- **Updated:** backend/tests/test_coach_notices.py

### 2026-10-29 · Plan save with a new exercise; exercise picker search (D-81)
- **Pehle:** Client ke plan me naya exercise add karke Save karne par "Could not save the plan" aata tha (naye exercise ki id null jaati thi, server mana karta tha). Add exercise drawer ek baar me 200 exercises maangta tha (server 100 hi deta tha, baaki kabhi nahi dikhte) aur search sirf browser me hota tha.
- **Ab:** Null id = naya exercise, plan save hota hai, purane rows ki id wahi rehti hai. Drawer 50-50 karke laata hai (scroll par aur), search server par typing rukne ke 400 ms baad, muscle tabs bhi server par.
- **Kyun:** Probid (29 Oct) ka screenshot + "ek ek caracter pe search na ho".
- **Updated:** backend/apps/training/serializers.py, tests/test_plan_save_d81.py, app/lib/features/trainer/client_profile/cp_plans_edit.dart · Decision D-81

### 2026-10-28 · Push icon = TWV logo; README daily commands (D-80)
- **Pehle:** Notification me safed ghanti (ya grey square) dikhti thi. README me roz ke local commands ek jagah nahi the.
- **Ab:** Status bar me TWV logo (safed), notification me logo blue. README me "Daily local commands": pull, API / Celery, app Chrome + phone, push_test, push se pehle checks.
- **Kyun:** Probid: "icon nahi aata", "readme me sare commands likh do". Push moto g54 aur web par chal gaya (asli server key + `requests`).
- **Updated:** app/android/app/src/main/res/drawable-*/ic_stat_notify.png, values/colors.xml, AndroidManifest.xml, README.md, docs/decisions/0080 · Decision D-80

### 2026-10-28 · Push notifications reach the phone (D-80); working set back to develop
- **Pehle:** Phone / browser par push nahi aata tha. App har start par token bhejta tha, server dusri baar 400 deta tha, isliye token pehle login wale account par atak jata. FCM ki kisi bhi INVALID_ARGUMENT galti par token delete ho jata. Server Android channel `default` maangta tha jo app me hai hi nahi. Ek device ki galti par baaki devices ko push nahi jata. Approval ka wait karne wale account aur "Allow notifications" ke baad device save nahi hota tha.
- **Ab:** Token hamesha login wale account ke paas (204). Sirf mara hua token hatta hai. Har device ko try. Push har login par start, waiting account par bhi, aur Allow ke turant baad. FCM project key file se bhi milta hai. `manage.py push_test <email>` se seedha test. Android status bar me safed ghanti. FlutterFire ki file par saaf warning. `requests` package add kiya (iske bina server FCM token le hi nahi sakta tha). Galat server key (google-services.json ki copy) par saaf error.
- **Kyun:** Probid: "mere notification aane chaiye", ek-ek kaam ache se. Pehle `working` ko `develop` (4ccacdd) par wapas kiya (Probid ka kehna); purana working backup bundle me.
- **Updated:** backend/requirements.txt, backend/apps/notifications/serializers.py, providers.py, tasks.py, apps/common/management/commands/push_test.py, tests/test_push_d80.py, app/lib/core/push/push.dart, sw_routes_*.dart, app/lib/app/services.dart, permissions_screen.dart, app/web/firebase-messaging-sw.js, app/tool/firebase_web.dart, AndroidManifest.xml, drawable/ic_stat_notify.xml, deploy/nginx.conf, README.md · Decision D-80

### 2026-10-24 · Trainer invite-link access; access notice says what changed
- **Pehle:** Access save par trainer ko sirf "Your access was updated" jata tha (kya badla, nahi likha). Trainer app me Invite link ka button nahi tha, aur invite link ke liye koi access switch nahi tha.
- **Ab:** Access → Clients me do naye switch: **Invite with his link** (on; off karte hi uske banaye/uske naam ke links band, join page "turned off" dikhata hai) aur **Make new invite links** (on; sirf apne liye). Trainer ke My clients header me `Invite link` (switch on ho to). Trainer link sirf apne naam se banata hai, dusre trainer pe nahi bhej sakta. Notice: "Vimal changed your access" + badle hue switch ("Approve sign-ups: on"); kuch na badle to notice nahi. Trainer ka app notice aate hi apna access dobara padhta hai.
- **Kyun:** Gautam: approve wala on kiya to Aman ko pata nahi chala; trainer apne link se invite kar sake ya nahi, aur naya link sirf apne liye bana sake.
- **Updated:** backend/apps/trainers/permissions_catalog.py, trainers/views.py, clients/models.py, clients/views.py, clients/serializers.py, tests/test_invite_access.py, app invite_links_modal.dart, clients_screen.dart, me_tabs.dart, services.dart, docs/screens/behaviour.md, docs/architecture/api-endpoints.md

### 2026-10-24 · Notifications everywhere, live toast fix, admin My profile, email links
- **Pehle:** Live site par toast / live bell 15 min baad band ho jaate the (socket purane token se reconnect karta tha). Trainer ko personal best, goal weight, chhoda workout, plan khatam hone ki khabar nahi milti thi. Client ko plan update / khatam / habit hatane par kuch nahi aata tha. Admin ko trainer join ya client delete request nahi dikhti thi. Reset password email me `localhost:5173` link. Admin ka apna profile page nahi tha.
- **Ab:** Ye sab notifications (D-60). Socket har reconnect par naya token leta hai. Prod me `FRONTEND_URL` default live site. Admin `/me` (My profile) sidebar, account menu aur More se.
- **Kyun:** Probid (2026-10-24).
- **Updated:** app realtime / api_client / services / router / nav_items / me, admin dashboard + More · backend notifications staff / services / reminders, training, nutrition, habits, checkins, accounts, settings · tests/test_coach_notices.py · Decision D-60

### 2026-10-24 · Check-ins — daily check-in rings the coach's bell
- **Pehle:** Client daily check-in bhejta to trainer ko koi notification nahi jaata tha (sirf ek socket event, jise app use nahi karta). Client Undo kare to bhi kuch hatana nahi padta tha.
- **Ab:** Daily check-in par sirf assigned trainer ke bell me row aati hai ("Riya Sharma sent their daily check-in" + weight / sleep / energy), aur app khula ho to toast. Push / email nahi jaata, admin ko nahi jaata. Ye Me → Notifications → New check-in switch ke hisaab se chalta hai. Client Undo kare to wo row hat jaati hai. Review par client ko notification pehle jaisa sirf tab jaata hai jab reply likha ho ("Coach Aman Verma replied").
- **Kyun:** Probid (2026-10-24): "daily checkin submit karta hai to trainer ke pass notification nahi jata".
- **Updated:** backend/apps/checkins/services.py, views.py, tests/test_client_checkins.py · docs/changes.md

### 2026-10-24 · Deploy — nginx finds a new api container by itself, 502 steps in README
- **Pehle:** nginx (`web`) api ka address sirf start par dhoondhta tha. `.env` badal ke `up -d` chalane par naya api container banta tha aur site 502 deti thi, jab tak `restart web` na karo.
- **Ab:** `deploy/nginx.conf` Docker DNS (`resolver 127.0.0.11 valid=10s`) se api ka address har 10 s me dobara leta hai. `deploy/README.md` me "Site shows 502" steps likhe hain, aur root README me ek line.
- **Kyun:** Probid ko 2026-10-24 ko phir 502 aaya ("ye esa readme.md me likh do").
- **Updated:** deploy/nginx.conf, deploy/README.md, README.md

### 2026-10-24 · Notifications page for admin and trainer
- **Pehle:** Admin / trainer ke paas sirf bell dropdown tha (latest 8). Purane notifications dekhne ki koi jagah nahi thi, aur dropdown se kholne par row read nahi hoti thi.
- **Ab:** `/notifications` page: All / Unread tabs, din ke hisaab se rows, tap se page khulta hai aur read hota hai, ⋯ me Open / Mark as read-unread / Delete (Undo ke saath), Mark all read (Undo), Show more, naya notification live upar aata hai. Bell dropdown me "See all notifications", More me Notifications row. API: `notifications/unread/` ab `total` bhi deta hai, rows me `actor_color`.
- **Kyun:** Probid (2026-10-24): "sare notifications dekhne ka page bhi banana hai".
- **Updated:** app/lib/features/trainer/notifications/notifications_screen.dart, app/router.dart, trainer dashboard_parts.dart, admin + trainer More · backend notifications serializers / services / views, tests/test_notifications_page.py · docs/architecture/api-endpoints.md, screens/behaviour.md, screens/status.md · Decision D-59

### 2026-10-24 · Invite link — twv.prowavetech.in domain
- **Pehle:** Invite link `trainwithvimal.app/join/...` dikhata tha. Woh domain hai hi nahi, isliye link khulta nahi tha.
- **Ab:** Link `FRONTEND_URL` se banta hai (`https://twv.prowavetech.in/join/...`). `INVITE_BASE_URL` sirf tab chahiye jab alag domain ho. App me preview / join page bhi wahi host dikhate hain.
- **Kyun:** Probid (2026-10-24): "ye link hai, sahi karo sab jagah".
- **Updated:** backend/config/settings/base.py, clients/models.py, app auth/account_widgets.dart, join_screen.dart, admin invite_links_modal.dart, docs/architecture/data-model.md, docs/screens/behaviour.md

### 2026-10-24 · Deploy — web restart after a new api container
- **Pehle:** D-58 ke deploy me nginx (`web`) purane api container ka address yaad rakhe raha, isliye health check 502 par fail hua. Code aur migration theek chal gaye the.
- **Ab:** Deploy `up -d --build` ke baad `restart web` bhi karta hai, taaki nginx naye api ko dhoondh le.
- **Kyun:** Deploy run 7 (2026-10-24) fail hua tha. Server par haath se ek baar `restart web` chalana pada.
- **Updated:** .github/workflows/deploy-develop.yml · docs/changes.md

### 2026-10-24 · Notifications — toast, bell count, Settings Log out, demo data on live
- **Pehle:** Naya notification sirf bell panel me dikhta tha, bell par sirf red dot (board jaisa). Admin Settings me Log out nahi tha. Live par `seed_demo` fail hota (createsuperuser wala admin hai, doosra admin nahi ban sakta).
- **Ab:** App khula ho to har naye notification ka toast (Open se uska page). Har bell par unread count (9+ tak). Admin Settings me Log out. `seed_demo` live admin ko hi "Vimal" maan ke demo trainers / clients bana deta hai, admin ka login nahi badalta.
- **Kyun:** Probid (2026-10-24).
- **Updated:** app/lib/app/unread.dart, app.dart, core/widgets/badge.dart, button.dart, admin dashboard, admin settings, trainer dashboard, client home / more · backend seed_demo, tests/test_seed_demo.py · Decision D-58

### 2026-10-24 · Firebase on the PC — file table, FlutterFire clean-up
- **Pehle:** README me Firebase steps the, par kaun si file kahan jaati hai ek jagah nahi tha. `flutterfire configure` chalane par apna `app/firebase.json` ban jaata hai jo D-56 wali key file ko replace karta hai, aur push chupchap band rehta hai.
- **Ab:** README "Push notifications on your PC" me files ki table aur FlutterFire clean-up ke steps.
- **Kyun:** Probid ne pehle PC par terminal se FlutterFire jaise commands chalaye the; ab D-56 wala ek hi tarika.
- **Updated:** README.md · docs/changes.md

### 2026-10-24 · Admin trainer profile — admin hamesha trainer bhi
- **Pehle:** Admin ka TrainerProfile sirf `seed_demo` me Vimal ke liye banta tha. Admin khud ko trainer ke roop me invite link / clients me use nahi kar sakta tha.
- **Ab:** Har admin ka trainer profile (is_owner=True) apne aap banta hai (post_save signal + migration `trainers/0003`). Invite link me admin khud ko ya kisi trainer ko chun sakta hai. Link trainer nahi chuna to admin ke naam se banta hai.
- **Kyun:** Probid ne kaha admin bhi trainer ho sakta hai, jaise demo me Vimal hai. Live admin `createsuperuser` se bana tha, uska profile nahi tha, isliye invite modal me trainer list khali aur Create link band tha.
- **Updated:** backend/apps/trainers (services, signals, apps, migration 0003) · backend/apps/common seed_demo · backend/tests/test_invite_links.py · docs/changes.md · docs/phases/CURRENT.md · docs/memory · Decision D-57

### 2026-10-23 · Push notifications (Firebase) in the app + handoff
- **Pehle:** Server push bhej sakta tha, par app phone / browser ko register hi nahi karta tha, isliye push kabhi nahi aata. Firebase keys kahan daalni hai, tay nahi tha. HANDOFF.md 18 Oct ka tha.
- **Ab:** Login ke baad app permission maangta hai aur device ko `devices/` me save karta hai. Log out par device hat jaata hai. Push tap karne par sahi page khulta hai. Web push service worker se aata hai. Saari app keys ek file `app/firebase.json` me (git me nahi), server key `secrets/` me. Live site ke liye GitHub secret `FIREBASE_JSON`. iPhone baad me (Apple account). HANDOFF.md naye account ke liye poora update hua (live server, deploy, push, parked list, branch rule).
- **Kyun:** Gautam: "mere local me bhi set kar do... notification and all", "ye copy ki hui kaha daalni hai", "handoff update kar dena... dusre account se continue karunga".
- **Updated:** app (pubspec firebase_core + firebase_messaging, lib/core/push/push.dart, lib/app/services.dart, lib/main.dart, web/firebase-messaging-sw.js, tool/firebase_web.dart, firebase.example.json), .gitignore, backend/.env.example, .github/workflows/deploy-develop.yml, README.md, deploy/README.md, docs/HANDOFF.md · Decision D-56

### 2026-10-23 · From address, package hide, icon + splash, deploy
- **Pehle:** Integrations me sirf domain tha, emails hamesha hello@domain se. Automations / Emails me Package trigger, Who → Package, Renewal reminder aur Packages tab the (par client ka package set karne ki jagah hi nahi thi). App icon / splash Flutter default. Server deploy ka koi setup nahi tha.
- **Ab:** Integrations → Email sending me "From address" (jaise coach@domain). Package har jagah hidden (code me comment, wapas la sakte hai). Gautam ke logo se app icon + splash (Android, iOS, web). Ek hi domain twv.prowavetech.in: CloudPanel reverse proxy → Docker nginx → app + API, sab Docker me. develop par push = auto test + deploy (GitHub Actions). App id ab `com.trainwithvimal.app` (Firebase apps jaisa). Server folder `~/twv` (root = `/root/twv`, workflow me likha hai) deploy khud banata hai. Detailed steps (SSH key, GitHub secrets, .env, Firebase file `secrets/` me) deploy/README.md me; app me push ka code Firebase project banne ke baad.
- **Kyun:** Gautam ka 23 Oct message (logos ke saath) aur "api ke liye dusri website banane ki jarurat nahi... docker use karo".
- **Updated:** backend apps/gym (serializers.py, integrations.py, models.py), apps/automations (models.py, views.py, engine.py), apps/notifications (views.py, defaults.py, migration 0006), config (settings/base.py SERVE_MEDIA, urls.py), Dockerfile, .dockerignore, tests; app settings_access.dart, automations_common.dart, automation_builder_screen.dart, emails_common.dart, assets/brand, pubspec.yaml, android / ios / web icons + splash, app id (build.gradle.kts, MainActivity.kt, project.pbxproj, about_screen.dart); docker-compose.prod.yml, deploy/ (nginx.conf, env.example, README.md), .github/workflows/deploy-develop.yml, .gitignore; docs · Decision D-55

### 2026-10-23 · Gautam ka feedback — trainer access, settings, tables, tooltips
- **Pehle:** Trainer ka "What clients see" aur access save karne par "Method PUT not allowed" aata tha. Automations aur Assign clients sirf admin. Settings me ek hi "Website / Instagram" field, Timezone / App language, Apple Health card aur Daily digest card dikhte the. Duplicate bina puche copy bana deta tha. Clients table ke header kat rahe the ("NEXT CHECK-", "ACTIO", "ADHERENC"), status pill 3.8 px bahar. Kuch cut text par tooltip nahi tha. New template modal ke tabs poore stretch, buttons bade. Automations list congested, chips 2.9 px overflow, builder ka teesra column kat raha tha. "Assigned to" lists poori lambi.
- **Ab:** PUT theek. Admin kisi ek trainer ko "Create and edit automations" aur "Assign and reassign clients" de sakta hai (Access → Custom). Settings: Website, Instagram, YouTube, Facebook; Timezone, App language, Apple Health card, Daily digest card abhi hidden (code me comment). Har Duplicate pehle confirm puchta hai. Table columns header jitne chaude, header kabhi nahi kat-ta. Har cut text par tooltip. Template modal: chhote fit tabs, chhote buttons, neeche jagah. Automations list compact (Clients column = running + finished), chips overflow nahi, trigger grid sahi columns. Assigned to / Clients on this plan / Used in lists 5 ke baad card ke andar scroll. Phone par app ka naam ab "Train With Vimal" (pehle "twv").
- **Kyun:** Gautam ke 8 screenshots wala message (23 Oct).
- **Updated:** backend apps/trainers (views.py, permissions_catalog.py), apps/accounts/serializers.py, apps/clients/views.py, apps/automations/views.py, apps/notifications/views.py, apps/gym (models.py, migration 0004, serializers.py, views.py, integrations.py), tests/test_trainer_access_extra.py; app core/widgets (overlays.dart confirmDuplicate, table_head.dart, scroll_after.dart), app shell / router / services, android AndroidManifest + ios Info.plist (app name), admin settings, emails, automations, trainers, clients, library pages; docs · Decision D-54

### 2026-10-22 · Admin Settings (built)
- **Pehle:** `/settings` holding page tha (sirf Log out). Regional defaults (units, week start) ka koi setting nahi tha. Branding sirf API me tha, page nahi. Roles matrix me client column aur kuch trainer cells kuch karte nahi the. Integrations sirf state save karte the: WhatsApp disconnect hone par bhi WhatsApp jaata, email domain ka DNS check nahi hota tha.
- **Ab:** `/settings` chaar tabs. General: Gym profile (Save changes, Last saved), Regional & defaults (Units + Undo, Week starts on, Timezone, App language) jo naye client ko milte hain, "Where these details show" links. Branding: logo upload / remove (512 x 512+), 8 colours + hex, theme, draft → Apply / Reset, client app preview. Roles & access: asli trainer / client counts, matrix me sirf woh trainer cells badalte hain jo app sach me maanta hai; baaki locked (tooltip ke saath). Integrations: WhatsApp off = WhatsApp messages skip; email domain ka SPF / DKIM / DMARC check (har ghante bhi), verify hone par emails hello@domain se; Health data types save; Disconnect confirm + Undo. Client app me brand colour / dark theme abhi nahi lagta (Gautam se pucha).
- **Kyun:** Gautam: "jesa pehle tumne kaha vesa karte hai ok... ab banao..sab ache se" (order ka last page: Settings).
- **Updated:** backend apps/gym (models.py, migration 0003, serializers.py, views.py, integrations.py, signals.py, tasks.py, apps.py), apps/notifications (providers.py, tasks.py), apps/accounts/emails.py, config/settings/base.py, tests/test_settings_page.py, app/lib/features/admin/settings/ (new), app/lib/app/router.dart, app/lib/core (icons, colors), docs · Decision D-53

### 2026-10-22 · Admin Emails & alerts (built)
- **Pehle:** `/emails` holding page tha. Built-in messages ke words board se alag the; Trainer invite Access me tha. Team alerts ke switch kahin use nahi hote the (alert sirf trainer ko, fixed channels). Daily digest setting nahi thi. Invite ka WhatsApp text bheja nahi jata tha, `{{date}}` aaj ki date deta tha.
- **Ab:** `/emails` teen tabs. Client messages: board order list (Team group bhi), channel dots, editor (channel tabs, Send by switch, subject / title + message counters, variable cursor par, Reset to default / Delete template + Undo, Saved / Not saved yet, Save), preview (email, push, WhatsApp, in-app), Where it is used (automations ke steps, app ke messages ka note), New template modal + Undo. Team alerts: checkboxes + Enable all asli channels decide karte hain (owner + client ka trainer), Quiet hours, Daily digest (Off / Daily / Weekly, 8 am email; shuru me Off, Gautam ke decision tak). Sender: naam, reply-to, WhatsApp number + Clients see. Phone par list → editor `‹ Messages`.
- **Kyun:** Gautam: "jesa pehle tumne kaha vesa karte hai ok... ab banao..sab ache se" (order: Forms, Automations, phir Emails & alerts, phir Settings).
- **Updated:** backend apps/notifications (defaults.py, models.py, migration 0004, serializers.py, views.py, staff.py, reminders.py), apps/accounts/emails.py, apps/checkins/services.py, apps/clients (services.py, views.py), apps/training/services.py, apps/nutrition/services.py, config/settings/base.py, seed_demo.py, tests/test_emails_alerts.py, app/lib/features/admin/emails/ (new), app/lib/app/router.dart, app/lib/core/theme (colors, metrics, text), docs · Decision D-52

### 2026-10-22 · Admin Automations and Automation builder (built)
- **Pehle:** `/automations` holding page tha. Backend me automations the par koi page nahi; trigger aur step ki lines board se alag thi ("Every Sunday at 09:00", "Send the message '…'"). Plan ends / Package ending ka time nahi tha. Text box me error aate-jaate typing ka focus chala jaata tha.
- **Ab:** `/automations`: 4 counts, har automation ki row (On / Off switch + toast + Undo, trigger, kis ke liye, step chips + "+N more", Running, Finished, Changed, ⋯ Edit / Duplicate / Delete + Undo), sender note, New automation modal (7 starters + Start blank). `/automations/new` aur `/automations/<id>` builder: naam, 15 triggers (All / Client / Schedule / Activity / Progress), trigger settings + "Starts:" line, Package / Trainer, Stop when the client responds, steps (Wait, Send message + preview, Send form, Assign task; ⋯ Move up / down / Remove + Undo; Add a step menu), In plain words + Not ready list, Last 30 days. Save as draft / Turn on / Save and keep on; tab tak kuch save nahi hota. Demo me board ke 5 automations.
- **Kyun:** Gautam: "jesa pehle tumne kaha vesa karte hai ok... ab banao..sab ache se" (order: Forms, phir Automations, Emails & alerts, Settings).
- **Updated:** backend apps/automations (views.py, starters.py, engine.py), seed_demo.py, tests/test_automations_builder.py, app/lib/features/admin/automations/ (new), app/lib/app/router.dart, app/lib/core/widgets/input.dart, docs · Decision D-51

### 2026-10-22 · Admin Forms & check-ins and Form builder (built)
- **Pehle:** Admin ke `Forms & check-ins` aur form builder holding page the. Builder me har change seedha clients tak jata; "Move back to draft" karne se weekly check-in hi band ho jata (app sirf published form leta hai). Onboarding form me board ke purane 15 sawal the.
- **Ab:** `/forms`: asli forms (New client questionnaire ke 57 naye sawal jo app sign-up par poochta hai, PAR-Q bhi), search, Form type dropdown, All / Archived, kaise bheja jata hai, status, ⋯ (Edit questions, Preview, Duplicate, Archive / Restore, Delete + Undo), Create form modal. `/forms/<id>` builder: Add question (9 type), editor, drag / Move up / down, Duplicate, Delete + Undo, Preview (bhar ke dekh sakte), Form details (naam, type, kaise bheja jata), Answers so far. Published form ka change draft me rehta hai jab tak Publish na karo; clients ko purana version milta rehta hai. Profile field bharne wale onboarding sawal ka sirf text / help / Required badalta hai.
- **Kyun:** Gautam: "jesa pehle tumne kaha vesa karte hai ok... ab banao..sab ache se"; onboarding ke naye sawal hi dikhane hain.
- **Updated:** backend apps/checkins (library.py new, views.py, serializers.py, models.py, migration 0007), tests/test_forms_library.py, app/lib/features/admin/forms/ (new), app/lib/app/router.dart, app_icons.dart, colors.dart, app/lib/features/auth/auth_frame.dart (login stats wrap at 900), docs · Decision D-50

### 2026-10-22 · Client fills forms the coach sends (built)
- **Pehle:** Coach ka bheja form (Monthly feedback, Liability waiver, PAR-Q, apna form) client ke app me kahin nahi dikhta tha aur bharne ka page nahi tha. Notification `/checkins` par le jaati thi. Bhara hua form dobara bheja ja sakta tha, aur Undo ke baad form "bhara hua" hi rehta tha.
- **Ab:** Check-ins par har form ka card (To fill, sawal kitne aur kitna time, chips, draft bar + Continue form; bhara hua 14 din tak green Sent). Form page `/checkins/forms/<id>`: ek page ek sawal, har type, review + Edit, Send to Aman (offline bhi), sent card, Undo (form wapas To fill). Notification seedha form kholti hai. Naya endpoint `me/forms/<id>/`, `me/checkins/` me `forms`. Design example Monthly feedback; PAR-Q onboarding me nahi, Forms ka form hi rahega.
- **Kyun:** Gautam ne design approve kiya ("ab banao.. sab ache se"); PAR-Q par: "forms and checkins wale me add rakho".
- **Updated:** backend apps/checkins (client_page.py, views.py, urls.py, services.py, client_forms.py, defaults.py), tests/test_client_form_page.py, app/lib/features/client/checkins (checkins_form.dart new, checkins_screen.dart, checkins_model.dart, checkins_parts.dart), app/lib/app/router.dart (third route level), design/screens/ClientForm*.dc.html, docs · Decision D-49

### 2026-10-22 · Notification links fixed, admin Check-ins, client form design
- **Pehle:** Kuch notifications app me na bane page kholte the: session reminder `/sessions/<id>`, trainer ka meal plan `/meal-plans/<id>`, coach ka bheja form `/forms/<id>`. Admin dashboard ka "Check-ins to review" holding page kholta tha. Client ke paas coach ka bheja form (jaise PAR-Q) bharne ka koi page nahi tha, aur canvas me iska board bhi nahi tha.
- **Ab:** Session notifications `/train` kholti hain, meal plan `/nutrition/<id>`, form ki notification abhi `/checkins` (form page banne par form par jayegi). Admin ke liye `/checkins` aur `/checkins/<id>` trainer wala Check-ins page kholte hain, sab clients ke saath. Naye boards ClientForm / ClientFormWeb (canvas me Client page, Check-ins row ke right): Check-ins par coach ke form ka card (To fill / Continue form / Sent), ek-ek question wala form (yes/no, ek option, kai options, number, scale, short, long), Check your answers, Send to Aman. Design Gautam ke approval par hai, code abhi nahi bana.
- **Kyun:** Gautam: "iske alava kahi kuch baki hai?" par mile gaps; form page ke liye "artifact banao.. us page pehle".
- **Updated:** backend apps/scheduling/views.py, apps/notifications/reminders.py, apps/nutrition/services.py, apps/checkins/client_forms.py + services.py, app/lib/app/router.dart, trainer/client_profile/cp_plans_assign.dart, design/screens/ClientForm.dc.html + ClientFormWeb.dc.html, docs/screens/status.md, docs/phases/CURRENT.md · Decision D-49 (aage, form page ke saath)

### 2026-10-22 · Admin Trainers, Trainer profile, Calendar and Activity log built
- **Pehle:** Admin ke `/trainers`, `/trainers/<id>`, `/calendar` aur `/activity` par holding page tha. Dashboard stat tiles par tooltip aata tha. Approvals me ek row overflow karti thi aur Review button ka text kat jata tha.
- **Ab:** Trainers page (stats, tabs, search, Filter, table / phone list, row ⋯, Add trainer, Deactivate, Move clients, Assign clients). Trainer profile (My profile tabs ka admin mode + Clients aur Access tabs, ⋯ menu me password reset, Move all clients, Deactivate). Team Calendar (All trainers pick, Busiest trainer, block par trainer ka naam, New session me Client + Trainer, Availability har trainer ki). Activity log (search, Who / Person filter, range, kind chips, day groups, Show more, Export CSV). Backend: `activity/?search=`, `trainers/summary/` me `adherence_change`, trainer GET me `access_presets`, notification routes `?tab=` form me; trainer ke apne routes par list ke filters nahi lagte (Clients tab search pehle 404 deta tha). Dashboard tiles ka tooltip hataya, Approvals overflow aur Review button fix.
- **Kyun:** Gautam (22 Oct): "ab aage trainer, calender and activity logs... banado... unme ache se check kar dena", saath me tooltip / Approvals fixes.
- **Updated:** app/lib/features/admin/trainers/*, admin/activity/activity_screen.dart, trainer/me/*, trainer/calendar/*, admin/approvals, admin/dashboard, core (icons, colours, StatCard hug), app/router.dart, backend apps/trainers, apps/activity, apps/notifications, tests/test_admin_team.py, docs · Decision D-48

### 2026-10-22 · Admin Clients and Approvals built
- **Pehle:** Admin ke `/clients`, `/clients/<id>` aur `/approvals` par holding page tha. Dashboard ke buttons (Approvals, Clients, Add client) kuch kaam ka nahi kholte the. Approvals tab filter detail actions (move back) par bhi lagta tha, isliye move back 404 deta tha.
- **Ab:** Clients page (sab clients, Trainer + Joined column, Trainer filter, Invite link, Add client drawer, row menu me Change trainer / Pause / Delete + Undo). Client profile admin ke liye (Change trainer, Edit details me password set karna ya reset link bhejna). Invite links modal (QR, copy, WhatsApp, email, download QR, naya link, sab links). Approvals page (Waiting + History, search, filter chips, Review drawer, Reject / Ask for info / Move back modals, phone par ek line per person). Naye endpoints: `clients/<id>/trainers/`, `clients/<id>/send-reset/`, `clients/check-phone/`; change-trainer me note, fresh start, old trainer ko notice; `trainer_since` field; `approvals/counts/` me `oldest_hours`. Sidebar Approvals badge app khulte hi.
- **Kyun:** Gautam (22 Oct): "ab aage wala clients and approvals ka kar... sahi se karna".
- **Updated:** backend/apps/clients (models, migration 0007, serializers, views, services, onboarding), backend/tests/test_admin_clients.py, app/lib/features/admin/clients/*, app/lib/features/admin/approvals/*, app/lib/features/trainer/clients/*, app/lib/features/trainer/client_profile/cp_model.dart, cp_overview.dart, cp_screen.dart, app/lib/app/router.dart, app/lib/app/shell/app_shell.dart, core/widgets (button text danger, drawer leading, pager empty text), docs · Decision D-47

### 2026-10-22 · Admin dashboard — no search icon in the header
- **Pehle:** Dashboard header me search icon tha jo "Search clients" modal kholta tha.
- **Ab:** Search icon hata diya. Header me Notifications, Add client aur profile (V) menu.
- **Kyun:** Gautam (22 Oct): "dashboard me se search ka icon hata do header se".
- **Updated:** app/lib/features/admin/dashboard/admin_dashboard_screen.dart, admin_dashboard_model.dart, docs/screens/behaviour.md

### 2026-10-22 · Admin dashboard — no overflow, Needs action scrolls, import activity wording
- **Pehle:** Gautam ki machine par stat cards me "BOTTOM OVERFLOWED BY 4.0 PIXELS" aur Trainer performance table me overflow stripes aate the (fixed 80 px height, fixed 90 px bar). Needs action me 5 rows ke baad `Show all` aur har row pe × Dismiss tha. Food import me sirf update hue foods par activity "imported foods 0 foods" likhti thi.
- **Ab:** Stat cards ki height content ke hisaab se (kam se kam 80), adherence bar jagah kam ho to pehle chhota hota hai, table headings "…" + tooltip. Needs action 5 se zyada rows par card ke andar hi scroll hota hai (scrollbar ke saath), × Dismiss hata diya. Activity: "imported 3 foods from Excel", "updated 2 foods from Excel", ya dono ho to "imported 3 foods · updated 2".
- **Kyun:** Gautam (22 Oct) ke admin dashboard aur activity screenshots.
- **Updated:** app/lib/features/admin/dashboard/admin_dashboard_screen.dart, backend/apps/nutrition/views.py, backend/tests/test_food_import.py, docs/screens/behaviour.md

### 2026-10-22 · Typeable steppers, cut text tooltips, Everyone, link card, Log out on My profile
- **Pehle:** Food drawer me Calories box "367.…" kat jata tha. Default serving / unit weight / Amount sirf − + se badalte the. Import me "100 g" wali row ka default serving 1 g ho jata tha, aur group me na aane wali category (Snacks) ka naam kho jata tha. Text field me sirf beech ke text pe click se focus hota tha. "…" se kate text ka poora text kahin nahi dikhta tha. Link item me badi khali picture thi. Assign to clients me sabko ek saath chunne ka option nahi tha. Trainer ka Log out My profile → Account me chhupa tha.
- **Ab:** Calories box chauda (kabhi nahi katta). Default serving, unit weight aur Portion Amount ke number pe tap karke type kar sakte ho (client ke Log food jaisa). "100 g" row → 100 g default serving; "1 (150 g)" → "1 piece"; "1 cup (150 ml)" → "1 cup". Other group ke saath apna category naam (Food.category). Import me ab koi chupa hua match nahi: sirf library group ka naam (Protein, Carbs, Fats, Veg / Vegetables, Fruits, Dairy, Indian dishes, Beverages) usi group me jaata hai; Grains, Egg, Legumes, Chicken, Cereals jaisi baaki categories Other me apne naam ke saath (list ke Group column aur import preview me "Other · Grains"). Edit targets aur library ke baaki steppers (weeks, sets wagairah) ka number bhi tap karke type hota hai. Text field ke box me kahin bhi click → focus. Har "…" wale text pe hover karo to poora text tooltip me (CutText, ~320 jagah). Link item: chhota link card (site, blue address, tap pe khulta hai). Chaaron Assign to clients lists me upar "Everyone" row (sab chuno / hatao; search ke saath "All shown"). My profile me Edit ke paas Log out.
- **Kyun:** Gautam (22 Oct) ke screenshots: calories cut, rice import, Other category, steppers editable, field focus, ellipsis tooltip, link card, Everyone, Log out.
- **Updated:** app/lib/core/widgets/type_number.dart (new), tooltip.dart (CutText, AppTooltip.when), input.dart, client.dart, food_drawer.dart, nutrition_screen.dart, meal_builder_screen.dart, cp_plans_meal_edit.dart, cp_content_drawers.dart (drEveryone), content_drawers.dart, builder_sheets.dart, hb_common.dart, meal_builder_sheets.dart, trainer/me/me_screen.dart, ~90 files Text → CutText; backend/apps/nutrition (models, serializers, importer, migration 0007_food_category), tests/test_food_import.py; docs/screens/behaviour.md, architecture/data-model.md

### 2026-10-22 · Food import template = Vimal's sheet
- **Pehle:** Download template me sirf 10 columns the (Food, Portion_g, Calories_kcal, Portion, Protein, Carbs, Fat, Fibre, Group, Diet). Vimal ki sheet ka Main_Category (veg / non-veg) aur Source column import nahi hota tha; "100 g" jaisa portion bhi ek unit ban jata tha.
- **Ab:** Template me Vimal ki sheet ke saare 15 columns usi order me (Category … Potassium_mg, Source, Main_Category) aur 4 sample rows. Main_Category diet ki tarah padha jata hai, Source food ka source note banta hai (IFCT / USDA), Legumes / Chicken / Fish groups protein me jaate hain, "Sodium (mg)" jaise headers bhi match hote hain, "100 g" unit nahi banta. Import drawer me "Category, Main_Category, Source" row.
- **Kyun:** Gautam: template me import wale fields kam the; uski sheet me itni details hain.
- **Updated:** backend/apps/nutrition/importer.py, tests/test_food_import.py, app/lib/features/library/nutrition/food_import.dart, docs/screens/behaviour.md

### 2026-10-22 · Client profile missing parts; toolbars wrap, chip rows scroll
- **Pehle:** Client profile me target date, health over time, form-check video, supplement stock history aur body map "Not built" the. Nutrition / Food library ~850 px par overflow stripes aate the; chip rows wrap ho jati thi. Trainer dashboard Today rows me client ka avatar (RS) tha. Content drawer me "Plays in the app" row tap karne par kuch kaam ka nahi hota tha.
- **Ab:** Edit details me Target date; History me target date change aur health lines (Since… / … cleared); stock 0 hone par "ran out of" save hota hai aur Compare me "Ran out of stock" row; client logger ke set menu me "Send a form video" (trainer ko notification, Logs workout detail me Watch); Plans exercise drawer me body map. Chip / badge rows ek line me sideways scroll, upar ka toolbar (search, tabs, dropdown) wrap ho sakta hai, tabs scroll. Today rows se avatar hata. Video file row ka tap hata, label rehta hai. Phone par Import from Excel kholne par layout error aata tha (footer phone par stretch hota hai), ab theek.
- **Kyun:** Gautam (22 Oct): client profile ke baaki hisse, form video workout logger me, responsive bina overflow, RS hatao.
- **Updated:** backend/apps/clients (models, serializers, history.py, logs.py, migration 0006), backend/apps/habits/views.py, backend/apps/training (FormVideo, migration 0007, form-video action), tests, app/lib/features/trainer/client_profile/*, clients_parts.dart, client/train/*, core/widgets/media.dart (playVideoFull), library/lib_common.dart (SearchTabsRow, ChipScroll), nutrition, content, meal builder, admin dashboard, trainer dashboard, docs/architecture · Decision D-46

### 2026-10-22 · Habits & supplements rights and look; Content media inside the app
- **Pehle:** Habit ya supplement plan banane / badalne ke liye "Edit gym templates" chahiye tha (default off), isliye Aman kuch add nahi kar sakta tha, sirf dekh sakta tha. Type cards simple the, Frequency tabs poori width me, list rows lambe. Content drawer me video, picture aur PDF naye browser tab me khulte the.
- **Ab:** Trainer apne habits aur supplement plans bana sakta hai aur sirf apne wale badal / delete kar sakta hai; gym wale par "Duplicate it from ⋯ to make your own". Type cards chhote aur simple (42 px: radio · icon · naam · grey hint), Frequency tabs label jitne chaude, list rows chhote. Content: video wahi chalta hai (full screen button player me), YouTube wahi, picture aur PDF app ke andar full screen. Picture cards par apni photo dikhati hai. PDF drawer me pehla page preview ("Tap to read"). Exercise detail me "Client logs" badge right me. Storage ab asli limit hai (20 GB poore hone par upload ruk jata hai). Naya video pick karte hi upload hota hai aur Save se pehle cover frame chun sakte hain (`content/stage/`). New content drawer: tabs fit width, Category select chhota, drop area hover / drag par react karta hai, file aane ke baad drop se replace nahi hota (sirf Replace se), × se nayi file hatao.
- **Kyun:** Gautam (22 Oct): Aman ko permission, type / tick chhote aur simple, tabs fit width, PDF preview, Client logs badge right, storage limit, cover save se pehle, drop area, list height kam, image / video / PDF usi screen me.
- **Updated:** backend/apps/habits/views.py, serializers.py, tests/test_habits_library.py, app/lib/features/library/habits/*, app/lib/features/library/content/*, app/lib/core/widgets/media.dart (showPdfViewer, PdfFirstPage), app/lib/features/library/exercises/detail_screen.dart, app/lib/core/api/api_client.dart (upload), backend/apps/content/views.py (stage, storage limit), backend/apps/training/frames.py (probe_source), tests/test_content_library.py · Decision D-45

### 2026-10-22 · Admin Dashboard and admin More page
- **Pehle:** Admin login karke har page par "This page is on the way" aata tha (admin ka router map khali tha). Dashboard API ke Needs action rows me sub line nahi thi, titles "1 programs" jaise the, aur Trainer performance ka "This week" select kuch nahi badalta tha.
- **Ab:** `/dashboard` board AdminDashboard / AdminDashboardMobile jaisa: 4 stats, 6 at-a-glance tiles (phone par ek list card), Needs action (kind chips, CTA, × dismiss, Show all), Trainer performance (table; phone par rows; This week / This month), At-risk clients (Remind + Undo, Remind all modal skip-24h ke saath), Recent activity (View all). Header: client search modal, bell (notifications), Add client, account menu (Settings, Log out). Phone More page (AdminMoreMobile). Library pages (Programs, Exercises, Nutrition, Habits, Content) admin ke liye bhi khulte hain. API: `dashboard/admin/` me `subline`, `notices`, `unread`, `onboarding_pending.forms_missing`, har Needs action row me `sub`, `?period=month`.
- **Kyun:** Gautam: trainer side poora, ab admin 1-2 screens ache se.
- **Updated:** app/lib/features/admin/, app/lib/app/router.dart, app/lib/features/trainer/dashboard (bell dropdown shared), backend/apps/activity/dashboard.py, backend/tests/test_admin_dashboard.py, docs/screens/status.md, docs/architecture/api-endpoints.md, docs/phases/CURRENT.md

### 2026-10-21 · Content library page
- **Pehle:** `/content` "This page is on the way" dikhata tha; exercise ke "Upload to library" se khali page khulta tha. Content API me card ke liye length, used in, who has it aur storage nahi tha; `content/<id>/detail/` crash karta tha (action ka naam `detail` DRF ke `self.detail` se takrata tha).
- **Ab:** Content library board ke jaisa: categories rail + storage, search, kind tabs, cards 8 per page, item drawer, New / Edit content (upload / YouTube / cover frame / article), Assign to clients (Everyone sirf Vimal), New category, Delete + Undo. Phone par chips aur 2 column. API: `content/summary/`, rows me `length_label`, `uses`, `who`, `file_name`, `frame`; upload par length / resolution / pages bharte hain. Demo items categories me file hue.
- **Kyun:** Gautam: habits ke baad content library, phir admin.
- **Updated:** app/lib/features/library/content/, app/lib/app/router.dart, backend/apps/content/, backend/tests/test_content_library.py, docs/screens/status.md, docs/architecture/*

### 2026-10-21 · Habits & supplements page; Pre-workout supplement timing
- **Pehle:** Trainer ke Library me "Habits & supplements" par "This page is on the way" aata tha. Supplement timing me Pre-workout nahi tha (board me hai).
- **Ab:** `/habits` page board jaisa: Habits (list, editor, Save / Discard, client preview, Assigned to, Assign, Duplicate / Delete + Undo, New habit) aur Supplements (plans, dose and timing modal, quick add, Custom, note, Client sees, Rename / Duplicate / Delete + Undo, New plan). Phone par list → sheet. Unsaved changes ke saath page chhodne ya doosra habit kholne par pehle poochta hai. Daily target max 100,000. Nayi timing `pre_workout` (client app me "before training"). `habits/counts/` batata hai page par kya kar sakte hain.
- **Kyun:** Gautam: trainer ke Library pages poore karo (2026-10-21).
- **Updated:** app/lib/features/library/habits/*, app/lib/app/router.dart (onExit on section pages), core/widgets/tabs.dart (byLabel), backend/apps/habits (Timing, counts, target limit, migration 0004), notifications/reminders.py, tests/test_habits_library.py, docs/screens/status.md, docs/architecture/*

### 2026-10-22 · Meal builder: alternatives in a drawer, smaller amount stepper
- **Pehle:** Portion panel me "Add alternative" ek chhota popover kholta tha; Amount ka − n + poori width me bahut lamba tha.
- **Ab:** "Pick an alternative" drawer khulta hai (Same group / All foods, match %), phone par sheet. Amount stepper 132 wide, unit picker baaki jagah. Client profile ke meal editor me bhi same stepper.
- **Kyun:** Gautam ka feedback (2026-10-22).
- **Updated:** app/lib/features/library/nutrition/meal_builder_screen.dart, client_profile/cp_plans_meal_edit.dart

### 2026-10-21 · Debug-mode errors, value limits, meal plan menu, More page
- **Pehle:** Food library tab tablet width par khali (Diet dropdown bina width ke Row me, debug me layout error). Meal builder me food click karne par "setState called after dispose" (text field focus listener), Assign modal build ke beech list set karta tha, aur portion drawer ka Done button desktop drawer me error deta tha. Edit exercise: cover frames chhoti width par overflow, "Shows on the How to tab" card ke beech me, tablet par fields poori width me lambe. Food drawer me calories / grams me koi limit nahi thi (1.99e+44 kcal tak dikhta tha). Meal plan ke stat cards me Fibre · Water do column le leta tha, aur ⋯ menu me kam options. Phone par page title upar chipka hua. Trainer More page saada tha. Raat 12 baje (IST) se pehle 5:30 ghante tak assign + Undo history chhod deta tha (UTC date se compare hota tha).
- **Ab:** Same-day Undo ab gym ke time (IST) se check hota hai, program aur meal plan dono me. Diet dropdown ki width fixed; text field apna focus listener hata deta hai; Assign list aane par set hoti hai; Done button sirf phone par full width. Frames sideways scroll, card note title ke neeche, ek column me form 680 wide (left aligned). Food values: kcal / g max 9999.9, mg max 99999 typing me hi; save par per 100 g 900 kcal / 100 g / 50,000 mg se upar "Too high". Stat grid 3 + 3 (Fat · Fibre · Water). ⋯ menu: Rename, Edit targets, Add meal, Assign, Clients on this plan, Duplicate, Discard, Delete. Phone par page ke upar 16 px jagah. More page: har row ke neeche ek line, "You" group (My profile, Calendar), neeche app ka naam.
- **Kyun:** Gautam ka test (debug console log aur screenshots, 2026-10-21).
- **Updated:** app/lib/core/widgets/input.dart, select.dart, app/shell/page.dart, features/library/nutrition/* , exercises/edit_screen.dart, trainer/more/more_screen.dart, client_profile/cp_plans_meal_edit.dart, backend/apps/training/services.py, apps/nutrition/services.py

### 2026-10-21 · Exercise library, Exercise page and program day cards fixes
- **Pehle:** Exercise card par "2 progra…" kat jaata tha (⋯ neeche ki line me), video wali exercise par bhi sirf dumbbell icon. Add to program same din me same exercise dobara daal deta tha. Filter kholte hi doosra menu khul jaata tha. Edit page: Equipment dropdown "Ba…" kat ke dikhta tha; step / cue likhte hi naya khali field aa jaata tha aur Add step / Add cue kuch nahi karte the; Pick a video me thumbnail nahi the, "Upload to library" par page badalta tha par modal khula rehta tha; edit ke baad library cards purane rehte the. Exercise page: "Time pe…" kat jaata tha; YouTube do baar likha tha (upar aur player ke neeche exercise name ke saath), aur link ki ek alag line thi. Program builder ke day cards alag-alag size ke the aur exercise list dikhate the.
- **Ab:** Card par ⋯ cover ke kone me, neeche level aur "3 programs" poora. Video ka cover na ho to video ka pehla frame (ffmpeg, ek baar bana ke save) card, Exercise page aur Pick a video me. Add to program me jis din exercise pehle se hai vo "Added" (tick, chun nahi sakte), program ke neeche "Already on Mon, Fri"; server bhi double nahi daalta. Filter me option list sirf hover / click par. Dropdown menu kam se kam 180 wide, Equipment chhoti width par Level ke upar. Typing se naya field nahi banta; Add step / Add cue naya field jodta hai. Upload to library modal band karke Content library kholta hai. Edit / Exercise page se lautne par cards reload. Stats card: Client logs header me pill, Sets · Time · Rest · RPE · Tempo ek row (phone par 3 + 2). Video card: header me "YouTube link · Open in YouTube", player ke neeche wali line aur link wali line hati. Builder day cards sab ek size: naam, "4 exercises · 35 min", neeche dumbbell (rest me moon).
- **Kyun:** Gautam ka test feedback (screenshots, 2026-10-21).
- **Updated:** backend/apps/training (frames.py, serializers.py, services.py, views.py), apps/content (views.py, library.py), tests/test_exercises.py, app/lib/features/library/exercises/*, lib_common.dart, programs/builder_screen.dart, core/widgets/select.dart, client_profile/cp_plans_parts.dart, docs/architecture/api-endpoints.md

### 2026-10-21 · Nutrition & foods page and Meal plan builder built
- **Pehle:** Library → Nutrition "This page is on the way" dikhata tha. Meal plan sirf client page ke andar edit ho sakta tha; food library, Excel import aur master meal plan builder nahi the. Built-in food delete ho sakta tha.
- **Ab:** Nutrition page: Meal plans tab (cards, ⋯ menu, New meal plan) aur Food library tab (table / phone rows, filters, pager, Create / Edit food drawer, Excel import). Meal plan builder `/nutrition/:id`: targets, meals → options → foods, Portion and swaps panel (desktop side column, phone / tablet drawer), alternatives, client permissions, Assign (sirf apne clients, "Moves here" badge), clients drawer. Publish = save + clients ko bhejna; draft banner (Discard / Publish now), bahar jaane par "Publish your changes?" (Publish / Don't publish / Cancel). Built-in food read-only; team food delete ho sakta hai.
- **Kyun:** Plan ka next step (Nutrition & foods), boards Nutrition, NutritionMobile, MealPlanBuilder, MealPlanBuilderMobile.
- **Updated:** backend/apps/nutrition (views, serializers), tests/test_meal_plans.py, app/lib/features/library/nutrition/*, app/lib/app/router.dart, app/lib/core/theme/colors.dart, cp_plans_meal_edit.dart, docs/architecture/*, docs/screens/status.md · Decision D-44

### 2026-10-21 · Programs list refresh, card layout, exercise drawer in the builder
- **Pehle:** Builder band karke Programs par aate the to naya program ya naya naam card me nahi dikhta tha (list reload builder ke band hote waqt chalta tha aur fail ho jata tha). Desktop card me icon upar, name aur level neeche; "By you / Gym" badge baaki tags ke saath left me. Builder me "Exercise details" seedha exercise page khol deta tha.
- **Ab:** Builder band hone ke baad list reload hoti hai, card turant naye naam, week aur "Edited" ke saath. Card me name aur level icon ke right side (phone aur desktop dono), owner badge tags wali line me right end par. "Exercise details" client page wala exercise drawer kholta hai (video, sets/reps/rest, muscles, prev/next); neeche "Open exercise page" aur "Edit sets and rest".
- **Kyun:** Gautam ka test feedback.
- **Updated:** app/lib/features/library/programs/programs_screen.dart, builder_screen.dart, app/lib/features/trainer/client_profile/cp_plans_parts.dart

### 2026-10-21 · Program builder Save changes, leave prompt, week menu, real cover frames, card menu
- **Pehle:** Builder har change turant save karta tha (clients adhoore edits dekhte the), bahar jaate waqt kuch nahi puchta tha, week sirf copy ho sakta tha (delete nahi). Assign ke baad Undo karne par Plan history me "Ended" aur "Replaced" rows aa jaati thi. Card par pata nahi chalta tha program gym ka hai ya kisne banaya. Cover frame tiles nakli the (rang + 0:04, 0:12). Program card ke ⋯ me kam options, "10 weeks" / "days / week" alignment kharab, builder se lautne par list update nahi hoti thi, "+ Add" par tooltip nahi, stepper text cut, Add exercise drawer me play icon.
- **Ab:** Builder me Save changes / Discard; bahar jaane par "Save your changes?" (Save / Don't save / Cancel), browser tab band karne par bhi warning. Week ka ⋯ menu: Copy, Add empty week, Delete week. Same din assign + undo (kuch log nahi hua) = koi history nahi, purana plan wapas Current; Assign se hataya to "Unassigned". Card par Gym / By you / By Aman tag, builder me "Made by …". Cover frames video se asli stills (ffmpeg) ya YouTube ke stills. Card menu: Open, Rename, Assign, See assigned clients, Duplicate, Archive, Delete; cards same height; list refresh; tooltips; drawer rows me picture + "Dumbbell · 3 × 8–12".
- **Kyun:** Gautam ke 2026-10-21 ke messages aur screenshots.
- **Updated:** backend/apps/training (frames.py, models, serializers, services, views, migrations 0005–0006), requirements.txt, tests/test_exercises.py, tests/test_programs.py, app/lib/core/leave/*, app/lib/app/router.dart, app/lib/features/library/** , cp_plans.dart, cp_plans_edit.dart, button.dart, ex_common.dart, docs · Decisions D-42, D-43

### 2026-10-21 · Android build, login from a real phone, login side panel 40 / 60, help sheet speed
- **Pehle:** Android build `checkDebugAarMetadata` par fail hota tha (permission_handler ko compileSdk 37 chahiye, app 36 par tha). Phone par app "offline" dikhata tha: 10.0.2.2 sirf emulator ke liye hai, Android debug build plain http block karta tha, aur dev server sirf localhost par sunta tha. Web login pages ka left panel max 520 wide tha, halka flat blue. "Need help?" sheet `gym/` ka jawab aane ke baad hi khulti thi, isliye der se khulti thi.
- **Ab:** compileSdk 37 (targetSdk / minSdk same). Debug / profile build me http allowed; dev settings koi bhi host accept karti hain; README me real phone ke steps (laptop IP, `--host 0.0.0.0`, Windows Firewall). Left panel window ka 40 %, form wala hissa 60 %; panel ka blue gehra aur chaaron taraf fade hota hai. Help / support sheet turant khulti hai, number aur email baad me aate hain.
- **Kyun:** Gautam ne phone par chalaya aur ye issues bheje (2026-10-21).
- **Updated:** app/android/app/build.gradle.kts, app/android/gradle.properties, app/android/app/src/debug|profile/AndroidManifest.xml, backend/config/settings/dev.py, README.md, app/lib/features/auth/auth_frame.dart, sheets.dart, app/lib/core/theme/colors.dart, docs/memory/README.md, docs/phases/CURRENT.md · Decision D-41

### 2026-10-20 · Exercise library, Exercise page and Add / Edit exercise built
- **Pehle:** Library → Exercises "This page is on the way" dikhata tha. Program builder ka "Exercise details" bhi wahi khali page kholta tha. Backend me built-in exercise badla ja sakta tha, cover image upload nahi tha, "Also works" me note nahi tha, aur Used in me sab trainers ke clients gine jaate the.
- **Ab:** Exercise library board jaisa (picture cards, search, Filter — Muscle / Equipment / Level / Source, chips, Sort, New exercise, ⋯ menu). Exercise page: cover, Default sets and reps, How to / Form cues / Muscles (body map), Video, Details, Used in N programs, Add to program (program + din, har week me add), Delete with Undo. Add / Edit exercise: saare fields, content library se video ya YouTube link (preview ke saath), cover frame ya Upload image, muscles chips aur body map par tap. Built-in exercise read-only ("Duplicate to edit"); custom ke liye "Add custom exercises" chahiye. Trainer ko Used in me sirf apne clients.
- **Kyun:** Gautam: "Banado agla" — Programs ke baad Exercises.
- **Updated:** backend/apps/training/ (models, migration 0004, serializers, views, services), apps/common/seed_data.py, seed_defaults.py, backend/tests/test_exercises.py, app/lib/features/library/exercises/, lib_common.dart (filter), app/lib/app/router.dart, core/widgets/select.dart, tabs.dart, core/theme/colors.dart, client/train/train_parts.dart (tappable body map), docs/screens/status.md, docs/phases/CURRENT.md, docs/architecture/api-endpoints.md, docs/memory/README.md · Decision D-40

### 2026-10-20 · Programs page and Program builder built
- **Pehle:** Library → Programs "This page is on the way" dikhata tha. Backend me trainer naya program bana sakta tha par use build nahi kar sakta tha (edit ke liye "Edit gym templates" chahiye tha). Program cards par sab trainers ke clients dikhte the, aur trainer ka Assign dusre trainers ke clients ko program se hata sakta tha. Delete ka Undo nahi tha.
- **Ab:** Programs page board jaisa (cards, Active / Archived, search, New program, ⋯ menu, Undo). Program builder: weeks, 7 din ka grid (phone par list), din ka panel, exercise table (phone par cards), sets / rest modal, Edit for this program, Add exercises, Assign, Assigned clients, rest day, coach note — har change turant save, Undo ke saath. Trainer apne banaye program badal sakta hai; Vimal ke program read-only hain "Duplicate to edit" ke saath. Cards aur Assign me trainer ko sirf apne clients. Delete → Undo clients ko wapas program par laata hai. Demo me 5 aur programs (ek archived).
- **Kyun:** Gautam: "Ab aage ka karo" — TrainerMoreMobile ke baad Library screens, Programs se shuru.
- **Updated:** backend/apps/training/views.py, services.py, serializers.py, seed_demo.py, backend/tests/test_programs.py, app/lib/features/library/ (lib_common, programs/), app/lib/app/router.dart, app/lib/core/widgets/overlays.dart (menu sub line), app/lib/core/theme/colors.dart, app/lib/core/icons/app_icons.dart, docs/screens/status.md, docs/phases/CURRENT.md, docs/architecture/api-endpoints.md, docs/memory/README.md · Decision D-39

### 2026-10-20 · Trainer More tab (phone) built; Check-ins badge everywhere
- **Pehle:** Trainer ke phone par More tab "This page is on the way" dikhata tha. Bottom bar ka Check-ins badge sirf Dashboard ya Check-ins kholne ke baad aata tha (More, Calendar, My profile seedha kholne par nahi). Log out karke dusre user se login karne par purana badge reh sakta tha.
- **Ab:** More page board jaisa: upar profile card (→ My profile), Library group (Programs, Exercises, Nutrition & foods, Habits & supplements, Content library), neeche laal Log out ("Log out?" confirm). Badge app khulte hi load hota hai, har trainer page par dikhta hai, aur naye login par khaali se shuru hota hai.
- **Kyun:** Gautam ka order: My profile ke baad TrainerMoreMobile. Board me badge More page par bhi hai.
- **Updated:** app/lib/features/trainer/more/more_screen.dart, app/lib/app/router.dart, app/lib/app/shell/app_shell.dart, app/lib/core/theme/colors.dart, docs/screens/status.md, docs/phases/CURRENT.md

### 2026-10-20 · My profile (phone) — layout fixed; date-proof tests
- **Pehle:** Phone par My profile ke header me speciality, experience, access aur last login ek hi line me chipke the; stats 4 alag cards; details do column me tight; tab strip scroll hone par khula tab dikhai nahi deta tha (link se tab kholne par error bhi). Device dates "Wed 14 oct" (month chhota). Tablet (600–819) par naam "Aman Ver…" kat jata tha. 7 backend tests kuch dates par fail hote the (seed data ka measurement period aaj ko cover karta tha) aur PDF test `pypdfium2` ke bina.
- **Ab:** Header teen saaf lines me; stats ek card me 2 × 2; details label-left / value-right rows; tab strip khule tab ko beech me le aata hai; "Wed 14 Oct". Tablet ke liye alag header (naam pura, button right). Tests kisi bhi date par pass (`fresh_measure_period` fixture), device date ka naya test.
- **Kyun:** Gautam (18 Oct): phone par details, cards, buttons theek se fit aur line me hon. Tests green hone chahiye push se pehle.
- **Updated:** app/lib/core/widgets/tabs.dart, app/lib/features/trainer/me/me_screen.dart, me_common.dart, backend/apps/trainers/me.py, backend/tests/*, docs/screens/status.md, docs/phases/CURRENT.md, docs/rulebooks/local-setup.md

### 2026-10-18 · Docs — handoff for a new Claude account
- **Pehle:** Handoff sirf `docs/phases/CURRENT.md` me tha; kaam ka tareeka, parked items aur artifact links alag-alag jagah the.
- **Ab:** `docs/HANDOFF.md` me sab ek jagah: app, kya bana / kya baaki (board names), parked Daily summary + Gym news, Gautam ki preferences, design canvas artifacts, kaam kaise hota tha, naye project ke instructions aur pehla message.
- **Kyun:** Gautam project ko dusre claude.ai account se continue karenge.
- **Updated:** docs/HANDOFF.md, CLAUDE.md, docs/phases/CURRENT.md

### 2026-10-18 · My profile — drag and drop fixed, Edit details; workout row gap; dashboard Done in ⋯
- **Pehle:** Web par upload modal me file drop karne se browser use naye tab me khol deta tha. Document ki details badalne ka seedha button nahi tha (sirf Replace file). Workout editor me exercise naam aur Sets wali line me zyada gap. Viewer footer (Edit details / Replace file / Delete) "RIGHT OVERFLOWED BY 35 PIXELS". Dashboard Today row me alag Done button, "Clients who need you" chips wrap hote the, Activity card me View all nahi.
- **Ab:** Upload modal khula ho to page par kahin bhi file chhodo, app use le leta hai (web: apna drop listener, desktop: desktop_drop). Document card par `Edit` aur viewer me `Edit details` (naam, type, dates, kaun dekhe; file tab tak wahi jab tak naya na chuno). Naam aur Sets line ka gap 2 px. Viewer footer: do buttons barabar jagah, Delete ab icon (koi overflow nahi). Dashboard: Done ab ⋯ menu me "Mark as done", chips sideways scroll, Activity card me `View all` → My profile · My activity.
- **Kyun:** Gautam ka 18 Oct feedback.
- **Updated:** me_docs.dart, me_pick_web.dart, me_pick_io.dart, cp_plans_edit.dart, dashboard_screen.dart

### 2026-10-18 · Trainer — debug crashes, plan editors, My profile uploads, Daily summary / Gym news
- **Pehle:** Calendar debug mode me crash ("LayoutBuilder does not support returning intrinsic dimensions"), New session ka Starts row debug me overflow. Workout editor me note ek alag line me, rows unchi. Phone par editor ke Back / Cancel / Save ajeeb jagah. Add food me galti se add hua food hata nahi sakte the. Alternatives me "0.5 × 1 katori", grams nahi. Your access card simple. Daily summary / Gym news toggles kuch nahi bhejte the. Upload me drag and drop nahi, phone par sirf photos, PDF ka page nahi dikhta tha.
- **Ab:** Calendar ka grid fixed height (crash gaya), Starts row fit. Note ⓘ icon ke tooltip me, rows chhoti. Teeno editors me ek `PlanEditBar` (phone: ek row, icon Back / Reset, Cancel, Save poori jagah), phone day strip me saare 7 din. "✓ Added" dabao to food hat jata hai (web par hover = Remove). Amount "½ katori", "1½ katori · 225 g", alternative rows me grams · kcal · P / C / F, popover window ke andar scroll. Your access card naya. Daily summary roz 8:00 baje (bell, push, email; dashboard ke numbers), Gym news admin post kare to trainers ko (admin screen baad me). Drag and drop, phone par PDF/JPG/PNG, PDF ke pages viewer me (zoom, page). Saare trainer pages debug mode me check.
- **Kyun:** Gautam ka 18 Oct feedback (debug me test karte hain).
- **Updated:** calendar cal_grid, cal_drawers; client_profile cp_plans_edit, cp_plans_meal_edit, cp_plans_supp_edit, cp_plans_parts; me me_tabs, me_docs, me_pick_io; pubspec (file_picker, desktop_drop, pdfrx); backend nutrition/swaps.py, notifications (staff.py, models, views, urls, serializers, reminders, migration 0003), trainers/me.py, config settings (beat); tests test_team_notices · Decision D-38 (update)

### 2026-10-17 · Trainer — Calendar and My profile built
- **Pehle:** Trainer ke Calendar aur My profile pages nahi bane the. Admin Trainers table me Aman ki average adherence 50 % (baaki jagah 56 %).
- **Ab:** Calendar: Week / Day, 4 stats, session panel (Open profile, Reschedule, Mark as done, Cancel + Undo), New / Move session drawer clash check ke saath, My working hours; phone par day strip. My profile: Overview, Documents (upload, viewer, replace, delete), What clients see (9 toggles + preview), My access (Ask for more access), My activity, Account (password, devices, notifications), Edit my details. Numbers dashboard aur admin table jaise. Adherence ab har jagah same.
- **Kyun:** Gautam: "Agla: Trainer Calendar, phir My profile."
- **Updated:** app/lib/features/trainer/calendar/*, me/*, router.dart, core/theme/colors.dart, core/icons/app_icons.dart; backend scheduling (models, views, migration 0002), trainers (me.py, views, serializers, urls, models, migration 0002); tests test_trainer_calendar, test_trainer_me · Decision D-38

### 2026-10-17 · Client profile round 3 — Portion and swaps, supplement copies, setup panel
- **Pehle:** Add food / Add exercise / Add superset drawers me rows me bahut jagah, line nahi, aur poora drawer scroll hota tha. Meal editor me sirf Portion panel tha (swaps nahi), tablet par dikhta hi nahi tha. Food ke swaps sab clients ke liye ek (Food.swaps); supplement plan bhi sab clients ka ek. Workout editor me 900–1100 px par "RIGHT OVERFLOWED BY 8 PIXELS". Forms tab me lamba onboarding card poora page scroll karta tha, photos nahi dikhte the. Meal log amount "2 pieces". Adherence ka meals a day master plan se. Setup ka left panel gehra neela, poora panel scroll hota tha; Training experience tabs pheeke, text boxes me placeholder nahi.
- **Ab:** Drawers: compact rows, beech me line, tabs + search upar ruke rehte hain, sirf list scroll (`showAppDrawer(fixedBody: true)`). Board ka *Portion and swaps* panel: Amount − n +, units menu ("UNITS OF …", Grams, ✓, "+ Add a unit in the food library"), "Swaps Riya may use" (match %, ×), "+ Add alternative" (Same group / All foods, "Amounts give the same calories as …"), rows par "N swaps" badge aur "Was: …" line; tablet par side panel, phone par sheet. Swaps har client ki copy me alag. Supplements: "Edit for Riya" editor, apni copy, Reset to master. Workout editor kisi width par overflow nahi. Forms: answers card ke andar scroll, completed form me 3 start photos (tap = full screen, print me bhi). Amount "2 pieces (80 g)". Adherence / Overview / Logs / check-ins client ki copy aur us din ke meals se. Setup panel baaki account pages jaisa light, sirf steps list scroll (kinaron par fade), current step dikhta rehta hai; experience tabs saaf selected state, har box me placeholder. Onboarding 9/9 ke baad Overview "4 of 5" nahi dikhata.
- **Kyun:** Gautam ka 17 Oct (09:43, 09:45, 09:55) feedback.
- **Updated:** cp_plans_meal_edit, cp_plans_edit, cp_plans, cp_plans_supp_edit (new), cp_forms, cp_forms_print, cp_logs_detail, auth_frame, setup_screen, core/widgets/overlays; backend nutrition (swaps.py, models, serializers, services, views, migration 0005), habits (models, views, migration 0003), clients (metrics, logs, overview, account, views), checkins (client_forms, review, client_page), notifications/reminders; tests test_meal_item_swaps, test_supplement_copy, test_meal_adherence_copy · Decision D-37

### 2026-10-17 · Client profile feedback — tooltips, Check-ins fit, logs, history, content, demo data
- **Pehle:** Screen ke kinare par tooltip bahar chala jata tha. Check-ins page khud scroll hota tha aur chhoti width par client ka naam nahi dikhta tha. Workout volume me body weight sets 0 the, meal amount "2 1 piece" dikhta tha, range menu ke options kat rahe the, Custom dates poora page leta tha, Compare plans ek plan par band tha, Journey badge poori width me failta tha, "Remind his to open it". Kuch demo clients (Aditya, Neha, Vikram) ke workouts join se pehle aur ek din me do baar the (Workouts 16/4).
- **Ab:** Tooltip hamesha screen ke andar (8 px), jagah na ho to doosri side. Check-ins window me fit, chhote panel me Open profile sirf icon aur numbers 2 column. Volume me body weight + extra load. Amount "2 pieces", "150 g". Range menu poora dikhta hai, Custom dates chhota modal. Compare: plan ya period (Previous / Last 30 days, plan ka pehla / doosra hissa, custom). Export band (comment). Badges text jitne chaude. "Remind him / her / them". Content assign list ~6 rows, andar scroll. Demo data: join se pehle ke logs aur ek din ke double workouts hata diye, seed ab dobara nahi banata.
- **Kyun:** Gautam ka 17 Oct feedback (screenshots ke saath).
- **Updated:** core/widgets/tooltip.dart, features/trainer/checkins/*, client_profile cp_logs*, cp_common, cp_history, cp_content*, cp_plans_assign / parts / meal_edit (badges), backend training services (volume), clients/logs (compare ranges), content/client_tab, seed_demo · Decisions D-34, D-36

### 2026-10-17 · Onboarding — Gautam ka coaching form, answers profile par
- **Pehle:** Setup ke 5 steps (goal, about, schedule, health, food) the; answers sirf `onboarding` JSON me. About card me Experience, Diet, Trains at, Daily activity, Wake-up "—" aate the aur Edit profile me ye fields the hi nahi. Age kahin calculate nahi hota tha.
- **Ab:** Setup = Gautam ka Google Form, 9 steps me (goal, about you, training, health, food, day of eating, supplements & medicines, measurements & photos, last step + terms "I agree"). Har answer client profile ka field hai; weight pehla weigh-in, measurements pehli Measurement, photos "Start photos" set. Age date of birth se banti hai. Onboarding form (admin edit kar sakta hai) ke questions `profile_key` se field se jude hain; naya question bina key ke last step me poocha jata hai aur Forms → Onboarding questionnaire me dikhta hai. Edit profile drawer me naye sections: Training, Health, Food and lifestyle, Supplements and medicines. About card ki values server se (`about.items`). Demo clients (Riya, Aditya…) ke saare answers seed me.
- **Kyun:** Gautam: "jab real user add karenge tab sari details kaha se aaegi… onboarding change bhi ho sakta hai… app me mock data nahi hona chahiye, sab ache se edit… calculate hona chahiye." Card par chuna: poora form.
- **Updated:** backend apps/clients (models, onboarding.py new, serializers, views, overview, history), checkins (Question.profile_key, defaults, client_forms, serializers, views), accounts/serializers (`setup_total`), seed_demo, migrations clients/0005 + checkins/0006, tests/test_onboarding.py, tests/test_onboarding_profile.py; app auth/setup/*, auth_frame.dart, pending_screen.dart, app/services.dart, trainer/clients/clients_parts.dart, client_profile/cp_overview.dart, cp_forms.dart; docs data-model, api-endpoints, memory · Decision D-36

### 2026-10-17 · Client profile → Plans — meal plan client copy, per-day meals, workout list editor
- **Pehle:** Meal plan "Edit for X" sirf ek "version note" modal kholta tha; day strip badalne par meals same rehte the. Workout editor ek chauda table tha. Exercise drawer ka video naye page me khulta tha. Edit habits me sirf add / delete. Assign drawer ke tabs poori width, list ke rows alag box, preview sirf doosra plan chunne par; workout plans ka level nahi tha.
- **Ab:** Meal plan "Edit for X" = editor (board `pe.meal`): har din ke meals, food add / remove, amount + unit, meal rename / time / remove / add, "Apply to every day". Client ki apni copy (`MealPlanAssignment.custom_plan`, `Meal.weekday`), master nahi badalta; Reset to master copy hata deta hai. Client app ka Food tab usi din ke meals dikhata hai. Version note modal hata diya. Workout editor: din ke exercises ki list (sets × reps, RPE, tempo, rest, load, note) + Swap / Edit / Remove; Edit drawer (Previous / Next). Coach note 4 line. Exercise drawer me video / YouTube wahi chalta hai, picture full screen, link ka label. Edit habits me har habit ka Edit (target, kitni baar, din, note) sirf us client ke liye. Assign drawer: tabs content jitne, list board jaisi (lines, ~6 rows phir scroll), Level filter + row me level, current plan ka preview. Assign plan ▾ menu me icons. `Program.level`.
- **Kyun:** Gautam ka 17 Oct feedback (Plans tab screenshots).
- **Updated:** app client_profile/cp_plans*.dart, cp_plans_meal_edit.dart (new), cp_screen.dart, core/theme/colors.dart (`pickLine`); backend nutrition (models, services, views, serializers, 0004), habits (models, views, 0002), training (Program.level, 0003), notifications/reminders.py, seed_demo; tests/test_client_meal_copy.py; docs data-model, api-endpoints

### 2026-10-17 · Trainer — Client profile (9 tabs) aur Check-ins
- **Pehle:** My clients / dashboard se "View profile" holding page kholta tha. Check-ins page nahi tha. Daily check-in ka review weekly jaisa dikhta tha (Weight, Change…). Notes ka Undo kisi bhi client ka note wapas la sakta tha (id se).
- **Ab:** Trainer Client profile ke saare 9 tab board jaise (Overview, Plans + assign + workout editor, Logs + Compare plans, Progress, History, Content, Forms + client copy, Activity, Notes). Check-ins page: list + review panel, phone par alag page. Daily check-in par Sleep / Energy / Workout / Steps; har number hara (behtar) / laal (kharab). Sidebar Check-ins count. Notes restore sirf usi client ke notes me. Tab title ab build ke beech nahi badalta (console error gaya).
- **Kyun:** Gautam: "ache se cleint profile me pura kar dena .. ye ho jane ke baad checkins wala start kar dena".
- **Updated:** app features/trainer/client_profile/*, features/trainer/checkins/*, app/router.dart, app/app.dart, core/theme/colors.dart; backend clients (history, logs, overview, views), checkins (review, views, client forms, staff logs, tasks), nutrition, habits, training, content, activity, common/mixins; tests; docs behaviour §3.3 §3.6, status · Decisions D-34, D-35

### 2026-10-16 · Fields sirf sahi type lein; Filter side menu; Export band; tab title + favicon
- **Pehle:** Mobile, kg, cm jaise fields me letters bhi type ho jaate the. Edit details me Date of birth haath se `DD / MM / YYYY` likhna padta tha. My clients Filter me group par click karke doosra menu usi jagah khulta tha. Export aur select boxes the. Browser tab me hamesha "twv" aur Flutter ka default favicon.
- **Ab:** Poore app me field apne keyboard type se input leta hai (`core/util/input_rules.dart`): phone = sirf 10 digit, number = sirf digit, decimal (kg, cm) = digit + ek `.` aur 2 decimal, email = bina space. Save par Mobile 10 digit (6–9) aur Email format check — Edit details, Edit profile (client), Join. Join me Mobile ke aage `+91`. DOB date picker se. Filter board jaisa: row par value + `›`, options side me. Export + checkbox comment kar diye. Tab title page ka naam ("My clients · Train With Vimal"), favicon aur app icons TWV logo se.
- **Kyun:** Gautam: "export ... comment kar do", "date sleect ka option rakho", "number ki ho to number hi aae ... mobile 10 digits ... emails bhi", "filter esi banao", "faviicon laga do ... page ka uper name".
- **Updated:** app core/util/input_rules.dart, core/widgets/input.dart, client.dart, overlays.dart (`showFilterMenu`), app/page_title.dart, app.dart, web/index.html, manifest.json, favicon + icons, features/trainer/clients/*, auth/join_screen.dart, client/more/more_sheets.dart, client/food/food_parts.dart; docs behaviour §3.2 · Decision D-33

### 2026-10-16 · Trainer — My clients
- **Pehle:** Trainer ke liye My clients page nahi tha (holding page). Clients API me Next check-in aur Last active nahi the; Next check-in filter sirf Overdue tha.
- **Ab:** My clients (web table + phone list) board jaisa: tabs + counts, search, Filter, Export CSV (list ya selected), select boxes, ⋯ menu (View profile, Edit details drawer), 8 rows ka pager. API me `goal_label`, `next_checkin`, `last_active`; filter `today` / `week` / `overdue` column wale rule se; export `ids=` se selected. Top par AV nahi.
- **Kyun:** Gautam: "ab aage ka karo" (next trainer board).
- **Updated:** backend clients/serializers.py, views.py, filters.py, tests/test_my_clients.py; app features/trainer/clients/*, core/widgets/select.dart + pager.dart, core/util/save_file*.dart, router, colors, pubspec (web); docs behaviour §3.2, status, CURRENT · Decision D-32

### 2026-10-16 · Trainer dashboard layout; check-in photos; Open in YouTube jagah
- **Pehle:** This week right column me, Activity uske neeche 6 rows + Show more. Web top par New session ke paas `AV` profile button. Review drawer ki photo click nahi hoti thi. Exercise guide me "Open in YouTube" video ke neeche alag line me tha.
- **Ab:** This week left (Clients who need you ke neeche), Activity right me Check-ins ke neeche, latest 10, Show more nahi. Web par AV button hata diya. Photo click → full screen viewer. Exercise guide card ki neeche wali line me right side "Open in YouTube" (pehle wahan "YouTube" likha tha).
- **Kyun:** Gautam: "this week ye left me aajae... activity thoda uper... show more na ho latest 10", "image open karni ho to... view karne ka option", "AV likha hai na... hata do", "open in youtube wala thoda galat jagah hai".
- **Updated:** app trainer/dashboard/*, core/widgets/media.dart (OpenInYoutube), client/train/train_parts.dart; backend trainer_home.py (10 rows); docs behaviour §3.1, status, D-31

### 2026-10-16 · Trainer dashboard Activity card, stats, date select; client video, PDF aur guide text
- **Pehle:** Exercise guide / Library me YouTube box debug web par laal error deta tha. Review drawer ke andar `Open profile` par laal screen (`_dependents.isEmpty`). Trainer stats cards 80 px fixed the, number 4 px kat jata tha. New session ka Day list upar khulke screen ke bahar chala jata tha. Demo PDF sirf plain text tha, guide ka text chhota aur halka tha. Dashboard par activity ka koi card nahi tha.
- **Ab:** YouTube player start na ho to still + "Open in YouTube" (error nahi). Drawer pehle band hota hai, phir profile khulta hai; text controllers animation ke baad free hote hain (New session modal me bhi). Stats: 4 barabar cards (patle page par 2 × 2), height content jitni. Menu jis taraf jagah ho us taraf khulta hai, screen me rehta hai, scroll hota hai, chuna hua row dikhta hai. Naya **Activity** card (trainer + uske clients, Show more). "Eating out on a fat loss plan" ab asli designed 6-page PDF; article text 15 / 1.7, headings aur bullets.
- **Kyun:** Gautam ke screenshots: "excercise video modal me video me", "open profile clcik kiya to ye red error", "stats ache karo", "date select wala acha karo", "ek aur activity card", "pdf wala example rakho", "guide ka likhavat acha karo".
- **Updated:** backend activity/trainer_home.py, dashboard.py, urls.py, seed_demo (+ demo_media/eat.pdf, eat.html, scripts/demo_pdf.js), tests/test_trainer_dashboard.py; app core/widgets/media.dart, overlays.dart, colors.dart, trainer/dashboard/*, client/library/library_sheet.dart; docs behaviour §3.1, status, CURRENT · Decision D-31

### 2026-10-16 · Trainer — Dashboard; trainer, admin aur client ke numbers ek jaise
- **Pehle:** Trainer dashboard ka page nahi tha (holding page). "Check-ins to review" har jagah alag gina jata tha: dashboard API weekly + monthly, Check-ins page weekly + daily + monthly, admin Trainers table weekly + daily. "Feeling low" purane low din se bhi aa jata tha jabki client ke latest check-in 4 / 5 the. Trainer aur client ke same paths (`/checkins`, `/more`, `/habits`) ek hi screen kholte the.
- **Ab:** Trainer Dashboard (web + phone hero) board jaisa: stats, Today (Done, ⋯ menu, Cancel + Undo), Clients who need you (chips, Remind + Undo, ek client ek row), Check-ins to review + review drawer (reply, quick replies, Undo), This week, bell, New session. Ek hi check-in queue sab jagah (dashboard, Check-ins page, sidebar badge, My profile, admin dashboard, Trainers table) — test check karta hai ki numbers same hain. Feeling low sirf latest check-in se. Router me trainer ke apne pages. Drawer ab board wale `.drawer` jaisa. Aman ke liye demo din (`seed_demo`).
- **Kyun:** Gautam: "ab trainer ke banane start karo", "data match hone chahiye sabhi... client admin trainer... kahi ulta na ho".
- **Updated:** backend activity/trainer_home.py (new), dashboard.py, checkins/queue.py + review.py (new), checkins/views.py, trainers/views.py, clients/metrics.py, seed_demo, tests/test_trainer_dashboard.py; app features/trainer/dashboard/*, router, app_shell, overlays (drawer look, modal width, menus on root overlay), button (filled icon), avatar (initials), colors, app_icons, assets/ill/trainer_hero.svg; docs behaviour §3.1, status, CURRENT, memory · Decision D-30

### 2026-10-16 · Client — About page, Home hero
- **Pehle:** About page nahi tha. Phone Home par plain top line (date, Hey Riya, bell) tha; hero wala design choose nahi hua tha. Gym ka support time code me "6 am to 10 pm" likha tha.
- **Ab:** About page (`/more/about`, Help & about se): app card + version copy, Vimal ka coach card (stats ke saath), Contact (WhatsApp, Call, Email, Website, Support hours), App (What's new, Rate the app, Terms, Privacy, Open-source licences). Contact aur coach ki baatein gym settings se aati hain (admin badal sakta hai). Phone Home ab hero wala: blue hero status bar ke neeche tak, "Hey Riya", aaj ka workout + "3 of 5 workouts done this week", runner picture, week strip hero par overlap.
- **Kyun:** Gautam: "client about banado... homehero ye hero wala rakhna hai".
- **Updated:** backend gym (models + migration 0002, serializers, views `gym/`), seed_defaults, clients/account.py, tests/test_client_about.py; app about_screen.dart, more_parts (MoMenuRow info row), more_sheets (About row), router, home_screen (hero), app_shell (no top safe area on client Home), colors, app_icons, assets/ill/hero_run.svg; docs behaviour §4.1 / §4.12, status, CURRENT, memory · Decision D-29

### 2026-10-16 · Media — YouTube app ke andar, chhoti picture, demo videos
- **Pehle:** YouTube video ki sirf still dikhti thi aur tap par YouTube khulta tha. Library me picture pura modal le leti thi. Gautam ki machine par ffmpeg nahi tha, isliye seed ke videos me file nahi bani ("Video not uploaded yet").
- **Ab:** YouTube video Library sheet aur Exercise guide ke andar hi chalta hai (iframe / web view, YouTube ka full screen button), neeche `Open in YouTube` link. Chapters embedded video ko seek karte hain. Picture box chhota (Library 240 / web 300), puri picture dikhti hai, tap par full screen. Demo videos ab code ke saath aate hain (`apps/common/demo_media`), seed bina ffmpeg ke chalta hai aur bina file wale videos bhar deta hai. Walking Lunge ab YouTube link hai. Jahan web view nahi hai (Windows desktop) wahan YouTube ki still + play button dikhta hai jo YouTube kholta hai, red error nahi.
- **Kyun:** Gautam: "video yt ka ho ya uploaded, isi me show karo... dusre page me na jae... yt pe jana ho to option do", "image itni badi height na le".
- **Updated:** app pubspec (youtube_player_iframe), core/widgets/media.dart (YoutubeBox), library_sheet.dart, train_parts.dart; backend content/library.py (media_of youtube), seed_demo + demo_media, tests; docs behaviour §4.2 / §4.10, status, CURRENT, memory · Decision D-28

### 2026-10-16 · Media — PDF pages, video, pictures, exercise media, links
- **Pehle:** PDF me sirf coach ka page outline dikhta tha; video me seek / full screen nahi tha; picture zoom nahi hoti thi. Exercise guide me video ki jagah sirf ek dark box tha jo Library par le jata tha, picture ka option hi nahi tha. Reference web link share nahi kar sakte the.
- **Ab:** PDF ke asli pages dikhte hain (server par picture bante hain), tap par full screen zoom aur swipe. Video me seek bar aur full screen (chalta rehta hai). Picture tap par full screen zoom. Exercise guide me exercise ka video yahin chalta hai ya picture dikhti hai; sirf YouTube ho to uski still aur YouTube khulta hai. Details me `Video / picture` row. Naya content type **Link**: Library me `Links` filter, sheet me site + `Open link`. Demo: Leg Press, Walking Lunge video, Romanian Deadlift picture, Riya ke liye ek healthline link.
- **Kyun:** Gautam: "pdf, media (image / videos), article ache se open ho", "excercise me video ya image ho to", "yt links, videos aur reference links bhi honge".
- **Updated:** backend content (pdf_pages.py, library.py, models + migration 0003 link_url / kind link, views), training serializers / views (media), seed_demo, requirements.txt (pypdfium2), tests; app core/widgets/media.dart, library sheet / screen / model, train parts / model / screen, colors, app_icons; docs behaviour §4.2 / §4.10, status, CURRENT, memory · Decision D-27

### 2026-10-16 · Library — client ka Library page bana
- **Pehle:** `/library` ka page nahi tha; More aur sidebar ka Library link khali page par jata tha. Coach share ke saath note nahi likh sakta tha.
- **Ab:** Library page phone + web board jaisa: progress, search, filters, New / Done / Saved, coach ke notes. Item kholne par video (chapters, end par done), PDF (pages, Download), image (Save image), article. Save for later aur Mark as done offline outbox se, Undo ke saath. Coach share me note de sakta hai, aur share program / meal plan se aaya bhi dikh sakta hai.
- **Kyun:** Gautam: "ab aage ka karo ache se" — agla client board Library tha.
- **Updated:** backend content (models + migration 0002, library.py, views), common/media.py (dev video seek), seed_demo, tests/test_client_library.py; app features/client/library, router, video_player; docs behaviour §4.10, status, CURRENT, memory · Decision D-26

### 2026-10-16 · Tabs — har width par chhote (label jitne)
- **Pehle:** Grey tab bars (My account ke All / Unread, Food ke My plan / Food log aur All / Recent / My foods, Progress ke Weight / Body / Strength, History ranges, photo poses) phone par aur kuch web par bhi poori width me faile rehte the.
- **Ab:** Ye sab tab bars har width (390 se 1440) par label jitne chhote, left me. `MoTabs`, `PxTabs`, `TwoTabs` ka default ab compact hai.
- **Kyun:** Gautam (screenshot, 2026-10-16): "ye tabs chote karo... kahi bhi ho tabs... fir width pe ho".
- **Updated:** app more_parts / more_screen, progress_parts / progress_screen / progress_pages / progress_sheets, train_parts, food_screen / food_log_screen; docs/memory/README.md

### 2026-10-16 · More / Progress round 2: one measurement entry per period, height, History sticky
- **Pehle:** Log measurements sheet me Today / Yesterday / 2 din pehle ki chips thi, roz naya entry ban sakta tha. Web My account me Your plan card tha (sidebar me wahi links already hain). Coach Details me `Open check-ins` button tha aur daily check-in ka zikr nahi tha. Edit profile me height nahi thi. First day vs now me sirf weight, waist, hips, body fat. History web par poora page scroll hota tha.
- **Ab:** Measurements ek period (photo cadence, 2 hafte) me ek entry: date chips hat gayi, sheet batata hai "This period · logged Thu, 15 Oct · next one due Sun, 1 Nov", dobara log karne par wahi entry badalti hai (My activity me change line), neeche "Your entries" dates ke saath. Check-in measurements tabhi poochta hai jab is period ki entry nahi hai. History (Weight filter) me "Measurements · 6 logged" har change ke saath. Web My account se Your plan card hata. Coach Details: Open check-ins hata, "Daily check-in · Every day · reminder at 9:00 pm / sent today" row (card aur sheet dono me). Edit profile me Height (cm), My activity me "Height 162 cm → 165 cm". First day vs now me har measurement (biceps bhi). History web: upar ka hissa aur Summary jagah par, sirf list scroll. My activity aur Notifications (phone + web): header, tabs / filters ruke rehte hain, sirf list scroll. Web My account ke title par bell nahi (Notifications tab hai). My activity me 0 wale step / water / sleep logs nahi aate.
- **Kyun:** Gautam ka feedback (screenshots, 2026-10-16) aur decision card "Period me ek baar".
- **Updated:** backend accounts serializers / views (height), checkins services (`measure_entry`, `next_measure_due`) / views / progress / client_page, clients/account.py (daily), tests; app more_screen / more_sheets / more_model, progress_screen / pages / sheets / model; docs behaviour §4.7 / §4.11, status · Decision D-25

### 2026-10-16 · More tab, change lines, measurements in the check-in, photos every 2 weeks
- **Pehle:** More tab sirf "This page is on the way" + Log out tha. Past date ka measurement / weight badalne ka kahin record nahi tha. Measurements sirf Progress ke Log sheet se aate the (weekly form me sawal nahi tha). Check-in har hafte photos maangta tha.
- **Ab:** More (phone) aur My account (web: Overview · Notifications · My activity) board jaisa: profile card + Profile page (Edit sheet: naam, email verify ke baad, mobile, city, DOB), coach card + Details sheet (Add to calendar, Open check-ins), Your plan rows, Notification settings sheet (8 toggles + apne quiet hours, Reset to recommended), Units & preferences, Privacy & data (photo sharing, usage data, Download my data ZIP email se, Delete account 14 din), Help & about (FAQ, Report a problem screenshot ke saath, front desk, Terms), Notifications page (All / Unread, Mark all read + Undo, row sheet: Mark as unread, Delete + Undo), My activity (7 din, filters). Past date ka ya badla hua weight / measurement My activity me aaj ki line banata hai: "You changed measurements for Tue, 13 Oct" · "Chest 92 → 91.5 cm"; late log par "Logged on". Photo weeks (har 2 hafte, coach ka `photo_every_weeks`) me weekly check-in photos ke pehle **Body measurements** step poochta hai, wo Progress me khud save hote hain. Coming up, Next set due, Next measurements sab isi rule par.
- **Kyun:** Gautam: "aage ka karo pages"; "ye change ke log bhi pade"; decision cards "Client side now" (photos every N weeks) aur "Check-in me add" (measurements).
- **Updated:** backend accounts (prefs, ProblemReport), notifications (more kinds, own quiet hours, water / supplement reminders), checkins (photo weeks, measures step, private photos, change lines), clients/account.py + 4 endpoints, migrations accounts 0002, checkins 0004, notifications 0002, clients 0004, tests/test_client_more.py; app features/client/more/*, checkins_weekly / model, progress caption, router; docs behaviour §4.9 / §4.11, status, CURRENT, memory · Decisions D-23, D-24

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
