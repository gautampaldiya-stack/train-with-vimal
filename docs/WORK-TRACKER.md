# Work tracker — kitna hua, kitna baki

Probid ki poori list ek jagah. **Last updated: 2026-11-02** · branch `working`.
Isko har kaam ke saath update karo: kaam khatam hone par item **Remaining se Completed me** le jao
(ya uska mark ✅ karo) aur `changes.md` / `phases/CURRENT.md` me bhi likho.

Sahi context ke liye: [HANDOFF.md](HANDOFF.md) · [phases/CURRENT.md](phases/CURRENT.md) · [changes.md](changes.md) · [screens/status.md](screens/status.md)

## Mark ka matlab
| Mark | Matlab |
|---|---|
| ✅ | Ho gaya (code `working` par) |
| 🔧 | Abhi chal raha hai (kisi thread me coding ho rahi hai) |
| ◐ | Aadha ho gaya, baaki likha hai |
| ⬜ | Shuru nahi hua (code me nahi mila) |
| ❓ | Probid ka jawab chahiye |

Numbering Probid ki list jaisi hi hai (A–M ke item 1–80 ek chain me; N–S ke item 1 se).

## Ek nazar me (2026-11-02)
| Hissa | Total | ✅ | 🔧 | ◐ | ⬜ |
|---|---|---|---|---|---|
| Completed (1–11) | 11 | 11 | 0 | 0 | 0 |
| Remaining A–M (1–80) | 80 | 0 | 2 | 7 | 71 |
| N Package (1–9) | 9 | 0 | 0 | 0 | 9 |
| O Custom notification (1–3) | 3 | 0 | 0 | 0 | 3 |
| P Circuit (1–7) | 7 | 0 | 0 | 0 | 7 |
| Q Workout plan weeks/swap/copy (1–4) | 4 | 0 | 0 | 0 | 4 |
| R Check-in builder (1–9) | 9 | 7 | 0 | 1 | 1 |
| S Nutrition additions (1–3) | 3 | 3 | 0 | 0 | 0 |

(Item 12 of Completed khali tha; neeche "Incomplete notes" dekho.)

## Abhi chal raha hai (thread "Fix push notifications on mobile", 2 Nov)
Is thread me Probid ki 31 Oct wali list ka kaam chal raha hai:
- ✅ Food list crash (`Null is not a subtype of num`) fix — commit `04f8c8c`
- ✅ Swap ke baad Planned = coach ka portion, Set to default wahi — commit `491587e` (S1)
- ✅ Log something else (off-plan): ek-line rows, Ate it, Edit portion — commit `4095a7d` (S2, A5 ka hissa)
- ✅ Meal photos: pehle 4 tak photos (har ek remove), phir ek Mark as eaten (S3) — push ho gaya
- ◐ Check-in form builder — commit `4a78061`: number stepper ke beech type box, weekly me "Other" text field, admin Body measurements question (measurements chunna), photo "No photos this week" toggle, admin ke suggestion chips, koi auto-added question nahi (purane forms ke liye migration). Weight quick pick: Weight-tag wale number question par apne aap. Baaki R3–R8 settings neeche likhi hain.

- ✅ Toast ki jagah (2 Nov, screenshots): workout logger me toast mini bar se 10 upar (pehle tab bar ka 75 bhi juda tha, isliye bahut upar). Bottom sheet khuli ho to toast sheet ke theek upar, screen ke top par nahi (sheet bahut lambi ho tabhi top).
- ✅ Form builder "New question" modal: Cancel / Add question footer me fixed, modal 680 wide (2 Nov).
- ✅ Check-in builder ki baaki R settings (R3–R8), Probid OK 2 Nov. Sirf choice option ka icon baaki (R5).

## 3 Nov
- ✅ Scrollbar: patla, gol thumb, grey track nahi; list ke apne right gutter me (food list, past check-ins), rows / + buttons ke upar nahi.
- ✅ Log food list card: header (All foods / Recent / My foods + count), sab rows ek height, card ke kinare tak scroll.
- ✅ Meal photos: card ke header se photo hataya (neeche photo bar me hai), har photo par "+1" badge hataya.
- ✅ Swap sheet: planned food coach ki unit me ("1 cup"), pehle grams se pehli fit unit ("8 tbsp") ban jaati thi.
- ✅ Log food "Add to Snack" error (3 Nov, screenshot): Snack 4:30 pm se pehle band tha, app generic "highlighted fields" dikhata tha. Ab band meal kabhi default target nahi banta, Add par "Snack opens at 4:30 pm" aata hai aur chune foods bache rehte hain; har error toast me server ka asli reason. *(commit `5d7c57a`)*

### 3 Nov feedback (phone screenshot, 12:52)
- ✅ Water card: "Log water" button normal size (poori width nahi).
- ✅ Meal photos: koi bhi photo kholo to wahin se next / previous (swipe + teer), card, preview, photo bar aur "Did you eat" me.
- ✅ Today's calories sheet: Eaten / Left / Still ahead / Target / Protein / Carbs / Fat, ek row me 2, koi box nahi, beech me patli vertical line aur rows ke beech line; har value ke saath ek line ka matlab.
- ✅ This week card: chune din ki line ek hi line me (wrap/overflow nahi, chhoti ho jaati hai); neeche "This week" bold ke saath avg.
- ✅ Toast + bottom sheet: toast sheet ke asli top (screen par jahan sheet hai) ke theek upar, sheet ke title/buttons par nahi.
- ✅ Kal ka meal: aaj jaise saare options (photo ke saath Mark as eaten, Edit portions, meal menu, Log something different / Ate something else kal ke din me).
- ✅ Off-plan food add karte hi Eaten (Probid ne chuna 3 Nov): pending / "Ate it" / "Not logged yet" hata diya (migration 0011 field hatata hai).
- ✅ Water bhi meals jaisa: sirf aaj aur kal log hota hai, baaki din sirf dekhne ke liye (app + server).
- ✅ Week card ka naam chune din ke hafte se: "This week" / "Last week" / "Week of 19 Oct"; neeche avg wali line me bhi wahi naam.
- ✅ Today's calories ring me rang: plan ka khana neela, off-plan amber (pehle sirf ek rang).

- ✅ Mark as eaten (phone): sheet me meal ka naam, kitne foods aur kcal, phir 2 saaf options (photo ke saath / bina photo, har ek ki line). "Did you eat this?" me har group apne rang me (Will be logged neela, Already logged hara, Added outside the plan amber), bold heading + kcal, neeche bold Meal total.
- ✅ App icon: safed background par TWV logo (neela gola), pehle poora neela tha (Android adaptive icon regenerate).

- ✅ Edit portions (logged meal): sheet seedha khulti hai; "Change what is logged?" sirf Save par aur tabhi jab kuch badla ho (pehle kholte hi poochta tha).

- ✅ Water card: 3-dot ki jagah History (ghadi) icon, tap = seedha History. History: upar is hafte ka saar (avg/din, goal days, kul), phir har hafta alag card me (naam + tareekh), har din ka bar, upar litre, target pe hara, aaj ka din neela.

- ✅ "Did you eat this?": har food ke neeche protein · carbs · fat, aur Meal total (hamesha) me kcal ke saath kul protein · carbs · fat.

- ✅ Today's calories sheet me halka rang: har value ke aage rang ka dot (ring/bars jaisa), Eaten neela, Left hara (Over amber), Eaten aur Protein/Carbs/Fat ke neeche patla rangeen bar.

- ✅ "Preview this meal" behtar: upar bada kcal (plan se +/-), Protein · Carbs · Fat dividers ke saath; phir rangeen groups (Eaten from your plan hara, Skipped grey, Added outside the plan amber) har food ke macros ke saath; photos; Edit portion kal ke meal par bhi.

- ✅ "Swapped from …" ab apni alag line me (meal card aur preview), Edited badge ke paas kat ke "…" nahi hota.

- ✅ Ek tap = ek kaam (poore app me): koi bhi sheet, modal, menu ya photo viewer 2 baar tap par 2 baar nahi khulta; buttons aur icon buttons double tap par ek hi baar chalte hain. Steppers (+/−) pehle jaise baar baar chalte hain. Rule docs/rules me.

- ✅ Log food: logged meal (jaise Breakfast) me food add karne se pehle confirm "Breakfast is already logged — Add 2 foods to it? +268 kcal" (Other time par nahi).

- ✅ Log food: search ke neeche "Try: paneer · dal · roti · rajma" chips hata diye.
- ✅ Log food: Create custom food save karne par crash ("TextEditingController used after being disposed") fix; sheet poori band hone ke baad hi fields free hote hain.
- ✅ "Preview this meal": har food ka kcal ab ek seedh me right side (pehle har row me alag jagah).
- ✅ Water history naya design: upar halka blue summary (avg a day / X of Y days on target / this week); har hafta bina grey card ke, patle gol bars (blue, target par green), dotted target line, value sirf jis din paani piya, aaj ka din highlight; header "This week · 2–8 Nov" + "avg 1.75 L · 0 of 2 days"; purane hafte band, tap karke khulte; neeche key (3 L target / below target / target reached).
- ✅ Home water card ab Food page wala hi card hai (ek shared `WaterCard`): litres, glass bar, History icon, "Log water" → wahi sheet (din ka total ml). Water habit na ho to "not assigned".
- ✅ Habits & supplements page: water "Log water" sheet (sirf aaj/kal), steps/sleep me number tap karke type, tick habit aur supplement (Take / Undo / Took it) par Yes/No confirm — Home jaisa.
- ✅ Habits page cards (Day): ek chhoti line jo phone par poori dikhe (goal, ya progress; tick habit "Yes / no · tick it when done"), sab buttons ek jaise outline, "No streak yet" grey. Week: upar 2 tiles me rangeen % + "X of Y" + patla bar, best streak alag line.
- ✅ Water history (2nd round): upar Today / Yesterday tiles (litres / target, bar, tick), chaude bars (column ka ~60%), sirf This week khula, baaki hafte band par har din ka dot + total + avg + days; web par sheet chaudi (560).
- ✅ Home (phone) status bar: scroll karke blue hero upar chala jaaye to status bar ke peeche page ka rang aur kaale icon (pehle safed icon safed cards par gayab). Trainer Dashboard par bhi same (`HeroStatus`).
- ✅ Home workout card: "See all" (aur "+ N more · See all") Train page kholta hai, usi din par (`/train?date=`).
- ✅ Other time sheet: "Now" / "30 min ago" tap ke waqt ki ghadi lete hain (sheet kab khuli usse nahi).
- ✅ Other time sheet: "Use this time" sirf tab chalta hai jab time poora aur sahi ho (ghanta 1–12, minute 00–59, aage ka nahi); warna button off.

Rule (Probid 3 Nov): aise chhote naye changes bhi yahan likhne hain, chahe REMAINING list me na hon.

Probid ka rule (2 Nov): abhi screenshot nahi lena, mobile par try nahi karna. Sirf code, `flutter analyze` aur backend tests; test Probid karenge.

## Decisions (confirmed)
- **Cardio:** KM poora hata do. Sirf BPM. KM ka migration nahi chahiye.
- **Rest timers:** Admin lock/set kar sakta hai. Client workout ke dauran badal sakta hai. Admin ko planned rest vs actual rest dikhna chahiye.
- **Water target:** Sirf admin set karega. Client edit nahi kar sakta.

---

## ✅ COMPLETED

1. **Media / Onboarding images:** onboarding preview (Finish se pehle) me images nahi dikh rahi thi. `.env` variable add karke fix. *(Phase 2, commit `08dc22a`)*
2. **Nutrition (Train): food aur photos**
   * Har food skip ho sakta hai, uska portion edit ho sakta hai.
   * "Ate it" option food ko eaten mark karta hai.
   * Ek meal me kai photos. Photo select karne par photo card add hota hai, thumbnails upar dikhte hain. Thumbnail tap = preview. *(Phase 3, `d25ced6`)*
3. **Nutrition (Train): confirmations** — meal log karna, single food par "Ate it", meal unlog karna. *(`d25ced6`, `28e54a1`)*
4. **Nutrition (Train): "Daily target" hata diya.** Today's card me planned food vs consumed dikhta hai. *(`28e54a1`, D-86)*
5. **Nutrition (Train): meal timing**
   * Upcoming meal abhi log nahi hota. Meal time se 30 min pehle khulta hai.
   * Meal unlog ho sakta hai.
   * Meal ka time aane se pehle edit nahi hota. *(`28e54a1`, D-86)*
6. **Log Food page**
   * Food tap karke portion set, phir select.
   * Neeche button "Add n food to {meal}".
   * Unsaved changes ke saath bahar jaane par poochta hai: meal me add ya discard.
7. **Home:** cards rearrange (drag & drop), remove aur add. *(Phase 6, `9f2761d`, D-87)*
8. **Home:** "Daily Check-ins" card quick fill ke liye. *(`9f2761d`)*
9. **Home:** "Progress" card (weight, body fat, muscle, strength) aur "Weekly Adherence" card. *(`9f2761d`, `89658d4`)*
10. **Mobile navigation**
    * Main tabs (Train, Food, Progress, More) par back se app band nahi hota. "Do you want to exit?" poochta hai.
    * Baaki pages back par Home jaate hain.
    * Main tabs par status bar (time, battery, network) ab saaf dikhta hai. *(Phase 4 `d5df1ba`, Phase 5 `d0d47d1`)*
11. **Train page:** week strip me sirf date (day name hata). Bodyweight aur kg tabs hata diye. Existing toggle rakha. *(`9f2761d`)* — dhyaan: neeche "Incomplete notes" me day name wala sawal.

---

## 🔧 REMAINING

### A. Nutrition (Train page) — ✅ sab ho gaya (3 Nov), Probid ka test baaki

1. ✅ Bottom navbar tab hidden rahe jab koi bhi bottom sheet khula ho.
2. ✅ Today's calories sheet: Left / Still ahead ek hi tarah round (1958 = 1958), har line ka matlab sheet me likha, "Got it" hataya, target coach ka.
3. ✅ Edit portion (meal level): decimal type karte hi save (pehle sirf blur par), photo delete par "Delete this image?", logged meal ki photos foods ke neeche (thumbnails + count, tap = view), log ke baad change/remove options gayab.
4. ✅ Ek food ya poora meal skip karne par confirmation.
5. ✅ Off-plan (bahar ka) food
   * ✅ Today's calories card me rangeen bar: Plan, Off-plan, Skipped.
   * ✅ Off-plan foods meal me normal foods jaise, "Off-plan" tag ke saath.
   * ✅ Off-plan portion edit aur entry delete.
   * ✅ Badla (3 Nov, Probid): Log Food se add kiya food turant Eaten aur gina jaata hai (client wahi add karti hai jo kha chuki). Pehle wala "pending / Ate it" hata diya.
   * ✅ Meal card: extra foods ka +kcal sirf gine hue foods ka.
6. ✅ Mark as eaten confirmation: Will be logged / Already logged / Added outside the plan, aur photos.
7. ✅ Logged meal preview: "Preview this meal" (Logged · Undo ke saath), foods tap nahi hote, preview me foods, totals, photos, "Edit portion" → sheet me "Edit & Log" aur "Cancel".
8. ✅ Yesterday logging: week strip me pichhla hafta (swipe), Monday ko last Sat-Sun dikhte hain. Kal ka chhoota meal "Log this meal for yesterday". Usse purane din sirf dekh sakte hain.
9. ✅ "This week" card: Monday ko last Sat-Sun bhi (halke), average sirf is hafte ka, chune din par kcal, protein aur meals logged.
10. ✅ Water card: water habit nahi to "Water habit is not assigned to you yet" (log bhi nahi hota). "Log water" button → sheet (− / ml / +, value tap karke type). 3-dot → History (is hafta + pichhle 3). Us din ka water saaf, target coach ka (habit target, warna plan), client edit nahi karta.

### B. Log Food page — ✅ sab ho gaya (3 Nov), Probid ka test baaki

11. ✅ "Other" time sheet: stepper hata diya. Ghanta (1–12) : minute (00–59) ke 2 box, AM/PM switch; galat number par laal line, aage ka time ho to "Use this time" nahi chalta. Now / 30 min ago chips rakhe.
12. ✅ Create custom food: Cancel/Save par error. Wajah: sheet ke text box sheet band hote hi dispose ho jaate the, jabki band hone ka animation chal raha hota tha. Ab sheet apne box khud rakhti hai (`showAppSheet(owns: …)`) aur sheet poori hatne ke baad hi free karti hai. Other time sheet bhi isi tarah. Widget test `test/food_sheets_test.dart`.
13. ✅ Food list UI: list aur upar ki added-food list behtar karo. Saare items same height, theek se arranged. Back-press confirmation me buttons chhote. *(crash fix `04f8c8c`; 3 Nov: list card header, same-height rows, scrollbar ✅; upar ki added-food list ✅: har row same height, naam + amount/protein, kcal right side ek column me, chhota remove button, group heading me ginti aur kcal; back-press confirm ke buttons chhote ✅)*

### C. Home page — ✅ sab ho gaya (3 Nov), Probid ka test baaki

14. ✅ Weekly Adherence: pehle sirf daily check-in ginta tha (Mon→aaj). Probid ne option 1 chuna (3 Nov): Mon se ab tak workouts + meals + daily check-in + habits, jo plan tha usme se kitna hua, sab barabar weight. Aaj sirf jo due ho chuka (meal ka time nikal gaya) ya ho gaya. Card me bada %, "X of Y done so far" aur 4 lines (Workouts / Meals / Check-ins / Habits). Coach ka adherence bhi isi rule se (pichhle 7 poore din). `metrics.plan_adherence`, test `tests/test_plan_adherence.py`.
15. ✅ Habits card (Water habit → "Log water" = Food jaisi sheet, total ml type bhi; Steps/counter aur Sleep me number tap karke type, sleep "7:30" / "7.5"; tick habit par Yes/No confirm dono taraf)
    * Habits se logging: har habit ke liye bottom sheet.
    * Water ke liye Nutrition water card jaisi hi sheet.
    * Sleep aur Steps sheets: stepper value tap karke editable text field (manual entry).
    * Tick habits par Yes/No confirmation.
16. ✅ Supplements: Take aur Taken (undo) dono par Yes/No confirm.
17. ✅ Food card (Ate it → `/food?meal=<id>`, Food page us meal par scroll + thodi der ring; Up next: time/opens chip, naam, kcal, foods, macros, aaj ke meals ke dots "2 of 4 logged"; header me Log food ki jagah See all)
    * "Ate it" tap = Nutrition page khule aur relevant meal par scroll kare (jaise snack time par Snack card).
    * "Up next" section behtar karo.
    * "Log food" button hatao.
18. ✅ Workout card: pehle 3 exercises numbered card par hi (naam + sets line), "+ N more · See all", shuru hua workout ho to "X of N exercises" bar aur ho chuke par hara tick; future din ka alag See all button hata diya.

### D. Progress / More / Notifications

19. ✅ Progress: Workouts stat card (Waist aur Bench best ke beech) samajh nahi aata. Meaningful details dikhao. → Har tile me value + ek line: Waist "−X cm since start" (kam hua to hara), Workouts done "This week X of Y", Bench best "Heaviest set so far".
20. ✅ More, Account section: "Notifications" aur "Notification settings" hatao (bell already notifications kholta hai). Client ke liye "Unit & Preferences" ki zaroorat nahi. → Ab sirf Privacy & data, My activity (phone), Help & about. Notification settings Notifications page ke gear se.
21. ✅ Notifications page: delete notification option hatao. → Notification sheet me sirf "Mark as unread" aur link button.
22. ✅ More, Trainer details sheet: trainer photo left, details right, extra details neeche. → Title "Your trainer"; left 84 px photo (na ho to initials), right naam, "Your trainer since", program, speciality chips; neeche About, Works best with, Experience/Languages/social (sirf jo trainer ne 'What clients see' me on kiya), Certificates, phir Your plan rows. Backend account coach payload me photo + public card. Round 2 (Probid: ache se arrange karo, design normal): upar grey header box (photo 76 px left; naam, since, "X yrs experience · languages", speciality chips right), phir alag white sections About (about + Works best with), Your plan, Certificates (tick ke saath), Contact (mobile/email/social). Har section me label left, value right, same spacing.

### E. Check-ins (Client)

23. ⬜ Check-in page cards
    * Top card: saaf details, equal height. Neeche ke cards bhi.
    * Daily Check-in card: admin ka description aur details. Card ke andar sawal nahi.
    * Weekly Check-in card: same saaf layout.
    * Weekly check-in button sirf due day par enabled. Us din "Due today".
    * Complete nahi hua to din me 2-3 baar reminder, 2-3 din tak. Uske baad Missed mark karo aur agla dikhao. Fill sirf due day par.
24. ⬜ Past Check-ins: kala scrollbar dikhta hai, hatao. Detail bottom sheet theek se arranged.
25. ⬜ Questions: koi default question nahi. Sirf admin ke chune sawal, har type ke hisaab se sahi answer input. Daily check-in ke neeche "water intake" line hatao.
26. ⬜ Header: mobile par subtitle kat jaata hai. Bina wrap ke aur bina lambe header ke theek se dikhao.
27. ◐ Daily check-in card *(31 Oct: sent hone par ek line "Sent ✓ · time", weight sawal ka naam form wala; baaki baaki)*
    * Data kal ka hai chahe aaj bhara jaye. Saaf likho: "Log yesterday's data (Oct 26)".
    * Detailed lekin compact. Admin ka description ho to dikhao.
28. ◐ Weekly check-in card *(31 Oct: weekly ab ek list me saare sawal, same-day edit, `fed2bf5`)*
    * Tag/badge chips hatao.
    * Next due date check-in schedule se aaye, last weight log se nahi.
    * Sirf scheduled din par enabled.
29. ⬜ Measurement logs
    * Weight aur measurement due dates weekly schedule ke hisaab se. Log ke baad next due date dikhao.
    * Measurement tap = past logs ki sheet: date, value, pichle se change.
    * Wahan stepper hatao, plain numeric field.
30. ◐ Daily check-in bugs (har ek ka root cause dhundho)
    * ◐ Single/multiple choice par "Other" configured hai par dikhta nahi. Dikhna chahiye aur free text lena chahiye. *(weekly me ✅ `4a78061`; daily me check karna)*
    * ⬜ Duplicate questions ("Morning weight", "Anything else"). Karan dhundho (duplicate rows, duplicate form assignment ya template). Sirf configured sawal dikhao.
    * ⬜ Submit error. Logs me dhundho, fix karo, regression test.
    * ⬜ Daily check-in dikh nahi raha. Form assignment, schedule aur automation verify karo. Automation na ho to banao.
31. ⬜ Partially completed onboarding
    * Check-in page "0 questions filled" dikhata hai chahe kuch answered hon. Count fix karo.
    * Resume original onboarding jaise same single-page layout me.
    * Bahar nikalne par progress dikhao ("You have completed 4 of 12 questions") aur Continue / Save and do it later.
32. ⬜ Unsaved check-in exit: adhoora weekly ya daily check-in chhodne par "You have not finished this check-in. Save and continue later, or discard?" aur buttons Save and continue later / Discard. *(app me "Draft saved" back-par kuch hai, poora spec check karna)*

### F. Workout Logger (Strong app design aur layout)
*(Dhyaan: 28 Oct ka pichla logger kaam (D-75, rest D-79 etc.) rollback me hataya gaya, sirf backup bundle me hai: `/mnt/project-files/backup-oct28/`. Wapas lana ya naya banana Probid decide karega.)*

33. ⬜ Layout aur behavior
    * Neeche swipe = logger mini bar me collapse (kabhi band nahi hota). Bar tap ya upar swipe = wapas khule.
    * Mini bar me workout timer aur current exercise.
    * Logger khula ho (expanded bhi) to bottom navbar hidden, main tab par wapas aaye.
    * Expanded me back = mini bar me collapse. Workout end nahi.
34. ⬜ Timer
    * Bug: timer logger khulte hi shuru hota hai (workout start par nahi) aur logger chhodte hi ruk jaata hai.
    * "Start workout" par shuru, sirf workout active hone tak chale.
    * Collapse, back ya app switch par na ruke.
    * Start timestamp persist ho, app restart ke baad bhi.
    * Active rahte ongoing notification (Android ongoing, iOS Live Activity jahan ho) — existing notification setup se: elapsed time, current exercise, set progress ("Set 3 of 5 done"). Tap = logger.
    * Finish ya reset par notification hatao. Agla workout zero se.
35. ⬜ Finished workout aur aur sets add karna
    * Finished workout dobara khol ke sets add karne par naya segment timer zero se. Original total restart nahi.
    * Time per exercise per session store: original sets aur har baad ka addition alag.
    * Sahi total sab jagah (exercise card, summary, history), breakdown ke saath. Example: 12 min + 4 min = 16 min.
36. ⬜ Set entry
    * +/- stepper hatao. Weight aur reps ke liye plain numeric fields, numeric keyboard, weight me decimals.
    * Placeholder propagation: set N me weight likho to N+1 se aage placeholder me dikhe. Upar ke sets par asar nahi. Placeholder ya tick tap = confirm. Reps ke liye bhi jahan sahi ho.
    * Test: 5 sets x 5 reps. Set 2 me 60 likho to sets 3–5 ke placeholder 60. Set 1 same.
    * "+ Add Set" text button (filled ya outlined nahi).
    * Completion tick turant volume, total reps, total time update kare.
37. ⬜ Previous column
    * Har set row me us exercise ke pichle session ke same set number ka weight aur reps ("60 kg x 8").
    * Tap = us set ka weight aur reps fill, aur wo Previous value disabled/light grey.
    * Divergence rule: weight ya reps Previous se alag kar do to Previous wapas dikhe (grey nahi). Original previous values stored rahein.
38. ⬜ Set number menu: set number tap = Use last time (pichle session se saare sets), Bodyweight, Set type (Drop set shamil), Rest timer for this set.
39. ⬜ Drop set (Strong ka exact UI screenshots se confirm karo)
    * Drop set, set menu me ek set type hai.
    * Drop set = main weight + ek ya zyada drop weights, har ek ke reps. Strong ka structure (agar Strong har drop ki alag row banata hai to wahi).
    * Drop rows visually grouped ya marked (jaise "D").
    * Set count aur volume me ginti.
40. ⬜ Focus metric: chuna hua metric exercise ke 3-dot menu ke paas dikhe aur menu se editable. 3-dot menu me Focus metric aur Rest timer dono.
41. ⬜ Form video (per set)
    * Har set par video (ya Strong per exercise karta hai to wahi, confirm karo).
    * Sirf workout finish par submit.
    * App chhod ke wapas aane par selected video bana rahe.
    * Submit se pehle change ya remove ho sake.
    * Finish screen batae kis exercise aur set me video hai, confirmation ke liye.
42. ⬜ Cardio (KM ki jagah BPM) *(code me abhi `distance_km` hai: `backend/apps/training/models.py`)*
    * KM field hatao, BPM lagao.
    * Admin plan builder me har cardio exercise ke liye target BPM range (min, max) set kare. Client ko us exercise par range dikhe.
    * Client jo BPM mila wo log kare.
    * Admin target vs actual saath me dekhe jahan bhi exercise aaye: client workout detail, history, activity feed detail.
    * Cardio volume me nahi ginta.
    * Purana KM data nahi rakhna. Sirf BPM.
43. ⬜ Exercise edit drawer
    * Bug: drawer me sets field badalte hi peeche ka exercise turant badal jaata hai.
    * Drawer ke changes draft me rahein. Exercise sirf Done tap par badle.
    * Done ke bina band (back, neeche swipe, bahar tap) = draft discard.
    * Done ke baad exercise aur totals turant update.
    * Notes field ke neeche ka divider hatao.
    * Har screen par jahan ye drawer use hota hai.
    * Root cause batao (expected: drawer inputs live exercise state me seedha likhte hain, local draft me nahi) aur regression test.

### G. Rest Timer (per exercise, per set type)

44. ⬜ Exercise 3-dot menu me "Rest timer" option (Strong jaisa).
    * Working, Warm-up aur Drop sets ke alag durations, minutes:seconds me enter, seconds me store.
    * Current workout ke current exercise par lage aur us exercise ke agle workouts ka default ban jaye, jab tak badla na jaye.
45. ⬜ Per-set rest timer
    * Set number menu ka "Rest timer for this set" sirf us set ka rest.
    * Set row ke neeche dikhe, edit ya remove ho sake.
    * Per-set value exercise default ko override kare.
46. ⬜ Swipe management
    * Set row par left swipe = delete: undo snackbar, ya set me data ho to pehle confirm.
    * Rest timer row par left swipe = delete.
    * Rest timer row tap = duration editor.
    * Smooth animations.
47. ⬜ Admin-defined rest timers: plan builder me set, client logger me dikhen. Admin lock kar sakta hai. Lock na ho to client workout me badal sakta hai, aur admin planned vs actual rest dekh sake.
48. ⬜ Rest sheet (workout ke dauran) (Strong jaisa)
    * Set complete par, us set ke liye rest duration ho to timer apne aap shuru.
    * Sheet navbar ke upar neeche: bada countdown, bada saaf Pause, Reset, Skip, +15 s, -15 s, aur chhupane ke liye X.
    * X UI chhupata hai, timer background me chalta rahe.
    * Rest khatam = timer finish aur sheet band.
    * Home ya dusre page par jao to timer chale aur chhota rest indicator dikhe. Tap = sheet wapas.
    * Rest state persist, rest period ke andar app restart par bhi.
    * App background me ho to shade me rest-finished notification (existing notification setup).
49. ⬜ History me rest data: har set ka actual rest store, sirf planned nahi (planned 2:00, actual 1:45 agar jaldi skip). History aur workout detail me planned vs actual.
50. ⬜ Sound aur haptics: set complete aur rest finish par. Device silent mode ka respect. Settings me sound aur haptics toggles.

### H. Workout Edit aur Timing

51. ⬜ Complete hua workout usi din dobara khol ke edit ho sake. Changes nayi version ke roop me save.
52. ⬜ Editable: exercises, sets, weight, reps, set type, rest timers, start aur end time.
53. ⬜ Start/end badalne par duration aur saari dependent stats recalculate.
54. ⬜ Client History page se bhi edit kar sake.
55. ⬜ Finish ke baad add kiye sets alag timed segment. Total exercise time = session time + addition.
56. ⬜ Client ka har edit admin ko dikhe (client profile: workouts aur activity).

### I. History aur Exercise Details

57. ⬜ History
    * Existing day bottom sheet us din ki history full page jaisi detail ke saath dikhaye.
    * Saare past workouts aur meals ke liye alag History page. Ooonchi rows (Strong jaisi): date, workout name, duration, volume, sets.
    * Title ke right me calendar icon = calendar. Completed workouts wale din marked, tap = us din ki sheet.
    * Day sheet: saare exercises, har set ka weight, reps, rest taken, set type, jahan relevant Previous. Total volume aur total time. Cardio me target BPM range aur actual BPM.
    * Bodyweight sets par us waqt record hua body weight: "BW (72 kg)".
    * Rest: har set ka planned aur actual.
58. ⬜ Accuracy checks (test data se verify, galat value ka root cause): session volume, session duration (added sets samet), rest taken vs planned, per-exercise totals, bodyweight sets par body weight. *(Phase 1 shared calc module `apps/common/calc.py` D-82 ban chuka hai, volume rule ek hai)*
59. ⬜ Exercise details (client mobile)
    * Tabs screenshot ki bottom sheet jaisi style me: Overview, History, Records.
    * History: us exercise ke saare past sessions (date, sets, volume). Tap = session details.
    * Records: sabse bhaari weight, best session volume, kisi weight par sabse zyada reps, har ek ki date ke saath.
    * Admin aur trainer client profile me yahi History aur Records dekhein.

### J. Habits aur Logging Modals

60. ⬜ Step/tick habits (jaise Sleep steps): tap = manual entry field wali sheet. Aise sab habits ke liye same pattern.
61. ⬜ Water: +/- ya quick-add, phir Save se commit (har tap par save nahi). Saved total dikhao.
62. ⬜ Water target: admin client profile par set kare aur client ke water card par dikhe. Client edit nahi kar sakta. *(code me `water_ml` hai `backend/apps/nutrition/models.py:112`, par admin-only edit verify nahi)*

### K. Onboarding (Client)

63. ⬜ Continue dabane par agle step ke top par scroll.
64. ⬜ Har sawal ko number do (1, 2, 3...).
65. ⬜ Required sawal unanswered ho aur Continue dabao to pehle unanswered sawal par scroll aur focus.
66. ⬜ Submit "I agree" tick hone tak disabled, tick karte hi turant enable.
67. ◐ Yahan select ki images fixed pipeline use karein aur step preview me dikhein. *(Completed 1 wala `.env` fix, `08dc22a`; step preview me dobara check karna)*
68. ⬜ Naye user ko jiska plan nahi, abhi water card aur daily/weekly check-ins dikhte hain. Ye sirf tab dikhein jab enabled ho (client profile toggles aur plan editing).

### L. Progress aur Comparison

69. ⬜ Week-by-week comparison: do ya zyada weeks chuno, adherence, weight, measurements, workouts, volume, duration, sets compare. *(pichla D-74 "Progress Week by week" rollback bundle me)*
70. ⬜ Per-exercise comparison (jaise Bench Press is hafte vs pichle hafte).
71. ◐ Home progress card wahi data source use kare. *(Home Progress card tabs `89658d4` Progress page ke numbers se; comparison ke saath jodna baaki)*

### M. Admin Panel

72. ⬜ Client profile toggles aur plan editing
    * Toggles: Daily check-in, Weekly check-in, Water habit.
    * Plan assign karne par plan se defaults. Admin client ke hisaab se override kar sake.
    * Client ko card ya habit tabhi dikhe jab uska toggle on ho.
    * Client profile se "Edit plan" kaam nahi kar raha tha (report). Verify, root cause, fix.
73. ⬜ Client profile: workouts aur activity
    * Workout list: date, duration, volume, change hua to "Edited" badge.
    * Workout kholne par poori details, edit history, cardio target vs actual BPM.
    * Client ka har workout ya meal edit audit entry banaye: kisne, kya badla, purani value, nayi value, timestamp.
74. ⬜ Exercise history aur records: mobile ke History aur Records tabs client profile me, shared module se taaki numbers match.
75. ⬜ Plan builder
    * Rest timers: admin har exercise aur har set type (working, warm-up, drop) ke liye rest set kare. Plan ke har set ka apna timer ho sakta hai jo exercise default ko override kare. Admin set par extra timer jod sake (jaise drop ke baad doosra rest).
    * Cardio: admin har cardio exercise ka target BPM range set kare.
    * Verify: ye sab plan banate waqt aur client ke maujooda plan ko client profile se edit karte waqt bhi set ho, sirf global template me nahi.
76. 🔧 Onboarding aur form builder *(form builder thread me kuch hissa chal raha; D-88 Progress tag ho chuka)*
    * ⬜ Publish ke baad edit: clients ke answer dene ke baad bhi admin question text, type, options edit kar sake. Purane answers stored aur linked rahein. Edit existing answers ko affect kare to warn karo.
    * ⬜ Options builder: options ek ek karke, har ek ka required title, optional subtitle/description, optional icon (choice questions).
    * ⬜ Question types fixed. Admin sirf answer options add, edit, remove, reorder kare.
    * ⬜ Yes/No conditional logic: admin Yes aur No ke liye follow-up questions chune. Abhi toota hai, fix karo.
    * ⬜ Selection par hint: option select hone par uska hint dikhe, client view jaisa.
    * ⬜ Admin preview answers client jaise dikhaye, pehle onboarding question ka layout bhi.
    * ⬜ Dependent questions (jaise weight aur goal weight): numeric values numerically compare ("5 kg to lose"). Baaki types ke rules plan mode me propose karo.
    * 🔧 Number question type (check-in builder): do modes, Field ya Stepper, dono me optional min/max. Field: seedha entry, configurable max digits (jaise phone number ke liye 10). Stepper: range ke andar, type bhi ho sake.
    * ⬜ Layout: question list scroll kare jabki left aur top navigation fixed. Meal builder me right side card fixed, meal-time cards scroll.
77. ⬜ Activity feed
    * Item tap (workout, meal, check-in, admin/trainer change) = detail sheet: workout (exercises, sets, weights, reps, time, cardio BPM), meal (foods, quantities, meal time), daily check-in (answers, date), change (kya, purani se nayi value, kisne).
    * "View client" link relevant tab par client profile kholta hai.
    * Admin aur trainer ke changes log hon aur feed me editor ke naam ke saath dikhein.
78. ⬜ Invite link: har trainer ka apna link (abhi sirf Aman ka dikhta hai). Client reassign hone par links follow karein. *(pichla D-70 rollback bundle me)*
79. ⬜ Nutrition (meal plan)
    * Create-plan modal: target field hatao. Targets added foods se calculate hon.
    * Har meal aur har din ke totals: calories, protein, carbs, fat.
    * "Client on this plan" card calculated totals dikhaye.
    * List cards equal height. Meal-time badges jitne fit hon utne, phir "+N".
    * Water target client profile par set ho aur client ke water card par dikhe.
80. ⬜ Admin se client/trainer tak reflection: admin ya trainer ka koi bhi change (plan, rest timers, cardio range, habits, check-ins, nutrition, targets) client app aur trainer view me agle load ya live update par dikhe. Test se verify: admin me change, dono me check.

### N. Package ("Plan" tab ki jagah, admin me)

1. ⬜ "Plan" tab ka naam "Package" har jagah (labels, routes, client profile). *(dhyaan: code me packages D-55 se hidden/commented hain, ye naya spec hai)*
2. ⬜ Package me bundle: meal plan, workout plan, habits, supplements. Client ko sab kuch sirf package ke through assign.
3. ⬜ Package ki duration.
4. ⬜ Status flow: Draft → Scheduled → Active → Ending soon → Completed.
   * Naya package default Draft (kisi ko assign nahi).
   * Future start date ke saath assign = Scheduled.
   * Start date se: Active (Scheduled nahi dikhna).
   * End date se 15 din ke andar: Ending soon.
   * End date ke baad: Completed.
5. ⬜ Start date assign karte waqt set. Services (meals, workouts, habits, supplements) us date se shuru, pehle nahi. Example: package aaj bana, 1 Jan ko assign = services 1 Jan se shuru, wahi package start date. Package apna date range (start se end) dikhaye.
6. ⬜ Assign drawer:
   * Client aur start date.
   * "Notify client" toggle. On ho to client ko notification: "Your plan starts on {date}".
   * Service type (weight gain, weight loss, etc.).
   * Amount paid aur payment date.
7. ⬜ Expiry alert aur reminders: package khatam hone se 15 din pehle admin ko alert, phir 10 din aur 5 din par reminders. 10 din pehle se package "At risk / Action required" me bhi dikhe (admin Clients page aur Dashboard dono par) aur client profile me.
8. ⬜ Client ko package ke cards aur habits sirf start date se dikhein.
9. ⬜ Migration: maujooda assigned plans apne aap packages me convert (best effort). Har client ka current plan uski maujooda start date ke saath Active package. Jo convert na ho sake uski report.

### O. Custom Notification (client profile)

1. ⬜ Client profile me naya tab: "Send notification".
2. ⬜ Admin/trainer title aur message likh ke us specific client ko bheje.
3. ⬜ Pehle bheji notifications ki list (date, title, message).

### P. Circuit Exercise Type

1. ⬜ Exercise type options me Cardio ke saath "Circuit".
2. ⬜ Admin plan builder me circuit banaye:
   * Circuit name aur exercises ki ordered list.
   * Har exercise: target reps (ya duration) aur optional target weight.
   * Rounds ki ginti.
   * Exercises ke beech rest (default 0) aur rounds ke beech rest.
3. ⬜ Client logger:
   * Circuit ek grouped card me, andar exercises ki list.
   * Client har exercise, har round ke reps/weight (ya duration) log kare.
   * Round ke saare exercises tick hone par round apne aap complete.
   * "+ Add round" extra round jodta hai.
   * Har round ke baad (aur set ho to exercises ke beech) rest timer apne aap, existing rest sheet se.
4. ⬜ Volume: circuit ke weight wale exercises ka weight x reps volume me. Bodyweight aur duration-only nahi.
5. ⬜ Time: circuit time workout timer ke neeche, per round track.
6. ⬜ History aur admin: rounds, har round me har exercise ke reps/weight, planned vs actual rest.
7. ⬜ Is file ke Strong-style rules ke saath chale (Previous column, rest timers, finished workout edit).

### Q. Workout Plan: Weeks, Swap, Copy (Admin)

1. ⬜ Week-wise view aur edit: workout plan dekhte ya edit karte waqt admin har week alag dekhe aur koi bhi week edit kare. Global template aur client ke apne plan (client profile se) dono me.
2. ⬜ Past plans se import: admin past workout plans se exercises chun ke current plan ya week me jod sake.
3. ⬜ Swap days: admin do din ke exercises swap kare (jaise Saturday workout aur Sunday rest = Saturday rest aur Sunday workout). Hafte ke koi bhi do din, rest days samet. Sirf current week ke liye one-time change, baaki plan same. Abhi sirf admin.
4. ⬜ Copy week: abhi week sirf agle week me copy hota hai *(code me bhi sirf N → N+1: `builder_model.dart`)*. "Copy week to..." jodo taaki admin koi bhi specific week (ya kai weeks) destination chune. Destination me data ho to overwrite se pehle confirmation.

### R. Check-in Builder: Admin/Trainer jo client dekhta hai wo banate hain

1. ✅ Admin aur trainer weekly aur daily check-in ke sawal, client jitne question types aaj dekhta hai un sab se bana sake.
2. ✅ Weekly check-in ka hardcoded aakhri sawal hatao. Saare sawal sirf builder se. Zaroorat ho to admin normal sawal ki tarah jode.
3. ✅ Number question: Field ya Stepper (dono optional min/max ke saath). Stepper mode me beech ki value editable text field.
4. ✅ Quick pick (jaise weight) *(builder me on/off + step; weight question me last weigh-in se, baaki me client ke pichhle jawab se)*: Number question ki setting. On ho to client ki last logged value ke aas-paas chips (jaise last 72.4 kg to 72.0, 72.2, 72.4, 72.6, 72.8). Admin on/off kare aur step set kare (jaise 0.2 kg). Client chip tap kare ya alag value type kare.
5. ◐ *(Probid 2 Nov: style ka option nahi, question ke hisaab se apne aap; subtitle ✅; option ka icon baaki)* Single/multiple choice display style, admin har sawal par chune:
   * Cards: bade boxes jisme title, subtitle aur icon.
   * List/Chips: compact.
   * Default compact jab options me subtitle ya icon na ho.
6. ✅ *(weekly; builder ka toggle pehle se tha)* Choice questions par "Allow Other" toggle. "Other" text field kholta hai aur type kiya text save hota hai.
7. ✅ Body measurements question type *(cm/in unit, har row Required)*
   * Admin chune kaun si measurements dikhein (chest, waist, hips, etc.), unit, aur har field required ya optional.
   * Client ek card me dekhe.
8. ✅ Photos question type
   * Admin photo slots set kare (front, side, back) aur required ya optional.
   * Admin "No photos this week" checkbox on/off kar sake.
9. ⬜ Admin preview har sawal bilkul waisa dikhaye jaisa client dekhta hai.

### S. Nutrition Additions

1. ✅ Plan foods ka default portion: trainer ne jo diya (jaise 120 g), food ka apna default serving nahi. Log, Edit portion aur Mark as eaten me. Real numbers se test (assign 120 g, default 120 g dikhe). *(swapped food ka Planned aur Set to default coach ke portion par, `491587e`. Log aur Mark as eaten me bhi 120 g wala test dobara dekhna.)*
2. ✅ "Something else" food (Log Food page se add hone wala off-plan food jaisa hi):
   * "Ate it" option details ke saath.
   * Edit portion.
   * Rows meal ke andar ke foods jaisi line-wise list (stacked cards nahi). *(`4095a7d`)*
3. ✅ Photos: Mark as eaten se pehle client ek ke baad ek kai images same card me add kar sake (4 tak, har ek remove ho sakti hai). *(push ho gaya)*

### T. History page (Probid 3 Nov, sabse last me)

1. ⬜ History page par har cheez ka saaf sheet preview. Tap karne par bottom sheet me poori detail (jaise Food ka "Preview this meal"):
   * Meals: foods, portions, macros, photos.
   * Workout: exercises, sets, volume, time.
   * Supplements aur habits: kya kiya, kab, kitna.

---

## Incomplete notes (aapka input chahiye)

* ❓ **Completed item 12:** khali chhod diya tha. Kya likhna tha?
* ❓ **Remaining Nutrition item 4:** "jab hum food ko..." par sentence kat gaya tha. Poora sentence bhejo. (Abhi: ek food ya poora meal skip par confirmation maana hai.)
* ❓ **Remaining Nutrition item 10:** khali chhod diya tha (Water card ka point likha hai, par numbering me 10 ke baad kuch khali tha?). Kuch aur add karna ho to batao.
* ❓ **Train strip (Completed 11):** is list me "sirf date, day name hata" likha hai. 28 Oct ko aapne kaha tha "day name date ke saath dikhao, 'beach day' jaise labels hatao", aur 30 Oct ka code (D-87) weekday + date dikhata hai. Kaun sa chahiye?

## Code se cross-check (2026-11-02)
Remaining me ye pehle se (aadha) code me mila:
- A5 / S2: off-plan rows, Ate it, Edit portion (`4095a7d`).
- S1: swapped food ka portion coach wala (`491587e`).
- Item 13: crash fix hua (`04f8c8c`), UI polish baaki.
- Item 27, 28: Home sent card aur weekly list/same-day edit (`fed2bf5`).
- Item 67: onboarding images ka `.env` fix (Completed 1).

Remaining me ye **abhi code me nahi** hai (`bpm`, `Circuit`, `Swap days`, `Send notification`, `Ending soon`, `Preview this meal`, `quick_pick` ke liye grep khali):
- Cardio abhi bhi `distance_km` rakhta hai (item 42).
- Rest timer sirf exercise ka `default_rest_seconds` / set ka `rest_seconds`; per-type, per-set, actual rest nahi (G).
- Copy week sirf N → N+1 (Q4).
- Invite link per trainer (`is_main`) nahi (item 78).
- Packages D-55 se hidden hain, naya Package spec bana nahi (N).

## Rollback ka asar
28 Oct ko `working` ko `develop` (`4ccacdd`) par wapas kiya gaya. D-61 … D-79 ka kaam (logger D-75, rest D-79, activity detail D-69, invite links D-70, meal-plan totals D-71, form config D-68, Progress weeks D-74, dark theme D-78, ...) sirf `/mnt/project-files/backup-oct28/working-before-rollback-d059df1.bundle` me hai. Jo items upar ⬜ hain par pehle bane the, unhe bundle se wapas laya ja sakta hai (Probid ki haan par).

## Park ki hui cheezein (jab tak Probid na bole mat banao)
Daily summary design · Gym news admin screen · client brand colour / dark theme · phone health data · WhatsApp · iOS Live Activity (iOS app try karte waqt yaad dilana).
