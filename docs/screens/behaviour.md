# Har screen, har button — behaviour spec

Ye file batati hai ki **har screen pe kya-kya hai, har button/row/chip click karne pe kya hota hai, kaun sa modal / drawer / sheet / dropdown khulta hai, usme kaun se option hain, aur mock data me kya dikh raha hai.**

**Source:** design canvas (`https://claude.ai/artifact/NKNGUZt9ZJMVXwiKXbfhiK`, v282). Repo ka `design/screens/*.dc.html` usi canvas ki copy hai (104 boards). Clash hone pe **ye file + canvas jeet-te hain**.

**Padhne ka tarika**
- Har screen ka ek section: *Kya hai → Har control → Modals/drawers → Mock data*.
- UI labels English me hi likhe hain (jaisa design me hain), baaki explanation Hinglish me.
- "Web" = 1440 board, "Phone" = 390 board. Jahan phone alag behave karta hai wahin likha hai; warna phone web jaisa hi hai sirf layout chhota.
- Jo cheez design me *abhi* mock hai (koi backend call nahi) wo "mock" likh ke mark ki hai.

---

## Contents

| # | Area | Screens |
|---|---|---|
| 1 | [Shell — sidebar, header, phone nav](#1-shell--sidebar-header-phone-nav) | sab pages pe common |
| 2 | [Admin](#2-admin) | 25 |
| 3 | [Trainer](#3-trainer) | 7 |
| 4 | [Client app](#4-client-app) | 13 |
| 5 | [Login, join link, onboarding](#5-login-join-link-onboarding) | 7 |
| 6 | [Common patterns](#6-common-patterns) | table, filter, modal, drawer, toast |

---

## 1. Shell — sidebar, header, phone nav

### Sidebar (web, admin + trainer)
240 px ka left rail, har web page pe. Items 34 high, radius 8; hover aur active dono #FAFAFA + 1px line, active ka icon accent blue.

| Control | Click pe |
|---|---|
| Koi bhi nav item | Us page pe chale jaate ho. Rail wahin rehta hai, sirf right panel badalta hai. |
| `Approvals` ka count chip (5) | Alag se clickable nahi — sirf batata hai kitne waiting hain. |
| Edge chevron (round 28, rail ke kinare) | Rail 240 ↔ 68 collapse/expand. Sirf tab dikhta hai jab pointer rail pe ho. Collapsed me labels tooltip ban jaate hain, group labels 1px divider, count corner badge. Width animate nahi hoti. |
| Brand block (logo + naam) | Click target nahi — bas naam aur role line: admin ke liye "Owner workspace", trainer ke liye "Trainer workspace". |

**Admin rail:** Dashboard · Clients · Approvals · Trainers · Calendar · Activity log — **Build:** Programs · Exercises · Nutrition & foods · Habits & supplements · Forms & check-ins · Content library — **Engage:** Automations · Emails & alerts — **Workspace:** Settings.

**Trainer rail:** Dashboard · My clients · Check-ins · Calendar — **Library:** Programs · Exercises · Nutrition & foods · Habits & supplements · Content library — **You:** My profile. (Approvals, Trainers, Automations, Emails, Settings trainer ko nahi dikhte.)

### Page header (har web page ke top pe)
Title left, actions right ek line me. Title width ke saath 28 → 20 shrink hota hai, max 2 line. ~760px se neeche outline buttons icon-only ho jaate hain (tooltip naam rakhta hai); phone pe har button icon-only.

| Control | Click pe |
|---|---|
| Search icon | Search field focus. |
| Bell icon | Notifications. Dot tab dikhta hai jab unread ho. |
| Profile (round 36 photo) | Account menu khulta hai. Naam tooltip me hai, menu ke andar bhi. |
| Main action (e.g. `Add client`) | Us page ka primary drawer/modal. Niche har screen me likha hai. |

### Phone nav (sidebar ki jagah)
Bottom bar, 5 tab. **Admin:** Home · Clients · Approvals (badge 5) · Calendar · More. **Trainer:** Home · Clients · Check-ins · Calendar · More. **Client:** Home · Train · Food · Progress · More.

**More page** (admin/trainer) — upar account card (naam + role, tap → Settings / My profile), fir wahi groups rows ki tarah, sabse neeche laal `Log out` row (tap → login screen).

---

## 2. Admin

### 2.1 Dashboard — `AdminDashboard` / `AdminDashboardMobile`

Admin ka ghar. Title greeting hai: **"Good evening, Vimal"**, neeche *"Thursday, 8 October · 3 things need you today"*.

**Header buttons:** Notifications (bell), `Add client`, profile (V) menu. Search icon nahi hai (Gautam, 22 Oct).

**Page pe kya hai (upar se neeche):** 4 stat cards → 6 "at a glance" tiles → 2 columns (left: Needs action + Trainer performance, right: At-risk clients + Recent activity).

**Stat cards (mock):** Active clients **142** (+8 this month) · Pending approvals **5** (Oldest waiting 2 days) · Check-in rate **86%** (−2% vs last week) · Avg adherence **81%** (+3% vs last week). Delta number ke bagal me baithta hai, upar wala green, neeche wala red.

**At a glance tiles — har tile ek list kholta hai:**

| Tile | Number | Sub | Kholta hai |
|---|---|---|---|
| Clients | 156 | 142 active · 14 paused | Clients page |
| Trainers | 8 | 1 over capacity (amber) | Trainers page |
| Check-ins to review | 12 | 4 waiting over 48 h (amber) | Check-ins list |
| Onboarding pending | 5 | 2 forms not complete | Clients, onboarding filter |
| Nutrition plans pending | 4 | Clients without a meal plan | Nutrition |
| Programs ending | 2 | This week · plan what is next | Programs |

**Needs action card**

| Control | Click pe |
|---|---|
| Kind chips: `All` · `Approvals` · `Clients` · `Check-ins` · `Trainers` · `Programs` | List us kind pe filter ho jaati hai. Chip pe count hota hai; jis kind ki ek bhi row nahi, wo chip dikhta hi nahi. Dobara All pe aa ke clear. |
| Row ka CTA (`Review` / `Open` / `Assign` / `Rebalance` / `Plan` / `View`) | Us kaam ki screen. |
| Row ka × | Hata diya (Gautam, 22 Oct): row tab tak rehti hai jab tak kaam ho na jaaye. |
| 5 se zyada rows | Card ke andar hi scroll (5 rows ki height, scrollbar dikhta hai); `Show all` button nahi. |
| Koi row nahi | Empty state: *"All clear. Nothing needs you right now."* |

Rows oldest first. Mock: 5 sign-ups waiting · 4 check-ins waiting over 48 hours · 3 clients need a trainer · Arjun Rao is over capacity (24 of 20) · 2 programs end this week · Aisha Sheikh flagged low energy · 2 clients have not logged in 7 days · Neha Jain asked to change trainer · Meera Shah has 5 replies pending.

**Trainer performance card** — table: Trainer · Clients · Adherence (bar) · Avg reply. Lowest adherence first, 5 dikhte hain, `Show all 8 trainers` toggle. Load `24 / 20` red ho jaata hai jab max se zyada ho. Upar right ek `This week` select (mock, badalta nahi).

**At-risk clients card** — 3 rows, `Show all 7`. Har row pe `Remind` button. Header me `Remind all` → **modal "Remind 7 at-risk clients?"**: body me ek checked checkbox *"Skip clients reminded in the last 24 hours (2)"*, footer `Cancel` + `Remind 5 clients`. Dono button modal band karte hain (mock bhejta kuch nahi). Backdrop click aur × bhi band karta hai.

**Recent activity card** — 5 one-line rows (kaun + kya + kitni der pehle). Lamba text hover pe tooltip me poora dikhta hai. `View all` → Activity log.

---

### 2.2 Clients — `Clients` / `ClientsMobile`

Title **Clients**, sub *"14 clients · 11 active · 3 need a trainer"*. Header me `Invite link` (outline) aur `Add client` (primary).

**Tabs:** `All 14` · `Active 11` · `Pending` · `Paused` · `At risk`.

**Toolbar (card ke andar):** search *"Search name or email"* left; right `Filter` + `Export`.

| Control | Click pe |
|---|---|
| `Filter` | Dropdown: **Trainer** (Anyone / Aman Verma / Meera Shah / Neha Joshi / Sahil Kapoor / No trainer) · **Goal** (Any / Fat loss / Muscle gain / Strength / Recomp / General fitness) · **Onboarding** (Any / Done / Not started / In progress) · **Next check-in** (Any / Today / This week / Overdue) · **Joined** (Any time / Last 30 days / This year). Option chunte hi dropdown band, chip neeche aa jaata hai, `Filter` pe count lag jaata hai (`Filter · 2`). `Clear filters` sab hata deta hai. |
| `Export` | CSV download (mock). |
| Row pe click | Client profile. |
| Row ka 3-dot (last column) | Menu: `View profile` · `Edit details` · `Change trainer` · `Pause` · `Delete client` (laal). Ek hi menu ek time pe khulta hai; bahar click pe band. |
| Checkbox column | Bulk select (mock). |
| `Add client` | **Add client drawer** — neeche. |
| `Invite link` | **Invite link drawer** — neeche. |

**Table columns:** name + email · Status badge · Trainer · Onboarding · Phone · Joined · Last active · Actions. Status badges: `Active` (green) · `Pending` (amber) · `Paused` (grey) · `No trainer` (amber) · `At risk` (red). Header band uppercase hai aur vertical scroll pe chipka rehta hai; koi column pin nahi hota; pagination card ke neeche.

**Add client drawer**

Fields: Full name (`Kavya Menon`) · Phone (`+91`, number type karte hi hint *"No client or sign-up with this number"*) · Email (*"For login links and receipts"*) · Gender select (`Female`) · DOB (`DD / MM / YYYY`) · City (`Bengaluru`) · Goal select (`Lose fat`) · Current weight (`62 kg`) · Height (`160 cm`) · Target weight (`68 kg`) · Health notes (*"Back pain, thyroid, recent surgery…"*) · Trainer select (`Aman Verma · 24 / 30`, hint *"You can change this later"*) · Program (`Pick later`) · Start date (`Mon, 12 Oct`, hint *"Her day 1 for workout and meal plans"*).

Do toggle rows: *"Send her the login link"* (WhatsApp + email, apna password set karti hai) aur *"Ask her to fill the health form (PAR-Q)"* (pehli login pe dikhta hai).

Upar do mode chips — **`Active now`** ya **`Send to Approvals`**:
- `Active now` → line *"She can log in as soon as she opens the link."*, button label **`Add client`**.
- `Send to Approvals` → line *"She shows up in Approvals first, like people who sign up with a link."*, button label **`Add and send to Approvals`**.

Footer note *"Only name and mobile are needed"*, buttons `Cancel` + primary (label upar wale mode se).

**Invite link drawer** — 3 tabs

1. **`Invite link`** (default) — ek link card: `trainwithvimal.app/join/AMAN-4821`, buttons `Copy link` (primary sm) · `WhatsApp` · `Email` · `Download QR` (text). Neeche **Link settings**: trainer (*"This trainer sees them first"*), aur ek toggle **"New sign-ups wait in Approvals"** (*"You approve each person before they can log in"*). Toggle off karte hi step-3 text badal jaata hai: on → *"She waits in Approvals. You or Aman Verma approve her, then she can log in."*, off → *"She can log in straight away. Aman Verma gets a notice."* Sabse neeche preview **"What she sees when she opens the link"**. Button `Done`.
2. **`New link`** — Trainer select · Name/label (`Instagram · October`, *"Only you see this"*) · Expiry select (`30 days · till 8 Nov`) · Max people (`No limit`) · Code (`AMAN-5530`, *"Made from the trainer name"*) · note *"The old links keep working"*. `Create link` dabate hi naya link ban ke list me sabse upar aa jaata hai aur drawer `Invite link` tab pe us naye link ke saath khul jaata hai.
3. **`All links N`** — har link ki row: code, label, trainer · bana kab · kab tak, `N joined`, `N waiting`, aur status badge `On` (green) / `Off` (grey) / `Ended` (grey). Row click → wo link `Invite link` tab me khul jaata hai. Row ka 3-dot: `Open link and QR` · `Copy link` · `Turn off` / `Turn on` · `Delete link` (laal). Off/Ended rows dim dikhti hain. Upar summary: *"4 of 5 links are on"* aur counts (links · on now · people joined · waiting now).

Mock links: AMAN-4821 (Aman Verma, 6 joined, 1 waiting) · VIMAL-0007 "Website" (41 joined) · NEHA-3307 "Instagram · Sept" (20 people · 3 used) · SAHIL-1190 (9 joined) · MEERA-2210 "Yoga batch" (**Ended** 8 Oct).

**Built (D-47):** `/clients` for admin. Export and the select boxes are off (as on My clients). Pause / Resume and Delete ask first and give an Undo toast. Add client checks the mobile while typing and saves all in one go; the toast offers `View` (or says the person is in Approvals). Change trainer drawer: search, load bars, Current / Full / Good fit tags (Full can't be picked), "Move open check-ins" (off = the new trainer starts fresh, open check-ins are marked as seen), "Tell old trainer" (a notice), a note for the new trainer (saved as a client note). Invite link opens the Invite links modal with a real QR code and Download QR (PNG).

**Mock clients:** Riya Sharma (Active, onboarding Done) · Rohan Kapoor (40%) · Neha Jain (Pending, Not started) · Kabir Mehta · Ananya Iyer (Paused, 9 d ago) · Sana Khan (No trainer) · Aisha Sheikh (At risk) · Priya Reddy (20%).

---

### 2.3 Approvals — `Approvals` / `ApprovalsMobile`

Title **Approvals**, sub *"5 people waiting · oldest waiting 2 days · new sign-ups from invite links land here"*. Header me wahi `Invite link` + `Add client` (bilkul wahi drawers jaise Clients me).

**Tabs:** `Waiting 5` · `History 6`.

**Waiting table:** person (naam + email) · Invited by · Profile setup (5 pips, `3 of 5`) · Health note badge · Signed up from (Web / Android app / iPhone app) · Waiting (1 din baad amber, 2 din baad red) · `Review` button.

| Control | Click pe |
|---|---|
| Row ya `Review` | **Review drawer** right se khulta hai, us person ka. |
| `Filter` (Waiting tab) | **Invited by** (Anyone / Vimal / Aman Verma / Meera Shah / Neha Joshi / Sahil Kapoor) · **Profile setup** (Any / All 5 done / Not finished) · **Waiting** (Any time / Over 1 day / Over 2 days) · **Health note** (Any / Has a health note / No health note) · **Signed up from** (Any / Web / Android app / iPhone app). Chips neeche, har chip pe × . |
| `Filter` (History tab) | **Decision** (Any / Approved / Rejected) · **Decided by** (Anyone / Vimal / Aman Verma / Neha Joshi) · **When** (All time / Last 7 days / Last 30 days). |
| `Clear filters` | Sab filter hat jaate hain. |
| Filter se koi match na ho | *"No one matches these filters."* + `Clear filters`. |

Footnote: *"Showing N of 5. Sorted oldest first. Amber after 1 day, red after 2 days."*

Page pe ek chhota **invite-link summary** bhi hai (top 3 links + counts); link row click → Invite link drawer us link pe, aur summary click → drawer ka `All links` tab.

**Review drawer** — ek person poora

- Header: naam, `‹` `›` se agle/pichle waiting person pe jaa sakte ho (list wrap karti hai).
- **Profile setup**: 5 steps — Account made (Email and phone checked) · Basic details (Name, age, city) · Goal and body · Health and PAR-Q (7 health questions) · Food preferences. Jo nahi hue unpe *"Not done"*.
- **From her onboarding**: Goal / Body / Trains / Food. Agar kuch bhara hi nahi: *"She has not filled her goal and body details yet. Ask for info to remind her."*
- **Health note** badge jab ho (mock: Pooja Nair — *"High blood pressure, on medicine. Ask for a doctor note before hard sessions."*).
- **Trainer** list: har trainer naam, speciality, load `24 / 30` aur bar. Tag: `Invited her` (grey) · `Good fit` (green) · `Full` (amber). **Full trainer click nahi hota.** Default pick = jisne invite kiya tha. Upar *"5 of 7 have space"*.
- **When you approve** do toggle: *"Tell her on WhatsApp and email"* (*She can log in right away*) aur *"Ask her to finish setup"* (*Only if some steps are not done*).
- Footer: `Reject` (laal text, left) · `Ask for info` (outline) · primary — label **`Approve and assign`** jab 5/5 done, warna **`Approve anyway`**.

**Reject modal** — reason list (ek chunna hai): `Not a fit for our coaching` (Her goal or health needs a specialist) · `Already has an account` · `Wrong or fake details` · `No trainer free right now` (She can sign up again later) · `Something else` (Write it in the message). Message box (*"Thanks for signing up. Right now we…"*), toggle *"Tell her by email"* (*She sees the reason and your message*). Buttons `Cancel` + `Reject` (laal).

**Ask for info modal** — "What does she need to do?" multi-select: `Finish profile setup` (N steps left in the app) · `Fill the health form again` · `Send a doctor note` (blood pressure/heart/recent surgery ke liye) · `Add a profile photo` · `Check her phone number` (OTP nahi gaya). Default: setup adhoora ho to `setup`, health note ho to `doc`, warna `photo`. Channel chips: `WhatsApp` (on) · `Email` (on) · `App notice` (off) — toggle hote hain. Button `Send request`, aur count line *"2 things asked"*.

**History tab** — naam · signed up · decision badge (`Approved` green / `Rejected` red) · reason/trainer · decided by · when. **Rejected rows pe `Move back` milta hai** → **modal**: approve ki hui row par *"She cannot log in until someone approves her again. Her data stays / Trainer stops seeing her as a client, plans paused not deleted / She shows at the top of Waiting with a 'Moved back' tag."*; rejected row par *"Her rejection is undone… The reason stays in her history…"*. Ek toggle *"Only if you want her to know it is being looked at again"*, button `Move back`.

**Built (D-47):** `/approvals` (`?tab=history` opens History). People moved back show on top with a "Moved back" tag. After Approve: toast "X is approved" with `View`; after Reject: toast with `Undo` (moves them back); after Ask for info: "Request sent to X". Move back gives "X is back in Waiting" with `Open`. Phone: one line per person (inviter, waiting, health note, `Review`); History rows show the decision badge, reason and date with the Move back icon for rejected people. The invite-link summary card is not built; its data is in the Invite links modal's `All links` tab.

Mock waiting: Pooja Nair (2 days, health note, 3/5) · Ishaan Mehta (1 day, 5/5) · Neha Jain (5 h, 2/5) · Ananya Gupta (3 h, 4/5, health note) · Rohit Sinha (40 min, 5/5).

---

### 2.4 Exercise library — `ExerciseLibrary` / `ExerciseLibraryMobile`

Title **Exercise library**, sub *"28 built-in · 0 custom by your team"*. Header: `New exercise` (primary).

Cards grid (auto-fill, min 280): har card pe video/cover thumb (ya "Image" placeholder jab video na ho), naam (lamba ho to ellipsis), aur meta line pe muscle · equipment · level badge (Beginner green, Intermediate amber) aur *"2 programs"* / *"No program yet"*.

| Control | Click pe |
|---|---|
| Card | Exercise detail. |
| Search *"Search exercises"* | Naam se filter. |
| `Filter` | Panel khulta hai: left me categories **Muscle · Equipment · Level · Source**, right me us category ke options count ke saath. Option **multi-select** hai — chunne pe right side tick aata hai (checkbox nahi), card list turant filter hoti hai. |
| Chuna hua option dobara click | Hat jaata hai. |
| Chips (panel ke neeche) | Har chuni hui cheez ek chip; chip ka × sirf wahi hataata hai. |
| `Clear all` / `Clear filters` | Sab category khaali. |
| `Sort` | Sort dropdown. |
| `New exercise` | Add exercise page. |

Default mock state: **Muscle = Chest** chuna hua hai. Options — Muscle: Chest 5, Back 5, Legs 5, Shoulders 3, Arms 3, Core 2, Cardio 1 · Equipment: Barbell, Dumbbell, Cable, Machine, Bodyweight · Level: Beginner, Intermediate · Source: Built-in, Custom.

---

### 2.5 Exercise detail — `ExerciseDetail` / `ExerciseDetailMobile`

Breadcrumb `Exercises › Barbell Bench Press`. Header: 76px video thumb (0:42) + naam + *"Chest · Barbell · Built-in exercise"*. Actions: `Duplicate to edit` (outline) · `Add to program` (primary) · 3-dot (`More actions`).

**Default sets and reps** card (*"Filled in when added to a program"*): Client logs `kg × reps` · Sets 4 · Reps 6–8 · Rest 2 min · RPE 8/10 · Tempo 3-1-1.

**Tabs (left card):** `How to 4` · `Form cues 3` · `Muscles 3`. **Default tab = Muscles.**

| Tab | Kya dikhta hai |
|---|---|
| How to | 4 numbered steps (lie with your eyes under the bar… / grip slightly wider… / lower to mid chest… / press up and slightly back). |
| Form cues | 3 tick-wali lines (squeeze the bar… / hips on the bench… / touch the chest, do not bounce). |
| Muscles | Blue **Primary muscle** block (Chest · Pectorals · *"decides where this exercise shows in the library filter"*, 3/3 meter) + **Also works** rows: Triceps (`Strong`, 2/3) aur Front shoulders (`Light`, 1/3). Bagal me body map — Front aur Back figure, legend `Primary` / `Strong` / `Light`. |

Right column: **Video** card (From content library — Bench press · setup · 0:42, cover = Frame at 0:12) · **Details** card (Muscle group Chest · Equipment Barbell · Level Intermediate · Source Built-in) · **Used in 2 programs** — Fat Loss Phase 1 (Upper A · 12 workouts · 4 clients) aur Hypertrophy · Push / Pull / Legs (Push A · 8 workouts · 4 clients); row click → Program builder.

`Duplicate to edit` built-in exercise ki copy banata hai jo editable hai (built-in edit nahi hota).

---

### 2.6 Add exercise — `ExerciseAdd` / `ExerciseAddMobile`

`New exercise` ya `Duplicate to edit` se khulta hai. Form me: naam, muscle group, equipment, level, video + cover, **How to** steps aur **Form cues** — dono me line add/remove ho sakti hai (step wali tarah ×), default sets/reps/rest/RPE/tempo, aur muscles (primary + also-works with Light/Strong meter). Save → exercise detail.

---

### 2.7 Trainers — `Trainers` / `TrainersMobile`

> **Built 2026-10-22 (D-48), route `/trainers` (`?add=1` opens Add trainer).** Stats are content-wide cards; phone shows one strip of 4 cells. Tabs All / Active / Full / Inactive with counts, search (name, phone, email), Filter (Access, Space, Speciality, Check-ins) with chips, 20 a page. Row ⋯: Open profile, Access and permissions (`/trainers/<id>?tab=access`), Edit details, Move clients to another trainer, Deactivate / Reactivate. Add trainer drawer: mobile already-used check, Access level with help text, "give clients now" opens Assign clients on the new profile.

Title **Trainers**, sub *"8 in the team · 7 active · 129 clients"*. Header: `Add trainer` (primary).

**4 stat cards:** Active trainers **7** (1 inactive) · Client spots **129 / 215** (86 spots free) · Check-ins to review **11** (Karan has the most (4)) · Avg adherence **82%** (+2% vs last week).

**Tabs:** `All 8` · `Active 7` · `Full 1` · `Inactive 1`.

**Table:** trainer (naam + email) · Speciality · Clients (`24 / 30` + bar; 80%+ pe bar amber, full pe red aur `Full` badge) · Check-ins to review (3+ amber, 0 grey) · Adherence (80% se kam amber) · Access · Status (`Active` / `Inactive`) · Joined · 3-dot.

| Control | Click pe |
|---|---|
| Row | Trainer profile. |
| 3-dot (active trainer) | `Open profile` · `Access and permissions` · `Edit details` · `Move clients to another trainer` · `Deactivate` (laal). |
| 3-dot (inactive trainer) | `Reactivate` — click karte hi row wapas Active ho jaati hai, counts update. |
| `Deactivate` | **Modal**: *"What happens"* — agar unke clients hain to *"Their N clients stay with them until you move them. Those clients get no check-in reviews meanwhile."*, warna *"They have no clients right now."* Saath me kahan move kar sakte ho (`Share between trainers with space` + kaun kitne free). Buttons `Cancel` + `Deactivate` (laal). Confirm karte hi row Inactive ho jaati hai. |
| `Filter` | **Access** (Any / Assigned clients / All clients / Custom) · **Space** (Any / Has space / Full) · **Speciality** (Any / Fat loss / Strength / Muscle gain / Women's / Beginners) · **Check-ins** (Any / Has check-ins to review / All reviewed). Chips + `Clear filters`. Match na ho to *"No trainers match."* |
| `Add trainer` | **Add trainer drawer** — neeche. |

Footnote: *"Adherence is the share of planned workouts and meals done in the last 7 days."*

**Add trainer drawer** — Full name (`Tara Pillai`) · Phone (`+91`, check *"No trainer or client uses this number"*) · Email · Gender (*"For clients who ask for a woman trainer"*) · Speciality (`Strength, Fat loss`, *"Separate with a comma"*) · Max clients (`30`, *"A number. You can change this later"*) · Bio (*"Shown on their profile"*) · Joining date (`Fri, 9 Oct 2026`).

Access mode chips — `Assigned clients` / `All clients` / `Custom`, line badalti hai:
- Assigned clients → *"Only the clients you give them: their plans and check-ins. Best for new trainers."*
- All clients → *"Every client of the gym. For senior trainers who cover for others."*
- Custom → *"Pick each permission yourself after adding. Starts the same as Assigned clients."*

Do toggle: *"Send the login invite"* (WhatsApp + email, apna password) aur *"Give them clients now"* (*Opens the Clients page to pick clients for them*). Hint: *"Certificates and ID documents are added from their profile, under Documents."* Footer note: *"They cannot add trainers or change gym settings"*, buttons `Cancel` + `Add trainer`.

**Mock team:** Vimal (Owner, 8/10, You) · Aman Verma (24/30) · Neha Joshi (21/30) · Sahil Kapoor (18/30) · Karan Mehta (30/30 — **Full**) · Ritu Malhotra (16/25, Custom · 12 of 18) · Meera Shah (12/25) · Varun Kohli (**Inactive**, 0/30).

---

### 2.8 Activity log — `Activity` / `ActivityMobile`

> **Built 2026-10-22 (D-48), route `/activity`.** Search (person, client or item: server `search=`), Filter (Who: Everyone / Team / Clients / Automations; Person: anyone in the team) with removable chips, range menu (Today … All time, default Last 7 days), kind chips All / Check-in / Plan / Workout / Meal / Body / Client / Content / System with counts, rows by day (the day count is the full count, not only loaded rows), old → new changes, time "2 min ago" today and "7:40 pm" before, hover shows the source. 20 a page with Show more (cursor). Export downloads a CSV of what the filters show.

Title **Activity log**, sub *"Every change by your team, your clients and the system."* Header me sirf `Export`.

Timeline din ke hisaab se grouped: **Today · Yesterday · Wed, 7 Oct · Mon, 5 Oct · Thu, 1 Oct · Mon, 21 Sep · Tue, 1 Sep**. Har row 40px: kaun + kya kiya · change (`60 s → 90 s` jaisa purana→naya) · kind · kab. Source (Admin · Web / Trainer · Web / Client · Android app / Automation · Push and WhatsApp) hover pe dikhta hai.

| Control | Click pe |
|---|---|
| Date range select (`Last 7 days` default) | Dropdown: `Today` · `Last 7 days` · `Last 30 days` · `Last 3 months` · `All time`. Chunte hi list us range ki ho jaati hai aur wapas 8 rows pe reset. |
| Kind chips | `All` · `Check-in` · `Plan` · `Workout` · `Meal` · `Body` · `Client` · `Content` · `System`, har ek pe count. Ek hi kind chun sakte ho; `All` se clear. |
| `Filter` | **Who** (Everyone / Team / Clients / Automations) · **Person** (Anyone / Vimal / Aman Verma / Sahil Kapoor / Meera Shah). Chips neeche, chip ka × us filter ko hataata hai. |
| `Show more` | 8 aur rows. Footer: *"Showing 8 of 24"*. |
| Kuch na mile | *"Nothing matches. Try a longer date range or fewer filters."* |
| `Export` | CSV (mock). |

Yahi timeline component trainer profile aur client profile ke "Activity" tab me bhi use hota hai (wahan sirf us insaan ki rows).

---

### 2.9 Calendar — `Calendar` / `CalendarMobile`

> **Built 2026-10-22 (D-48), route `/calendar` (admin).** Same code as the trainer calendar with `admin: true`. Sub "Your team’s sessions, range" or "{Trainer}’s sessions, range". All trainers button (menu "Show sessions of" with each trainer's sessions this week). Blocks show "7:00 am · Aman" on All trainers. 4th stat Busiest trainer (Working days when one trainer is picked); no shading on All trainers. Session panel shows Trainer instead of Plan. New session: Client + Trainer side by side, the client's trainer is picked for you, picked trainer's clients first; warnings name the trainer ("Aman already has …", "Outside Aman’s working hours", "Aman is free at this time"). Availability drawer: Trainer pick, then that trainer's week; saves for that trainer.

Title **Calendar**, sub *"Your team's sessions, 5 – 11 Oct 2026"* (trainer chuno to *"Aman Verma's sessions, …"*). Header: `Availability` (outline) + `New session` (primary).

**4 stat cards:** Sessions this week · Done (+ % of the week) · On a call (Quick calls and reviews) · Busiest trainer (ya trainer filter laga ho to Working days).

**Toolbar:** `‹` `›` · `Today` · date range text · trainer dropdown · `Week` / `Day` toggle · kind legend (`1:1 session` 60 min · `Quick call` 15 min · `Program review` 30 min).

| Control | Click pe |
|---|---|
| `‹` / `›` | Week view me pichla/agla hafta; Day view me pichla/agla din (hafte ke kinare pe apne aap agle hafte me chala jaata hai). |
| `Today` | Aaj (Fri) pe wapas. |
| Trainer dropdown (`All trainers`) | List: All trainers + 7 trainers, har ek pe session count. Trainer chunte hi grid sirf unka, aur unke **non-working hours grey** ho jaate hain, off-day pe poora column *"Day off"*. |
| `Week` / `Day` | Week = 7 column, Day = 1 column (Monday…Sunday poora naam). Week view me din ke header pe click karo to wahi din Day view me khul jaata hai. |
| Session block | **Session drawer** khulta hai. Overlap hone pe blocks side-by-side baant jaate hain; 45 min se chhota block "tiny" style me. Done sessions halke dikhte hain. Hover pe tooltip: client · kind · time · trainer · Done/Booked. |
| `New session` | **New session drawer**. |
| `Availability` | **Availability drawer**. |

Aaj ki line (current time) Friday column pe dikhti hai. Grid 6 am se 10 pm.

**Session drawer** — kind badge, client, trainer, `Monday, 5 Oct · 7 – 8 am`, Place (`Andheri gym floor`) ya *"On a call"*, note, *booked by*, aur status badge `Done` (green) / `Booked` (blue).

| Button | Kya karta hai |
|---|---|
| `Open profile` (text) | Client profile. |
| `Reschedule` (outline) | **Move session** form — wahi New session drawer, par title *"Move session"*, sub *"Riya Sharma · now Monday, 5 Oct · 7 – 8 am"*, button `Move session`. Save karte hi block nayi jagah chala jaata hai. |
| `Mark as done` / `Mark as not done` | Status turant toggle, block ka look badal jaata hai. |
| `Cancel session` (laal text) | **Confirm modal** — toggle *"Tell the client"* (*Push notice and WhatsApp with the time that was cancelled*), buttons `Keep it` + `Cancel session` (laal). Confirm pe block hamesha ke liye hat jaata hai. |

**New session drawer**

- Kind chips: `1:1 session 60` · `Quick call 15` · `Program review 30` — chunte hi duration aur default jagah set (call/review = Call, session = In person).
- **Client** dropdown — clients sorted taaki chune hue trainer ke clients upar aayein, unpe tag *"Their client"*. Client badalte hi uska trainer apne aap set ho jaata hai.
- **Trainer** dropdown — 7 trainers, client ke apne trainer pe tag *"Their trainer"*. Hint: *"Shows clients of the picked trainer first"* / *"Their trainer is picked for you"*.
- **Week strip** (Mon–Sun) + `‹` `›`; aaj se pehle ke din "past" dikhte hain.
- **Time**: hour dropdown (6 am – 9 pm) + minute chips `:00` `:15` `:30` `:45`. Duration kind se aata hai (min field).
- **Where**: `In person` (place field `Andheri gym floor`, *"Where they meet"*) ya `Call` (link field `meet.google.com/abc-defg-hij`, *"Optional"*).
- **Note** (*"e.g. Check the left shoulder first"* — *"Optional. The trainer sees it on the session."*)
- Toggle *"Tell the client"* (*Push notice and WhatsApp with the time and place*).
- **Live check** form ke neeche: free ho to green *"Aman is free at this time"*; clash ho to red *"Aman already has Riya Sharma at 7 – 8 am"* **aur create button disable**; working hours ke bahar ho to *"Outside Aman's working hours (6:30 am – 8 pm)"* ya *"day off"*.
- Footer: din + time range, buttons `Cancel` + `Create session` / `Move session`.

**Availability drawer** — upar trainer dropdown, sub *"6 working days"*. Har weekday ki row: on/off toggle + from–to time. Off karte hi row `Day off` ho jaati hai aur calendar me us din ka column grey. Footer note *"Booked sessions stay as they are"*, button `Save availability`.

Mock week: 20 sessions, Aman Verma sabse busy. Clients ↔ trainers mapping bhi mock me fix hai (Riya/Rohan/Kabir/Dev/Ishita → Aman, Aisha → Meera, Sana → Neha, Vikram → Sahil, Ananya → Ritu, Arjun → Karan, Pooja → Vimal).

> Parked (Probid, 9 Oct): "Body scan" 20 min kind abhi nahi — sirf un gyms ke liye jinke paas body composition machine ho; check-ins weight aur photos cover kar lete hain.

---

### 2.10 Programs — `Programs` / `ProgramsMobile`

Title **Programs**, sub *"Master plans for your clients. Change one and everyone following it gets the update."* Header: `New program` (primary).

**Tabs:** `Active 5` · `Archived 1`.

Cards grid. Har card pe: naam, goal line (*"Fat loss · gym"*), `12 weeks`, `5 days / week`, week pattern ke 7 dot (M T W T F S S — training day filled, hover pe *"Monday · training"*), assigned clients ke 3 avatar + `+1`, aur *"Edited 2 Oct"*. Jisko koi client nahi: *"Not assigned"*.

| Control | Click pe |
|---|---|
| Card | Program builder. |
| Card ka 3-dot | `Open` · `Duplicate` · `Archive` / `Restore` · `Delete` (laal). |
| `Duplicate` | *"Name (copy)"* turant list me sabse upar, bina clients ke. Toast **"Program duplicated"** + `Undo`. |
| `Archive` | Card Archived tab me chala jaata hai, `Archived` badge lagta hai. Toast *"Fat Loss Phase 1 archived — Assigned clients keep their plan"* + `Undo`. |
| `Restore` | Wapas Active tab me. |
| `Delete` | **Confirm modal**: *"Fat Loss Phase 1 will be removed for good and unassigned from 4 clients. Workouts they already logged stay safe."* Buttons `Cancel` + `Delete`. Delete ke baad toast + `Undo`. |
| `New program` | **Modal**: naam (*"e.g. Strength Base"*), **Weeks** stepper (1–24, default 8), **Days per week** stepper (1–7, default 4), aur ek week preview jisme pehle N din filled. Hint: *"The other days start as rest days. You can change every week later."* Buttons `Cancel` + `Create program`. |
| Khaali tab | Active: *"No programs yet — Build your first master plan and assign it to clients."* · Archived: *"Nothing archived — Programs you archive are kept here and can be restored any time."* |

Mock: Fat Loss Phase 1 (12 wk, 5 d, 4 clients) · Hypertrophy · Push / Pull / Legs (8 wk, 4 clients) · Beginner Full Body (4 wk, 1) · Yoga Strength (6 wk, 2) · Strength Base (10 wk, 0) · Shoulder-safe Upper Body (**Archived**).

---

### 2.11 Program builder — `ProgramBuilder` / `ProgramBuilderMobile`

Breadcrumb `Programs › Master plan`. Header: program naam + *"12 weeks · 5 days / week · edited 2 Oct"*, right pe 3-dot aur `Assign` (primary). Archived program pe `Archived` badge + `Restore` button.

**Program 3-dot:** `Rename` · `Duplicate program` · `Archive` / `Restore` · `Delete` (laal).
- `Rename` → modal *"Rename program — Clients see the new name in their app"*, field Program name, `Save`. Toast *"Program renamed"*.
- `Duplicate program` → naam "(copy)" ho jaata hai, clients hat jaate hain, toast *"Program duplicated — Now editing … (copy)"*.
- `Archive` → toast *"Program archived — Assigned clients keep their plan"* + `Undo`.
- `Delete` → confirm modal, fir toast + `Undo`.

**Week strip:** `W1 … W12`, chune hue week ke din dikhte hain. Saath me **`Copy week N → N+1`** (aakhri week pe label *"Copy week 12 → new week"* aur wo naya week bana deta hai). Toast + `Undo`.

**Day column (left):** har weekday ek card — naam, summary (`5 exercises · 55 min` / `Rest day` / `No exercises yet`), aur pehle 3 exercise `4×6–8` ke saath, `+2 more`. Rest day alag style. Khaali slot pe **`Add`** → add-day modal. Day card click karne pe wo din right side khul jaata hai; day card ka `Add` seedha exercise picker kholta hai.

**Day panel (right):** heading `Week 1 · Tuesday`, day ka naam, summary `≈ 55 min · 16 sets · 6 exercises`, day 3-dot aur `Add exercise`.

**Day 3-dot:** `Rename` · `Move earlier` (*"Swap with Monday"*, pehle din pe *"Already the first day"*) · `Move later` · `Make rest day` / `Make workout day` · `Remove day` (laal).
- Rest day banate hi toast *"Push Day is now a rest day — Its exercises are kept if you change it back"*.
- `Remove day` → toast *"Push Day removed — Later days of the week moved up"* + `Undo`.
- Rest day pe panel me `Make workout day` button aur note field (*"e.g. 8k steps and 10 minutes of mobility"*).

**Exercise rows:** tag (1, 2, 3… ya superset me `A1`, `A2`), naam, muscles line, Sets · Reps · RPE · Rest · Tempo, aur note. Program ke liye custom banaya ho to `Edited for this program` badge.

**Exercise 3-dot:** `Edit sets and rest` · `Edit for this program` · `Reset to library version` · `Exercise details` · `Move up` · `Move down` · `Make superset with next` / `Remove from superset` · `Remove` (laal).

| Modal | Kya hai |
|---|---|
| **Edit sets and rest** | Upar ek line `4 × 6–8 · RPE 8 · Tempo 3-1-1 · Rest 2 min` jo live update hoti hai. Steppers: Sets (1–12), Rest (0–300 s, 15 s step), RPE (0–10). Reps field (*"e.g. 8–10, AMRAP, 45 s"*), Tempo (*"e.g. 3-1-1"*), note (*"e.g. 30° incline only"*). `Cancel` + `Update`. Toast *"Barbell Bench Press updated — 4 × 6–8 · Rest 2 min"*. |
| **Add exercise (picker)** | Muscle chips `All` · Chest · Back · Legs · Shoulders · Arms · Core · Cardio (counts ke saath). Har row: naam, muscles, equipment + default `4 × 6–8`, video thumb. Multi-select tick. Jo exercise **is din pe pehle se hai** uspe `On this day` badge aur row disabled. Footer: *"3 selected"* aur button `Add 3 exercises` (ek ho to `Add exercise`), kuch na chuna ho to disabled aur *"Tick the exercises to add"*. Add hote hi library ke default sets/reps/rest aa jaate hain; toast *"3 exercises added — Default sets and reps from the exercise · click a row to change them"* + `Undo`. Match na ho: *"No exercise matches. Create it in the exercise library."* |
| **Edit for this program** | Exercise ki **is program ke liye copy**: naam badal sakte ho (hint *"Library name: Dips"*), video chun sakte ho — `Same as library` / `Another video from Content library` / `YouTube link` (link field, *"Plays inside the app."*), aur How-to steps + Form cues add/remove kar sakte ho (`Add step`, `Add cue`, har row pe ×). Footer: `Reset to library` (laal text) · `Save for this program`. Toast *"Bench Dips edited for this program — The library and other programs stay the same"* + `Undo`. |
| **Reset to library version** | Custom copy hatt jaati hai. Toast *"… reset to the library version — Library changes reach it again"*. |
| **Make superset with next** | Dono rows ek group (A) ban jaate hain, tag `A1`/`A2`, visually joined. `Remove from superset` todta hai; group me ek hi bache to superset apne aap khatam. |
| **Add day** | Modal *"Add day — Week 1"*, field Workout name (*"e.g. Upper B"*), button `Add day`. |
| **Rename day** | Modal *"Rename day — Week 1 · Tuesday"*, `Save`. |

**`Assign` button** → **Assign drawer**: sab clients ki list, har ek pe goal · trainer. Jo doosre program pe hai uspe *"On Hypertrophy PPL"*. Multi-select. Button `Save · 4 clients` (koi na ho to `Save · no clients`). Save pe toast *"Assigned to 4 clients — 1 added · 0 removed"* + `Undo`.

Header ke paas **clients chip** (`4 clients` / `No clients yet`) → **Clients drawer**: *"4 follow Fat Loss Phase 1"*, har client pe tag `Master` (blue) ya `Custom` (amber). Hint: *"Clients follow this master plan as it is. A trainer can make a custom version for one client from the client page."* Koi na ho: *"Nobody follows this program yet."* Buttons `Close` + `Change clients` (→ Assign drawer).

Har destructive/bulk action ke baad **dark toast** aata hai, zyadatar pe `Undo`.

Mock program: Fat Loss Phase 1 — Upper A · Push Day · Rest (Steps 8k · mobility) · Pull Day · Legs · Cardio · Rest (Check-in day).

---

### 2.12 Nutrition & foods — `Nutrition` / `NutritionMobile`

Title **Nutrition & foods**. Do tabs: **`Meal plans 4`** aur **`Food library 41`**. Header actions tab ke hisaab se badalte hain.

#### Tab 1 — Meal plans
Sub: *"Master meal plans. Assign one to many clients and note what is different for each."* Header: `Create food` (outline) + `New plan` (primary).

Diet chips: `All` · `Veg` · `Eggetarian` · `Non-veg` · `Vegan` (counts ke saath).

Plan card: naam, diet badge, `4 meals · 10 meal options`, kcal + P/C/F bar (teeno ka weight), `Published` (green) / `Draft` (amber), clients ke avatar + *"3 clients · 1 custom"* (kisi ke paas apna tweak ho to). Jisko koi na mila: *"Not assigned yet"*. Neeche *"Edited 8 Oct"*.

| Control | Click pe |
|---|---|
| Card | Meal plan builder. |
| Card 3-dot | `Open in builder` · `Duplicate` (*"Same meals, no clients"*) · `Delete` (laal). |
| `Duplicate` | *"… (copy)"* sabse upar, Draft, bina clients. Toast + `Undo`. |
| `Delete` | **Confirm**: *"Cut · Eggetarian is removed for good and taken off 3 clients. Meals they already logged stay."* `Cancel` + `Delete`. Toast + `Undo`. |
| `New plan` | **Modal**: naam (*"e.g. Cut · Veg"*), diet chips (Veg / Eggetarian / Non-veg / Vegan), calories stepper (1200–4000, 50 step, default 2000). Hint: *"Breakfast, Lunch, Snack and Dinner split this target. Protein, carbs and fat can be set in the builder."* `Cancel` + `Create plan`. |

Mock plans: Cut · Eggetarian (2150 kcal, 3 clients, Published) · Lean gain · Non-veg (2800, 1, Published) · Fat loss · Veg (1700, 1, Draft) · Maintenance · Vegan (2200, 0, Draft).

#### Tab 2 — Food library
Sub: *"Foods your team uses in meal plans. Clients see team foods first when they search."* Header: `Import from Excel` (outline) + `Create food` (primary).

Group chips: `All` · Protein · Carbs · Fats · Veg · Fruits · Dairy · Indian dishes · **My foods** (team ke apne banaye). Saath me ek **diet dropdown**: `Any diet` / Vegetarian / Eggetarian / Non-veg / Vegan.

Table (10 per page, pagination `1–10 of 41 foods`): food naam + sub-line (source · *"Made by your team"* / *"Imported · IFCT"* · *"2 units"* · *"3 swaps"*) · Diet · Calories · Protein · Carbs · Fat · *Used in* (plan naam, hover pe poori list) ya *"Not in a plan"* · 3-dot (`Edit` · `Duplicate` · `Delete`).

Ek toggle hai **per 100 g** vs **per serving** — table ke numbers usi hisaab se.

`Delete` → confirm: *"Paneer is removed from My foods. It stays in the 2 plans that use it."* Toast + `Undo`. Kuch na mile: *"Nothing found. Remove a filter, or make your own food."*

#### Food drawer (`Create food` / `Edit`)
- Naam (*"e.g. Paneer bhurji"*), brand (*"Only for packaged food"*), diet chips (Vegetarian / Eggetarian / Non-veg / Vegan), group.
- **Serving units** — hamesha `1 g` base rehta hai. `Add unit` dropdown me suggestions: 1 tsp (5 g) · 1 tbsp (15) · 1 katori (150) · 1 cup (200) · 1 glass (250) · 1 bowl (100) · 1 plate (200) · 1 piece (30) · 1 slice (30) · 1 scoop (30) · 1 handful (30), aur `Custom unit` (*"1 serving" 100 g se shuru, toast "Unit added — Name it and set its weight in grams"*). Har unit ke bagal me uske grams ka stepper aur uski kcal. Default unit ke alawa koi bhi unit × se hat sakta hai.
- **Default serving** — unit + quantity stepper; neeche *"= 180 g · 290 kcal"*.
- **Nutrition** — do mode: `Per 100 g` ya `Per 1 plate`. Jo bhi ho, **save hamesha per 100 g hota hai**; mode badalne pe hint batata hai *"You are typing for 1 plate (180 g). Saved as per 100 g: 161 kcal · P 12.2 g …"*. Fields: Calories, Protein, Carbs, Fat, Fibre + optional micros Sodium / Iron / Calcium / Potassium (mg).
- **Calorie check** — *"Per 100 g: 4 × P + 4 × C + 9 × F = 158 kcal. You entered 161 kcal. Close enough."* badge `Calories match` (green) ya `Check calories` (red).
- **Alternatives (swaps)** — `Add alternative` kholta hai ek list: `Same group` / `All foods` toggle, top 6 foods **match %** ke saath (*"Match = how close protein, carbs and fat are, per calorie"*; 85%+ green, 65%+ amber). Add karte hi chip ban jaata hai, × se hat jaata hai. Koi na ho: *"No other foods in this group."* Khaali: *"No swaps yet. The client has to eat this food as planned."*
- **Used in** — kaun se plan aur kaun se meal me.
- Right me live preview card: naam, serving, aur kcal · P · C · F.
- Footer: *"Saved to the team food library"*, button `Save to library` / `Save changes`. Edit save pe toast *"Food updated — The 2 plans using it are updated"* + `Undo`.

> Recipes abhi **parked** hain (Probid, 10 Oct). Code me recipe form hai (ingredients `Add ingredient`, serves stepper, steps `Add step`, per-serving numbers), `RECIPES_ON` true karne pe wapas aa jaayega.

#### Import from Excel (2 steps)
- **Step 1 of 2 · Choose the file** — file picker, `Download the template` (toast *"Template downloaded — food-import-template.xlsx"*). Required columns `Required` badge ke saath: **Food** (Name clients search for), **Portion_g** (Weight of that serving in grams. ml counts as g.), **Calories_kcal**. Optional: Portion/Quantity (unit naam jaise 1 tsp (5 g); sirf "100 g" unit nahi banta), protein/carbs/fat/fibre/minerals, Category (group), Main_Category (veg / non-veg), Source (food ka source note, jaise IFCT). Template me Vimal ki sheet wale saare 15 columns usi order me: Category, Food, Portion/Quantity, Portion_g, Protein_g, Carbs_g, Fat_g, Calories_kcal, Fiber_g, Sodium_mg, Iron_mg, Calcium_mg, Potassium_mg, Source, Main_Category. Column naam me bracket bhi chalte hain ("Sodium (mg)"). Portion sirf "100 g" / "30 g" ho to default serving utne gram. "1 (150 g)" → unit "1 piece", "1 cup (150 ml)" → unit "1 cup" 150 g. Category sirf tab kisi group me jaati hai jab wo group ka hi naam ho (Protein, Carbs, Fats, Veg / Vegetables, Fruits, Dairy, Indian dishes, Beverages); baaki (Grains, Egg, Legumes, Snacks) Other me jaati hai aur apna naam rakhti hai (food drawer me Other ke neeche naam ka field). File chunne pe *"34 rows found"*; na chune to `Next` toast deta hai *"Choose a file first — Excel or CSV"*.
- **Step 2 of 2 · Check and import** — 4 KPI: Rows in the file · New foods · Skipped/Will update/Added again · **Calories differ** (amber).
  - **Already there (duplicates)** ka choice: `Skip them` (*"Your library keeps its numbers. Nothing changes in meal plans."*) / `Update the numbers` (*"Library foods get the numbers from your sheet. Meal plans that use them change too."*) / `Add as new` (*"You get two foods with the same name. Clients may pick the wrong one."*).
  - **Calories differ** rows: har row pe sheet ki kcal vs P/C/F se nikli kcal, aur choice `Sheet` / `P, C, F`.
  - Toggle **"Egg rows are Eggetarian"** — *"Your sheet marks eggs as Non-Vegetarian. 2 rows."*
  - Group aur diet mapping dropdowns (Grains → Carbs, Egg → Protein, Non-Veg → Indian dishes, Beverages → *Beverages (new group)*; Vegetarian → Veg, Non-Vegetarian → Non-veg, Dairy → Veg).
  - Good-to-know lines: kitne serving units Portion/Quantity se bane, raw vs cooked alag rehte hain, ml = g, aur *"Only the exact same name counts as already in your library."*
  - Preview table (6 per page) filter chips: `All` · `New` · `Already there` · `Check`. Har row pe status badge `New` / `Update` / `Skip` / `New · kcal differs`.
  - Button `Import 28 foods`. Import ke baad Food library tab khul jaata hai aur toast *"28 foods imported — 4 library foods updated"* + `Undo`.
  - `Back` step 1 pe le jaata hai.

> Column-matching wala step abhi band hai: sheet ke columns naam se match hote hain, upload seedha Check pe le jaata hai.

---

### 2.13 Meal plan builder — `MealPlanBuilder` / `MealPlanBuilderMobile`

Breadcrumb `Nutrition & foods › Meal plan`. Header: plan naam + *"Eggetarian · Master plan · 3 clients, 1 custom version"*, right pe 3-dot, `Assign` (outline), `Publish` (primary).

**Plan 3-dot:** `Rename plan` (*"Clients see the new name"*) · `Duplicate plan` (*"Same meals, no clients"*) · `Delete plan` (laal).

**Targets card:** Calories · Protein · Carbs · Fat · Fibre · Water (`Daily`). Har target ke neeche *"Meals add up to 2,140"* ya *"Planned 150 g"* — target se door ho to amber. `Edit targets` → **modal** steppers ke saath, button `Update targets`, toast *"Targets updated — 2,150 kcal · P 150 g · C 220 g · F 65 g"* + `Undo`.

**Meals** (mock: Breakfast 8:00 am 520 · Lunch 1:30 pm 640 · Snack 5:00 pm 260 · Dinner 8:30 pm 730)

Har meal card ke upar: naam, time, calorie target, aur **option tabs** (jaise Breakfast ke `Veg` / `Eggs`; Dinner ke `Eggetarian` / `Veg` / `Eating out`). Default option pe `Default` badge — client ko wahi pehle dikhta hai.

| Control | Click pe |
|---|---|
| Meal 3-dot | `Edit meal` (*"Name, time and calorie target"*) · `Delete meal` (laal). |
| `Edit meal` | Modal: naam (*"e.g. Pre-workout"*), time, calorie target. `Save meal`. |
| `Delete meal` | Confirm: *"breakfast · 2 options"*. Toast + `Undo`. |
| `Add meal` | Wahi modal, naya meal list ke beech me add hota hai (mock: Pre-workout 11:00 am). |
| Option tab | Us option ke foods dikhte hain. |
| `Option` (+) | Menu: `Blank` (*"Empty option, add the foods yourself"*) ya `Duplicate current option` (*"Copy of Veg"*). Toast dono pe. |
| Option 3-dot | `Rename` · `Duplicate` (*"Same foods, new option"*) · `Set as default` (*"The client sees this one first"*) · `Delete option` (laal). |
| Aakhri option delete karne ki koshish | Toast *"A meal needs at least one option — Delete the meal instead"*, kuch nahi hota. |
| `Add food` | **Food picker**: team ki `Team` badge wali foods upar, group ke hisaab se list, har row pe serving + kcal + P/C/F aur `Add`. Add ho chuki food pe `Added`. Neeche `Create custom food` (text) aur `Done`. Toast *"Added Oats — Breakfast · Veg"*. |
| Food row | Food panel khulta hai: quantity + **unit dropdown** (*"Units of Oats"*, aur `Add a unit in the food library`), swaps, aur `Remove from meal` (laal text). |
| Unit badalna | Quantity apne aap convert hoti hai, toast *"Oats in grams — 1 cup → 80 g"*. |
| `Add alternative` | Same-group foods match % ke saath (*"Amounts give the same calories as 60 g"*). Add pe toast *"Alternative added — Poha for Oats"*. Koi na ho: *"No other foods in this group."* / *"No swaps. The client has to eat this food."* |
| `Remove from meal` | Toast *"Removed from Breakfast — Oats"* + `Undo`. |

Har food row pe `P … C … F …` aur swap count. Meal ke neeche total `P 42 g · C 58 g · F 18 g`. Khaali option: *"No foods yet. Use Add food to pick from the food library."*

**Client permissions** (plan pe): `Client can swap within the approved list` · `Client can search any food` · `Client can switch meal options` · `Allow off-plan meals (flagged to coach)`.

**`Assign`** → clients list, multi-select. Save pe toast *"Plan assigned — 3 clients on Cut · Eggetarian"* + `Undo`. Clients card me har client pe tag `Master` (blue) ya `Custom version` (amber).

| Client 3-dot | Kya |
|---|---|
| `Open client profile` | Client profile. |
| `Add version note` / `Edit version note` | **Modal** — *"Only for this client. The trainer and the client see it on the plan."* `Save version note`. Mock: *"Dinner: brown rice 1 × 100 g instead of 1.5. Banana before training instead of dates."* |
| `Reset to master` | *"Removes the version note"*. Toast *"Rohan follows the master again — Version note removed"* + `Undo`. |
| `Remove from plan` | Toast + `Undo`. |

Koi client na ho: *"Not assigned to anyone yet."* Hint: *"Changes to the master reach everyone. A version note keeps one client's changes."* Aur *"Clients on another meal plan move to this one. Their logged meals stay."*

**`Publish`** → **modal**: *"3 clients get the new version on their phone."* (koi na ho to *"Nobody is on this plan yet. It is saved as ready to assign."*) Points: *"1 custom version keeps its changes"* (ya *"Everyone follows the master plan"*) · *"Meals already logged stay as they are"* · *"Their trainers get a notice"*. Confirm pe toast *"Master plan published — Sent to 3 clients"*. Jab tak unpublished changes hain, header me `Publish now` dikhta rehta hai.

---

### 2.14 Habits & supplements — `Habits` / `HabitsMobile`

Title **Habits & supplements**, do tabs: **`Habits 8`** aur **`Supplements 3`**. Layout = left list, right editor (master-detail).

#### Habits tab
Sub: *"Build a habit once and assign it to many clients. Saved changes reach everyone on it."*

Left list: har habit ka naam, kind (`Tick` ya `Counter · 8,000 steps`), frequency (`Daily` / `Mon, Wed, Fri` / `3 times a week`) aur kitne clients pe hai.

Right editor: naam, **kind** (Tick / Counter — counter pe target + unit, hint *"Glasses, steps, min…"*), **frequency** (Daily / Specific days / N times a week — hint *"Any days. The week resets on Monday."*), icon (Water · Steps · Sleep · Food · Timer · Sun · Habit), aur "why" line jo client ko dikhti hai. Saath me ek **live phone preview** aur `Reset preview`.

| Control | Click pe |
|---|---|
| Kuch bhi badla | Upar bar: *"Unsaved changes"* + `Discard` + `Save changes`. Warna *"All changes saved"* aur Save disabled. |
| `Save changes` | Toast *"Changes saved — Sent to 3 clients on this habit"* (kisi pe na ho to *"Not assigned to anyone yet"*). |
| `Discard` | Sab wapas, toast *"Changes discarded"*. |
| Habit 3-dot | `Duplicate habit` (*"Same settings, no clients"*) · `Delete habit` (laal). |
| `Delete habit` | Confirm *"Delete this habit? — Drink 3 L water is removed from 3 clients. Their past logs stay."* Toast + `Undo`. |
| `Assign` | Clients list, har ek pe `On it now` / `Not on it`, multi-select. Button `Save · 3 clients`. |
| `New habit` | **Modal**: kind chips, naam (*"e.g. Drink 3 L water"*), target + unit, frequency. `Cancel` + `Create`. |

Mock habits: Drink 3 L water (counter, 12 glasses) · 8,000 steps · Sleep by 11 pm (tick) · Hit protein target (150 g) · 10 min mobility (Mon, Wed, Fri) · Morning sunlight · No sugary drinks · Strength session (3 times a week).

#### Supplements tab
Sub: *"Supplement plans with dose and timing. Save to send changes to every client on the plan."*

Left: plans (Muscle gain basics · Fat loss support · Vegetarian essentials). Right: plan ka note (*"e.g. Take creatine every day, rest days too."*) aur items **timing ke hisaab se grouped** — Breakfast · Post-workout · Any time · Before bed.

Har item pe dose (`1 scoop · 30 g`), din (saare ya kuch), aur *"with food"* mark. Item 3-dot: `Edit dose and timing` · `Remove`. Edit modal me dose (*"e.g. 5 g, 1 tablet"*), timing, days, aur toggle **"Take with food"** (*The client sees "with food" next to it*).

Neeche **quick add** chips library se: Vitamin D3 · Electrolytes · Caffeine · Iron · B12 · Fibre (psyllium) · Probiotic · Ashwagandha, aur `Custom`. Khaali plan: *"No supplements yet. Use quick add below."*

Plan 3-dot: `Rename plan` · `Duplicate plan` (*"Same items, no clients"*) · `Delete plan` (laal, confirm *"… is removed from 2 clients."*). Save / Discard bar aur `Assign` habits jaisa hi.

---

### 2.15 Forms & check-ins — `Forms` / `FormsMobile`

Title **Forms & check-ins**, sub *"Onboarding questionnaires, weekly and daily check-ins, surveys and waivers."* Header: `Create form` (primary).

**Type dropdown** (*"Form type"*): `All forms` · Onboarding · Weekly check-ins · Daily check-ins · Surveys · Waivers (counts ke saath). **Tabs:** `All 8` · `Archived 0`.

Table: form naam · type · question count · **kaun bhejta hai** (automation ka naam, jaise *"Client onboarding · on approval"* aur `+1 more`; koi automation na ho to *"Sent by hand"*) · status `Published` (green) / `Draft` (amber) / `Archived` (grey) · edited · 3-dot.

**3-dot:** `Edit questions` (→ form builder) · `Preview` · `Duplicate` · `Archive` / `Restore` · `Delete form` (laal).
- `Preview` → **modal**: form client ki tarah dikhta hai aur **asal me bhara ja sakta hai** (choice, dropdown, scale, yes/no, photo). Khaali form: *"This form has no questions yet."* Button `Close`.
- `Duplicate` → copy Draft me, toast *"Form duplicated — Saved as a draft"* + `Undo`.
- `Archive` → toast *"Form archived — It is no longer sent to clients"* + `Undo`.
- `Delete form` → confirm *"Weekly check-in is removed for good. Answers clients already sent stay in their profiles."* Toast + `Undo`.
- Khaali: *"No forms here yet — There is no form of this type. Create one to start."* / *"Nothing archived — Forms you archive show up here."*

**`Create form` modal:** pehle **type** chuno —
| Type | Line |
|---|---|
| Onboarding questionnaire | Goal, history, diet and schedule. Filled in once after registration. |
| Weekly check-in | Weight, measurements and how the week went. Sent on a schedule. |
| Daily check-in | A 30-second morning pulse: weight, sleep and energy. |
| Survey / feedback | Program feedback, ratings and quick polls. |
| Waiver / consent | Statements the client agrees to before starting. |

Fir **`Template`** (*"Starts with our standard questions. You can change every one of them."*) ya **`Blank form`** (*"Starts empty. You add every question yourself."*). Buttons `Cancel` + `Continue to builder`.

Mock forms: New client questionnaire (15 q) · PAR-Q health screening (7) · Weekly check-in (9) · Morning check-in (5) · Bridal Shred intake (7) · Monthly feedback (4, Draft) · Liability waiver (3) · Photo consent (2).

---

### 2.16 Form builder — `FormBuilder` / `FormBuilderMobile`

Header: form naam, 3-dot (`Rename` · `Duplicate` · `Archive form` · `Delete`), `Preview` (outline), `Publish` (primary).

**Question list** — har question card pe number, text, type, `Required` badge, aur choice type pe *"5 options + Other"*.

**Question 3-dot:** `Edit question` · `Duplicate` · `Move up` · `Move down` · `Delete question` (laal).

**Add question** — 9 types: `Short answer` · `Long answer` · `Number` · `Single choice` · `Multiple choice` · `Dropdown` · `Scale 1–5` · `Yes / No` · `Photo upload`. Choose karte hi question editor khulta hai.

**Question editor:** question text (*"Enter the question"*), options (choice types pe — hint *"Add at least two options."*), toggle **"Add an 'Other' option"** (*The client can pick Other and type their own answer*), help text (*"e.g. Empty stomach, same scale"*), aur toggle **Required** (*The client must answer it*). `Cancel` + save.

**Side panel:**
- **Automation** — kaun bhejta hai. Koi na ho: *"No automation sends this form yet."* Hint: *"Schedule and reminders are set in the automation."* Button `Open automations`.
- **Answers** — *"Each answer shows in the client profile under Check-ins."* Link `See Riya's answers`.

`Preview` wahi fill-able preview modal kholta hai jo Forms list pe hai.

---

### 2.17 Content library — `Content` / `ContentMobile`

Title **Content library**, sub *"Videos, articles, PDFs and images. Use them in exercises, programs and meal plans, or share them with clients."* Header: `New category` (outline) + `New content` (primary).

Left me **Categories** rail: Exercise videos · Form tutorials · Onboarding · Nutrition guides · Mindset & sleep, aur `New category` link. Right me cards grid; upar kind filter (Video / Article / PDF / Image).

Card: thumb + duration/pages badge, naam, category, kisne daala, kab, aur usage. Kahin use na hui ho: *"Not used yet"*.

| Control | Click pe |
|---|---|
| Card | **Detail drawer**. |
| Card 3-dot | `Open` · `Edit` · `Assign to clients` · `Delete` (laal). |
| `New category` | Modal: naam (*"e.g. Mobility"*), `Create category`. Toast *"Category created — Mobility"*. Nayi category turant select ho jaati hai. |
| `Delete` | Confirm: *"Bench press · setup is removed for good. It is used in exercise Bench press, program Fat Loss Phase 1, which will show no video after this."* Toast + `Undo`. |

**Detail drawer:** video player ya file preview, badge `Plays in the app` / `Opens in the app`, description/text, aur key-values (Type · Length/Pages/Format/Read time · Added by · Updated), file info (*"Uploaded 14 Sep · 12 MB · 1080p"*).
- **Shared with**: `Everyone`, ya clients ke avatar, ya *"Not assigned to anyone yet. Clients still see it inside the exercise, program or plan that uses it."*
- **Used in**: Exercise / Program / Meal plan / Form / Habit / Automation / Client ke links. Khaali: *"Not used in an exercise, program, meal plan or form yet."*
- **Stats**: opened · watched to the end (ya read/viewed/opened to the last page) · finish rate.
- Footer: `Delete` (laal text) · `Edit` · `Assign to clients`.

**New / Edit content drawer:** kind chips `Video` · `Article` · `PDF` · `Image`.
- Video: source `Upload file` ya `YouTube link` (*"https://youtu.be/…"*, hint *"Plays inside the app. Clients do not leave it."*), cover image (*"A frame from the video. Clients see it on the card."*).
- PDF: *"Drop a PDF here or click to upload — PDF up to 25 MB. Clients open it inside the app."*
- Image: *"Drop an image here or click to upload — JPG, PNG or WebP, up to 10 MB. Clients can zoom in."*
- Article: body (*"What clients read. Leave an empty line between paragraphs."*) + read time.
- Sab me: naam (*"e.g. Romanian deadlift · side view"*), category, short description (*"One or two lines clients see above the file"*), aur toggle **Everyone** (*"All current and future clients. Untick to pick clients after saving."*). File pe `Replace` button.

**Assign to clients drawer:** `Everyone` toggle (*All current and future clients*; hint *"Untick 'Everyone' to pick clients one by one."*), warna client list jisme har ek pe `Has it now` / `Does not have it`. Button `Share with everyone` / `Assign to 3 clients` / `Save, not assigned`. Toast uske hisaab se.

---

### 2.18 Automations — `Automations` / `AutomationsMobile`

Title **Automations**, sub *"Forms, messages and tasks that go out by themselves when something happens."* Header: `Message templates` (outline) + `New automation` (primary).

**4 stat cards:** Automations on `3 of 5` (2 off or draft) · Clients in a flow `43` (Waiting for their next step) · Messages this month `214` (96% delivered · 61% opened) · Tasks for trainers `9` (4 still open).

Har automation ka card: naam, trigger line (*"When a new client is approved"*), step chips (jaise `Form` → `1 day` → `WhatsApp` → `2 days` → `Task`), status badge `On` / `Off` / `Draft`, package scope, aur counts `Running` / `Finished` / `Changed`.

| Control | Click pe |
|---|---|
| Card | Automation builder (edit). |
| On/off toggle | Turant on/off, toast. |
| 3-dot | `Edit` · `Duplicate` · `Delete` (laal). |
| `Duplicate` | Copy Draft me, toast *"Automation duplicated — Saved as a draft"* + `Undo`. |
| `Delete` | Confirm: *"Weekly check-in stops for everyone in it now. Messages already sent stay sent."* Toast + `Undo`. |
| `Message templates` | Emails & alerts page. |
| `New automation` | **New automation screen** (`AutomationNew`). |

Mock: Client onboarding (On, 3 running / 41 finished) · Weekly check-in (On, 38 / 412, package *Quarterly Transformation*) · Missed workouts nudge (Off) · Renewal reminder (On) · Birthday wish (Draft).

### 2.19 New automation — `AutomationNew` / `AutomationNewMobile`

Starter list: har starter card pe naam, ek line explanation, trigger aur step count.

| Starter | Kya karta hai |
|---|---|
| Client onboarding | Sends the onboarding form on approval, reminds on WhatsApp, then asks the trainer to call. |
| Weekly check-in | Sends the check-in every Sunday, reminds after 24 hours, then gives the trainer a review task. |
| Missed check-in reminder | A short reminder flow that works with any check-in. |
| Missed workouts nudge | A friendly nudge first, then the trainer checks in. |
| Renewal reminder | Two reminders before the package ends, then a call from the trainer. |
| Welcome week | A welcome message, the health screening on day 2 and a first-week call. |
| Birthday wish | A birthday message at 9 am and a reminder for the trainer. |

Saath me ek **Blank** option. Buttons `Cancel` + `Use this` — starter chuna ho to builder usi ke steps ke saath khulta hai, blank pe khaali builder.

### 2.20 Automation builder — `AutomationBuilder` / `AutomationBuilderMobile`

Header: automation naam, status badge, `Cancel` · `Save as draft` · `Turn on` / `Save and keep on`.

**Trigger** — abhi tak na chuna ho to **15 trigger** group chips ke saath: `All` · Client · Schedule · Activity · Progress.

| Group | Trigger | Kab chalega |
|---|---|---|
| Client | New client approved | As soon as they are approved. |
| Client | Plan starts | A program or meal plan starts. |
| Client | Plan ends | Before a plan ends. |
| Client | Package ending | Before a package ends. |
| Client | Client birthday | On the client's birthday. |
| Schedule | Every week | Same day and time each week. |
| Schedule | Every day | Same time every day. |
| Schedule | On a date | Once, on a date you pick. |
| Activity | Missed check-in | A check-in is late. |
| Activity | Missed workouts | Workouts missed in a row. |
| Activity | No app activity | The app is not opened. |
| Activity | Form sent in | A client sends a form. |
| Activity | Workout streak | Workouts done days in a row. |
| Progress | Goal weight reached | Weight reaches the goal. |
| Progress | Weight not changing | Weight stays the same. |

Trigger chunne ke baad uska **settings block** aata hai (jo jis trigger ko chahiye wahi dikhta hai): weekday chips, time stepper (30 min step), date stepper, plan type (`Any plan` / `Program` / `Meal plan`), form dropdown, ya ek number stepper jiska label trigger se aata hai — *Days before the end* (0–14 / 1–30), *Not sent within* hours (6–72, 6 step), *Missed in a row* workouts (1–10), *No activity for* days (2–30), *Days in a row* (3–60), *Same weight for* weeks (1–8). Upar summary line banti rehti hai: *"When a check-in is not sent within 24 hours"*. `Change` se trigger wapas chun sakte ho.

**Who it applies to:** package scope (`Any package` / ek package) aur trainer select (`Any trainer`).

**Toggle:** *"Stop when the client responds"* — *"The remaining steps are skipped once the client sends the form or replies."*

**Steps** — har step card: number, kya hoga (*"Send the form 'New client questionnaire' by Push and Email"*, *"Wait 1 day"*, *"Task for the assigned trainer: Call the client"*), aur channel chips.

Step 3-dot: `Edit` · `Move up` · `Move down` · `Remove`.

**`Add a step`** (*"It is added after the last step"*) — 4 kinds:
| Kind | Line |
|---|---|
| Wait | Pause before the next step |
| Send message | A template by email, push, WhatsApp or in-app |
| Send form | A form or check-in from Forms & check-ins |
| Assign task | A to-do for the trainer or the owner |

Channels: `Email` · `Push` · `WhatsApp` · `In-app` (multi). Form step me `Open forms & check-ins` link, message step me `Edit message templates` link. Khaali: *"No steps yet. Add what should happen after the trigger."*

**Right panel — preview:** *"This is what will happen for each client it applies to."* Trigger line + har step ek plain line.

**Save karte waqt:**
- `Save as draft` → toast *"Saved as a draft — Turn it on when it is ready"*.
- `Turn on` → agar kuch adhoora hai to toast *"Not ready to turn on — <pehli problem>"* aur kuch nahi hota; sab theek ho to toast *"Client onboarding is on — It starts with the next trigger"*.

**Runs** (existing automation pe): `41 started` · `36 finished` · `5 stopped early`, aur log rows — Riya Sharma *"Sent the form · stopped at step 1"* 2 d ago, Neha Jain *"Waiting · step 2 of 5"*, Ishaan Mehta *"Trainer task made · step 5"*, Sana Khan *"Finished"*. Naya automation: *"No runs yet. Clients show up here once it is on."*

---

### 2.21 Emails & alerts — `Emails` / `EmailsMobile`

Title **Emails & alerts**. Header: `Automations` (outline) + `New template` (primary). Teen tabs:

#### Tab 1 — `Client messages`
Sub: *"The messages clients and trainers get, per channel. Change the words once and every send uses them."*

Left me templates groups ke hisaab se (**Access** · **Coaching** · **Packages**): Client invite · Welcome · Password reset · Onboarding form reminder · Check-in reminder · Missed workouts nudge · Coach feedback · Birthday wish · Renewal reminder · Trainer invite. Apna banaya ho to `Custom` badge. Har row pe 4 channel dots (`Email · on` / `Push · off` …).

Right me editor:
| Control | Click pe |
|---|---|
| Channel tabs `Email` · `Push` · `WhatsApp` · `In-app` | Us channel ka text. Dot batata hai on hai ya off. |
| `Send by Email` toggle | Off channel on karte hi default text aa jaata hai aur toast *"Email turned on — Write the text and save"*. On ko off karo to *"Off: this message is not sent on this channel."* |
| Subject / Title field | Email pe `Subject`, push/in-app pe `Title`, WhatsApp pe koi nahi. Counter `Subject 32 / 50`. |
| Message body | Counter: push 120, WhatsApp 1000, email 2000. |
| `Insert a variable` | `{{first_name}}` · `{{coach_name}}` · `{{gym_name}}` · `{{package_name}}` · `{{date}}` — click karte hi body ke end me lag jaata hai. |
| `Reset to default` | Standard text wapas. |
| `Delete template` (laal text) | Sirf custom templates pe. |
| `Save` | Save; upar *"Saved"* / *"Not saved yet"*. |
| `Open automation builder` | Jo automation is template ko bhejta hai. |

Right-bottom me **live preview** — email card / phone push / WhatsApp chat (header me *Train With Vimal*) / in-app notice, jisme variables bhare hue hain. Hint: *"How Sana, a sample client, would see it. Variables are filled in for each person."* Channel off ho to: *"There is no Email text for this message yet. Turn it on to write one."*

**`New template` modal:** naam (*"e.g. Workout streak"*), group (`Access` / `Coaching` / `Packages`), aur channels multi-select —
| Channel | Line |
|---|---|
| Email | Subject and a longer message |
| Push | Short title and text on the phone |
| WhatsApp | From your WhatsApp number |
| In-app | In the app's notifications |

Hint: *"You can turn channels on or off later in the editor."* Koi channel na chuna to `Create template` disabled aur toast *"Pick a channel — A template needs at least one"*.

#### Tab 2 — `Team alerts`
Sub: *"Alerts for you and your trainers when something happens."* Events: **New client** (Sign-up or invite accepted) · **Check-in submitted** (Weekly check-in by a client) · **Plan updated** (Trainer edits a program or meal plan) · **Missed workout** (2+ workouts skipped in a row). Har event pe channel toggles.

**Quiet hours:** *"No push or WhatsApp at night. Emails wait in a queue."* — from `10:00 pm` to `7:00 am`.

#### Tab 3 — `Sender`
Sub: *"Who clients see as the sender of emails and WhatsApp messages."* **Sender identity**: Sender name (`Train With Vimal`, *"Your gym or coaching name"*) · Reply-to email (`hello@trainwithvimal.com`, *"Client replies to emails land here"*) · WhatsApp number (`+91 98200 12345`, *"Shown in the WhatsApp chat header"*).

---

### 2.22 Settings — `Settings` / `SettingsMobile`

Title **Settings**, tabs ke saath.

**Gym profile** — naam · email · phone · address (`2nd floor, Linking Road, Bandra West, Mumbai 400050`) · Instagram. Button `Save changes`.

**Regional & defaults** — timezone (`Asia/Kolkata (IST)`) · language (`English`).

**Branding** — logo (`Upload logo` / `Remove`; toasts *"Logo uploaded — logo-trainwithvimal.png · 512 x 512"* aur *"Logo removed — Your initials show until you upload a new one"*), accent colour (*"Buttons, links, progress bars and the selected tab use this colour."*), theme (`Light` / `Dark` / `Match phone`). Bagal me **live phone preview** (*"Good morning, Sana"* + `Start workout`). Hint *"Changes show for every client after Apply."* Buttons `Reset` (toast *"Branding reset — Blue and light theme"*) + `Apply` (toast *"Branding applied — Clients see it next time they open the app"*). Status: *"Applied"* / *"Not applied yet"*.

**Roles & permissions** — teen role cards:
| Role | Kaun | Kya |
|---|---|---|
| Admin | Owner · only one · you | Everything: clients, trainers, plans, content and settings. *"There is exactly one admin per gym. Ownership cannot be moved from inside the app, and trainers cannot be given admin access."* |
| Trainer | 11 members | Assigned clients, programs, meal plans, daily and weekly check-ins. *"A trainer's access level is set on the trainer's own profile."* → `Open trainers` |
| Client | 142 active | Own plan, logging and check-ins. *"Clients only ever see their own plan and data."* → `Open clients` |

Permission matrix (Admin / Trainer / Client columns) — View all clients · View assigned clients · Assign / reassign clients · Create programs & meal plans · Daily + weekly check-ins · Manage content library · Schedule sessions · Add trainers · Automations & settings. **Admin column hamesha ticked aur locked.** Tick karte hi *"Not saved yet"*; `Save` pe toast *"Permissions saved — Applied to every trainer and client"*. Footer: *"The admin always has every permission. Changes apply to every trainer and client."*

**Integrations** — teen cards, har ek pe status badge aur `Connect` / `Manage`:
1. **WhatsApp** — steps: *Connect a business number* (The number must be registered with the WhatsApp Business API) · *Display name review* (Meta reviews the display name, usually within 24 hours) · *Message templates* (Reminders and nudges are sent from approved templates). Connected pe `+91 98200 12345`.
2. **Email domain** — steps: *Add your domain* (e.g. trainwithvimal.com) · *Add three DNS records* (SPF, DKIM and DMARC go into your domain provider — GoDaddy, Hostinger and others) · *We verify the records* (DNS changes take 15 minutes to 48 hours. Until then emails keep going from the platform address). DNS table: SPF `TXT · @` **Verified** · DKIM `TXT · twv._domainkey` **Verified** · DMARC `TXT · _dmarc` **Waiting**. Button `Check records again`, toast *"Checking the DNS records — We will email you when all three are verified"*.
3. **Health app** — client health data sync, toggles kis-kis cheez ka. Connected pe `64 clients linked`.

Har integration drawer me `Disconnect` (laal text) → **confirm modal**: WhatsApp *"Automations and messages stop sending on WhatsApp. Email and push keep working."* · Email *"Emails go back to the platform address."* · Health *"Client health data stops syncing. Past data stays."* Buttons `Keep it` + `Disconnect`. Toast + `Undo`.

---

### 2.23 Client profile — `ClientProfile` / `ClientProfileMobile`

**Built (D-47):** the trainer client profile with admin extras — menu `Change trainer`, Coaching card Trainer row `Change` / `Pick one`, Edit details → Sign-in (New password, at least 8 characters; `Send a reset link`) and Trainer line. A new password signs the client out everywhere and sends a notice.

Ye poore admin area ka **sabse bada screen** hai. Breadcrumb `Clients / Riya Sharma`.

**Header** — avatar `RS`, naam **Riya Sharma**, badge `Active`, sub line *"Fat loss · 68 kg goal"*. Buttons:

| Control | Click pe |
|---|---|
| `Edit profile` | Drawer — client ki details (naam, phone, email, gender, DOB, goal, starting weight, goal weight, trainer, joined date) |
| `Assign plan` ▾ | Menu: `Workout plan` · `Meal plan` · `Supplement plan` · `Habit plan` — plan picker drawer khulta hai |
| ⋯ 3-dot | `Edit profile details` · `Change trainer` · `Assign a plan` · `Send check-in reminder` · `Full history` |

**4 stats cards** — `86%` adherence · `71.2 kg` current weight · `14 of 16` workouts · `6 of 7` check-ins.

**9 tabs** — `Overview` · `Plans` (4) · `Logs` · `Progress` · `History` · `Content` (8) · `Forms` (4) · `Activity` · `Notes` (4).

#### Overview tab
Cards: **About Riya** (goal, trainer, plan, joined) · **Weight trend** (chart, range picker) · **Last 7 days** grid (din-wise workout/meal/check-in tick) · **Latest note** · **Needs attention** (missed cheezein) · **Coaching** (trainer + next session) · **Current plans** (4 plans ki list) · **Check-ins and schedule**.

Range picker har chart pe: `Last 7 days` · `Last 30 days` · `Last 90 days` · `Last 6 months` · `Since start` · `Plan: Fat Loss Phase 1` · `Plan: Beginner Full Body` · `Custom dates…` (custom pe do date field khulte hain).

#### Plans tab
Chaar plan slots — `Workout` · `Meal plan` · `Supplements` · `Habits`. Har plan card pe:

- Badge batata hai plan master se kitna alag hai — `Edited for Riya` / `Changed for Riya` / `Edited in program`.
- ⋯ menu: `Duplicate and edit` · `Replace with another plan` · `Reset to master` · `Open master plan` · `End this plan`.
- `Reset to master` pe **confirm modal** — Riya ke liye kiye gaye saare change chale jayenge.
- Card ke neeche **Up next** (agla week / agla plan) aur **Plan history** (purane plans, date range ke saath).

Plan editor do tarah se khulta hai:
1. **`Edit X for Riya`** — sirf Riya ka copy badalta hai, master program nahi.
2. **`New plan for Riya: copy of X`** — naya plan, aur checkbox `Also save to the library as a new master plan`.

`Compare plans` button → **A/B view**, do plans side by side, farq highlight. A aur B har ek plan **ya** period ho sakta hai (`Last 30 days`, `Previous 30 days`, `This plan: first half / second half`, `Custom dates…`). Ek hi plan ho to default A = Previous 30 days, B = Last 30 days (koi "Nothing to compare yet" toast nahi).

#### Logs tab
Chhe sub-tabs — `Workouts` · `Meals` · `Daily check-ins` · `Weekly check-ins` · `Habits` · `Supplements`. Har sub-tab me date-wise list; row pe click karke us din ka poora log khulta hai (sets, reps, weight / food aur macros / answers + photos). Workout volume me bodyweight sets bhi count hote hain (us din ka body weight — us din ya pehle ka latest weigh-in — + added load). Meal Amount = quantity × unit + grams ("2 pieces (80 g)", "1 katori (150 g)", "150 g"). Meals-a-day / adherence client ki copy aur us weekday ke meals se (D-37). Range picker ka `Custom dates…` chhota modal kholta hai (do mahine ka calendar; phone par sheet). Export abhi band (17 Oct).

#### Progress tab
Weight, measurements aur progress photos. Photo compare (pehle / ab, side by side).

#### History tab
Ek timeline — plan assign hua, trainer badla, plan end hua, check-in hua, pause hua. Same timeline component jo Activity log, trainer profile aur client profile teeno me use hota hai.

#### Content / Forms / Activity / Notes tabs
- **Content** (8) — jo library items Riya ko share kiye gaye; `Share content` se picker khulta hai, row pe `Unshare`.
- **Forms** (4) — bheje gaye forms, status `Filled` / `Waiting`; `Send a form` se picker.
- **Activity** — Riya ne app me kya kiya.
- **Notes** (4) — trainer ke private notes; `Add note` se composer khulta hai, note pe `Edit` / `Delete`. Clients ko notes kabhi nahi dikhte.

**Mock data** — Riya Sharma, `Active`, *Fat loss · 68 kg goal*. Stats: `86%` (*+4% vs last month*) · `71.2 kg` (*−3.6 kg since start*) · `14/16` (*Done in last 30 days*) · `6/7` (*Week 6 waiting for review*).

Overview cards ka exact content:
- **About Riya** — cap *"From onboarding · edit in Edit profile"*, `Edit` link.
- **Weight trend** — *"−3.6 kg in 30 days · 3.2 kg to goal"*, chart pe `Goal 68 kg` line, `Open progress`.
- **Last 7 days** — cap *"What Riya did each day"*, Fri→Thu columns, rows `Workout` / `Meals` / `Check-in` / `Habits`, `Open logs`.
- **Latest note** — cap *"Staff only"*, `AV` ne likha, `All notes`.
- **Needs attention** — *Knee pain on deep squats* (flag · use box squats until cleared) · *Week 6 check-in to review* (sent Sun, 4 Oct · 3 photos) · *Missed Upper B on Monday* (first miss in 3 weeks).
- **Current plans** — *Fat Loss Phase 1* (workout · week 6 of 12 · edited for Riya) · *1,650 kcal · high protein* (meal plan · 5 meals · veg) · *2 supplements* (Whey protein, Vitamin D3) · *3 habits* (8k steps, 3 L water, sleep 7 h). `Open plans`.
- **Check-ins and schedule** — *Daily check-in* every morning 8:00 am, weekly check-in, next session.

Forms jo bheje ja sakte hain: `Weekly check-in` (weight, energy, meals, photos · 6 questions · **Sending**) · `Monthly feedback` (how happy she is with coaching · 3 questions · sent 1 Oct) + onboarding aur PAR-Q.

Naya plan assign karte waqt **kab shuru ho** poochha jata hai — `After current ends` (*"Starts when Fat Loss Phase 1 ends on <date>. It shows as Up next till then."*) ya turant (*"Starts tomorrow. Both plans run together."*).

---

### 2.24 Trainer profile — `TrainerProfile`

> **Built 2026-10-22 (D-48), route `/trainers/<id>?tab=overview|clients|access|activity|documents|visible`** (`&assign=1` opens Assign clients). Reuses the trainer's My profile tabs with an admin mode (texts name the trainer, Edit details adds Work and Login sections, documents get Mark as verified). Clients tab: search, Status and Goal filters, ⋯ Open profile / Move to another trainer. Access tab: level cards, summary, permission grid, changed rows in amber, Save. ⋯ menu: Access, Send password reset link, Move all clients, Deactivate / Reactivate (not for the owner).

Breadcrumb `Trainers / Aman Verma`. Header: `AV`, **Aman Verma**, badge `Active`, sub *"Strength, fat loss"*.

| Control | Click pe |
|---|---|
| `Edit details` | Drawer — naam, phone (+91), email, gender, DOB `14 / 02 / 1994`, city, speciality (comma se), experience (*Since 2020*), mode (`Gym and online`), languages, *"works best with"*, Instagram / YouTube / page link / website, max clients (`30`, hint *"He has 24 now"*), joined date. Toggle `Send password reset link` (*"He gets a link on WhatsApp and email"*). Footnote *"Access is changed in the Access tab"*. Buttons `Cancel` + `Save` |
| `Assign clients` | Drawer — unassigned ya doosre trainer ke clients ki list (Sana Khan *no trainer*, Farhan Ali *from Karan Mehta (full)*…), toggles `Tell the clients` (push *"Aman Verma is your trainer now"*) aur `Keep their current plans` (*"Aman can change them later"*) |
| ⋯ 3-dot | `Access and permissions` · `Send password reset link` · `Move all clients to another trainer` · `Deactivate Aman` (laal) |

**4 stats** (web: 4 barabar cards ek line me, page 760 se patla ho to 2 × 2; height content jitni, kam se kam 80) — `24 / 30` clients (*6 spots free*) · check-ins to review (*Oldest from yesterday*) · `84%` adherence (*+2% vs last month*) · `3 h` reply time (*Team average 4 h*).

**6 tabs** — `Overview` · `Clients` (24) · `Access and permissions` · `Activity` · `Documents` (6) · `What clients see`.

#### Overview
Cards: **Professional details** (cap *"Shown to you when you pick a trainer"*, chips `Strength` `Fat loss` `Powerlifting`, `About Aman`, `Social media`, `Edit` link) · **Contact and account** · **Certificates** (cap *"3 of 4 verified · one expires soon"*, `All documents`) · **This week** (`Mon 5 – Fri 9 Oct` schedule) · **Clients who need him** (*"From his 24 clients"*, `All clients`) · **Recent activity** (`All activity`).

#### Clients tab
Table + `Filter` — `Status` (Any / Active / At risk / Paused / Pending) aur `Goal` (Any / Fat loss / Muscle gain / Strength / Recomp). Row ⋯: `Open profile` · `Move to another trainer`.

#### Access and permissions tab
**Access level** (cap *"Pick a starting point, then switch single permissions below"*) — teen cards:
- `Assigned clients` — *"Only the clients you give him: plans and check-ins. Default for new trainers."*
- `All clients` — *"Sees and can cover every client of the gym. For senior trainers."*
- `Custom` — *"Switch each permission on or off below."*

Neeche permission groups (default on = ✓):

| Group | Permissions |
|---|---|
| Clients | View assigned clients ✓ · View all clients · Approve sign-ups (*only people invited by him*) · Pause or resume clients |
| Training | Create and edit programs ✓ (*for his clients*) · Use gym templates ✓ (*copy master programs*) · Edit gym templates (*changes master programs*) · Add custom exercises ✓ |
| Nutrition | Meal plans ✓ · Add foods and recipes ✓ · Supplement plans ✓ · See food logs ✓ |
| Check-ins | Review daily check-ins ✓ · Review weekly check-ins ✓ · Edit check-in forms (*changes master forms*) · Progress photos ✓ |
| Schedule | Manage own calendar ✓ · Book sessions for clients ✓ |

Koi bhi toggle badalne pe **Summary** card aur `Undo changes` button aa jate hain; save karne pe toast. (Community, challenges, payments aur chat ke permissions board me parked hain — feature on hone pe wapas aayenge.)

#### Activity tab
Cap *"What Aman did in the app"*, filter + date range, `Show more`. Khali pe *"Nothing matches. Try a longer date range or fewer filters."*

#### Documents tab
`Upload document` → drawer: kind select (`Certificate` / `ID proof` / `Contract`), naam (`Kettlebell Level 1`), issuer (`StrongFirst`), issue `MM / YYYY`, expiry `MM / YYYY or no end`, visibility select (`Admins and clients`, hint *"Only after you mark it verified"*), toggle `Remind me before it expires` (*"30 days before, on the Dashboard"*), `Upload`.

Mock docs: ACE CPT (Verified) · Precision Nutrition L1 (Verified) · First aid and CPR (**Expires in 33 days**, warning) · K11 Diploma (**Not checked**) · Aadhaar card (Verified, admins only) · Trainer agreement (Signed).

Doc pe click → **viewer**: zoom, `Page 1 of 1`, ID numbers masked (`XXXX XXXX 4821`, *"Numbers are hidden in the preview"*). Note *"Check the name and dates on the file, then mark it verified. Until then clients do not see it."* Buttons `Mark as verified` · `Replace file` · `Delete` (laal).

#### What clients see tab
Cap *"On 'My trainer' in the client app"*. Har field ka toggle + **live preview** (*"Live preview · what Riya sees"*), hint *"Changes here show up in the client app right away."*

| Field | Default | Note |
|---|---|---|
| Photo and name | On, **locked** | *"Clients always see this"* — `Always` |
| Speciality | On | Strength, Fat loss, Powerlifting |
| Experience | On | 6 years |
| About | On | Short bio |
| Languages | On | Hindi, English |
| Certificates | On | *"Only verified ones you allow"* |
| Social media | On | Instagram, YouTube |
| Mobile number | **Off** | *"Only you and admins see it"* |
| Email | **Off** | — |

---

### 2.25 More (phone only) — `AdminMoreMobile`

Phone pe sidebar nahi hota, isliye bottom bar ke 5 tabs ke baad baaki sab yahan. Title **More**, groups me plain rows:

- **Pages** — Trainers · Activity log
- **Build** — Programs · Exercises · Nutrition & foods · Habits & supplements · Forms & check-ins · Content library
- **Engage** — Automations · Emails & alerts
- **Workspace** — Settings · Log out

---

## 3. Trainer area

Trainer login karta hai to usko **apna workspace** milta hai. Sidebar me brand ke neeche *"Trainer workspace"* likha hota hai aur list chhoti hoti hai: `Dashboard` · `My clients` · `Check-ins` · `Calendar` · `Me`. Phone pe bottom bar ke 5 tabs ke baad baaki `More` me.

**Golden rule** — trainer ko sirf uske diye gaye clients dikhte hain (jab tak admin ne `All clients` access na diya ho), aur gym settings, trainers, automations, emails usko **kabhi** nahi dikhte.

---

### 3.1 Trainer dashboard — `TrainerDashboard` (built, D-30, D-31)

Title time ke hisaab se — *"Good evening, Aman"*, neeche *"Friday, 16 October · 10 clients · 5 sessions today"*. Top right: bell (laal dot jab unread), `New session` (web par `AV` profile button nahi, Gautam; My profile sidebar me hai).
Phone (`TrainerDashboardMobile`): blue hero status bar ke neeche tak (date · Trainer workspace, bell, `+`, `AV`, greeting, picture), uske kinare par 4 numbers ki strip.

**4 stats** — `My clients` 10 / 30 (*20 spots free*; sirf active clients) · `Check-ins to review` (*"N waiting over 48 hours"* ya *"None waiting long"*) · `Workouts done` (last 7 din, *"+4% vs last week"*) · `Avg reply time` (*"Team average 2.1 h"*).

| Card | Kya hai | Click pe |
|---|---|---|
| **Today** | Aaj ki sessions (time, length, client, `Push A · Gym floor` / `Video call`). Badge `Done` / `Missed`; agla session blue row + *"In 40 min"*. Cap *"N left"* / *"All done"* | ⋯ menu: `Mark as done` (alag Done button nahi, Gautam 18 Oct) · `Mark as missed` · `Mark as not done` · `Open client profile` · `Cancel session` (laal → toast *"Session cancelled · <name> gets a message in the app"* + `Undo`). Khali pe *"No sessions left today."* `Calendar` link |
| **Clients who need you** | cap *"Only your clients"*, chips `All` · `Missed workouts` · `Not logging` · `Plan ending` · `Feeling low` (count ke saath, ek line me sideways scroll). Ek client ek hi row (sabse bada reason). 4 rows, phir `Show N more` | `Remind` → toast *"Reminder sent to Kabir · Push and WhatsApp"* + `Undo` (Undo tak reminder ruka rehta hai), button `Reminded`. `Plan next` / `Open` / naam → client profile |
| **Check-ins to review** | Sabse purane 5 (weekly, daily, monthly) — *"Riya Sharma · Weekly check-in"*, *"Weight 61.8 kg · energy 3/5 · knees sore"*, age badge (laal 48 h+, peela 24 h+). Count = pura queue (Check-ins page aur sidebar badge jaisa). Khali: *"All check-ins reviewed"* | Row → review drawer: 4 numbers, week ke jawab + last week, *"Riya wrote"*, photos, reply + 3 quick replies. `Open profile` · `Close` · `Mark reviewed` / `Send and mark reviewed` → toast *"Riya’s check-in reviewed · Your reply was sent / Moved out of your list"* + `Undo`. `View all` → Check-ins |
| **This week** | `Mon 12 – Fri 16 Oct`: Sessions held, Check-ins reviewed, Plans changed, New clients | `My profile` link |
| **Activity** (Gautam ne add karwaya, board me nahi) | *"You and your clients"*: trainer aur uske clients ne kya kiya, naya sabse upar — check-in bheja, workout khatam, session book / cancel, plan badla, reminder. Har row: kind ka gol dot (check-in blue, plan purple, client logs green, session amber), *"Tanya Arora sent Weekly check-in"*, neeche client · item, right me time (`21:28` / `Yesterday` / `3 days ago`). Latest 10 rows, Show more nahi (Gautam). Web par right column me Check-ins ke neeche; This week left me Clients who need you ke neeche. Sirf apne clients | client line → client profile `View all` → My profile · My activity. |

Review drawer ki Photos: photo par click → full screen (zoom, swipe), title *"Riya’s photos"*.

**Bell** — *Notifications* list (unread blue), `Mark all read`; check-in wali notice review drawer kholti hai.

**`New session` modal** — Client (sirf apne active clients), Day (aaj + 13 din), Time (15 min steps), Length `30 / 45 / 60 / 90 min`, Where `Gym floor` / `Video call`, note (*Bring your lifting belt*). `Cancel` + `Add session` → toast *"Session added · Neha Jain · today 17:30"* + `Undo` (bina client message ke cancel). Day / Time list jis taraf jagah ho us taraf khulti hai, screen ke andar rehti hai, scroll hoti hai aur chuna hua din / time beech me dikhta hai.

---

### 3.2 My clients — `TrainerClients` (built, D-32)

Title **My clients**, sub *"13 clients given to you · 10 active · 2 at risk"* (sirf apne clients). Top right par AV nahi (Gautam).

Tabs `All` · `Active` · `Pending` · `Paused` · `At risk` (counts `clients/counts/` se). Search *"Search name or email"* (naam, email, phone; 300 ms baad). `Filter` (`Filter · 1` jab koi laga ho): Goal · Onboarding · Next check-in (`Today`, `This week`, `Overdue`) · Joined — har row par uski abhi ki value aur `›`; row par mouse le jao (ya click) to options menu ke left me khulte hain (`.dr-submenu`, jagah na ho to right), chuni value par ✓. Neeche `Clear filters`. Phone: Filter sheet, group par tap → options ki sheet. **Export aur select boxes abhi band hain** (Gautam, 16 Oct: "abhi need nahi hai"); code comment me rakha hai, API `clients/export/` hai.

Table (web) — client (avatar + naam + email; naam → profile) · Goal · Status badge (`Active` / `Pending` / `Paused` / `At risk`) · Onboarding bar (`Done` / `40%` / `Not started`) · Phone (`+91 98201 11234`) · Next check-in (`Sun, 18 Oct`, `Today`, laal `Overdue`, `Paused`, `—`) · Last active (`2 h ago`) · ⋯. Columns se patla page ho to table side me scroll hoti hai (board jaisa). 8 rows ek page, pager *"Showing 1–8 of 13"*.
Phone (`TrainerClientsMobile`): ek line ek client — avatar, naam, goal, badge, ⋯; Filter icon button; menu bottom sheet.

Row ⋯ menu: `View profile` (`/clients/<id>`, TrainerClientProfile abhi bana nahi) · `Edit details` → **Edit details drawer**: Must have (Full name*, Mobile* `+91`), Good to have (Email, Gender, Date of birth — box par click se date picker, City), Goal and body (Goal, Goal weight, Height, Current weight, Injuries or health notes). `Cancel` + `Save changes`; Mobile 10 digit (6–9 se shuru), Email sahi format, Goal / Current weight 25–300 kg, Height 100–250 cm — warna field ke neeche error; dusre account ka number bhi. Save par toast *"Riya’s details saved"*.

Board me Add client aur Invite link drawers hain par unhe kholne ka button board par nahi hai, isliye trainer app me nahi banaye (admin Clients page me aayenge).

---

### 3.3 Check-ins — `TrainerCheckins` (built, D-35)

Title **Check-ins**, subline *"4 to review · oldest from 2 d ago"* (sab ho gaye to *"All check-ins reviewed"*). Sirf trainer ke apne clients (`staff_submissions` → `visible_clients`).

**Web (900+)**: ek card me do hisse — left 360 wide list, right khula check-in. **Phone**: list; row par tap → `/checkins/<id>` usi card me check-in khulta hai, `‹` se wapas list (wahi tab, type, rows).

**List**: tabs `To review` (count) · `Reviewed` · `All`; search *"Search client"* (naam, 300 ms baad); type chips `All types` · `Weekly` · `Daily` · `Monthly` har ek par us tab ka count (`checkins/counts/` → `kinds`). Row: avatar · naam · age (`2 d` / `6 h` / `12 min`, 48 ghante se purana laal) · kind (`Weekly check-in`) · summary (*"Weight 61.8 kg · energy 3/5 · knees sore"*) ya reviewed par ✓ *"Replied: …"*. Naye pehle, 30 ek baar me, `Show more` (cursor). Khali: *"All caught up"* / *"New check-ins show up here as clients send them."*; filter / search par *"Nothing here"* / *"Try another type."*. Kuch select nahi: *"Pick a check-in"* / *"Its answers show here."*.

**Khula check-in**: avatar + naam (profile link) · *"Weekly check-in · sent Tue 6 Oct, 7:40 pm · Fat Loss Phase 1 · week 6"* · `‹` `›` (list me upar / neeche) · `Open profile` (`/clients/<id>`).
- 4 numbers: weekly / monthly → `Weight` · `Change` · `Workouts` · `Meals on plan`; daily → `Sleep` · `Energy` · `Workout` · `Steps`. Behtar hua to hara, kharab to laal (Change: goal weight ki taraf gaya to hara).
- **Answers** *"Compared with last time"*: har jawab ke saath pichhli baar ka (`last 4`, `same`), hara / laal usi rule se (hunger, soreness, stress kam = behtar).
- *"Riya wrote"* box, **Photos** (*"3 photos · click to open"*, full screen viewer).
- **Your reply** (ⓘ *"The client gets your reply in the app with their check-in. To change their plan, open their profile."*): box *"Write a short reply for Riya…"* + 3 quick replies (`Great week, keep going!` · `Let’s talk at your next session.` · `I’ve updated your plan.`). Draft check-ins badalne par bhi rehta hai.
- Neeche *"3 more to review after this"* + `Mark reviewed` (reply likha ho to `Send and mark reviewed`). Toast *"Riya’s check-in reviewed"* + `Undo`; To review me agla apne aap khulta hai (phone par list par wapas).
- Reviewed: hara box *"Reviewed Tue 6 Oct, 8:10 pm"* + reply + `Mark as not reviewed` (wapas To review me).

Dashboard ka review drawer, sidebar count aur yeh page ek hi `checkins/counts/` aur `review/` API use karte hain, isliye numbers same rehte hain.

---

### 3.4 Trainer calendar — `TrainerCalendar` (built, D-38)

Admin calendar ka trainer version — sirf apni sessions. Title **Calendar**, buttons `My working hours`, `New session`, `Today`.

Session pe click → panel: `Open profile` · `Reschedule` · `Mark as done` / `Mark as not done` · `Cancel session` (laal).

**Cancel confirm** — toggle `Tell the client` (*"Push notice and WhatsApp with the time that was cancelled"*), buttons `Keep it` + `Cancel session`.

**New session drawer** — client (hint *"Only clients given to you"*), date, time, length (`min`), place `Andheri gym floor` (hint *"Where they meet"*), video link `meet.google.com/abc-defg-hij` (*"Optional"*), note *"e.g. Check the left shoulder first"* (hint *"Optional. Only you and Vimal see it."*), toggle `Tell the client` (*"Push notice and WhatsApp with the time and place"*).

**My working hours drawer** — har din ke slots, `Day off` mark kar sakte hain. Footnote *"Booked sessions stay as they are"*, button `Save availability`.

---

### 3.5 Me — `TrainerMe` (built, D-38; tabs at `/me/<tab>`)

Trainer apni hi profile dekhta hai. Header `AV` · **Aman Verma** · `Active` · *"Strength, fat loss"* · button `Edit my details`. Wahi 4 stats jo admin ke trainer profile pe hain.

**6 tabs** — `Overview` · `Documents` · `What clients see` · `My access` · `My activity` · `Account`.

Admin ke trainer profile se **farq**:

| Cheez | Admin ko | Trainer ko |
|---|---|---|
| Professional details cap | *"Shown to you when you pick a trainer"* | *"Clients see only what you switch on in What clients see"* |
| About field | `About Aman` | `About you` |
| Access tab | `Access and permissions` — toggles badal sakta hai | `My access` — **read only**, cap *"Ticked ones are on for you. The rest only Vimal can switch on."* |
| Access badalna | Direct | Button `Ask for more access` → request bhejta hai |
| Clients tab | Hai, `Assign clients` button ke saath | Nahi — `My clients` page hi hai |
| Account tab | Nahi | Hai |

**`Ask for more access` drawer** — options: `See all clients` (*"To cover other trainers"*) · `Edit gym templates` (*"Change master programs and meal plans"*) · `Edit check-in forms` (*"Change the gym's forms"*) + reason box. Request Vimal ko jati hai.

**Account tab**:
- **Password** — cap *"Last changed 3 months ago"*, `Change password`.
- **Where you are logged in** — `Android app · Pixel 7` (*Mumbai · active now*, badge `This device`) · `Chrome on Windows` (*Mumbai · yesterday, 6:10 pm*) · `Safari on iPad` (*Pune · Sat 3 Oct*). Har ek pe `Log out`, upar `Log out of all others`.
- **Notifications** — cap *"Push to your phone and email"*. Toggles: `New check-in` (*"When a client sends a check-in"*) · `Missed workouts` (*"When a client misses 2 in a row"*) · `New client` (*"When the admin gives you a client"*) + baaki.

---

### 3.6 Client profile (trainer view) — `TrainerClientProfile` (built, D-34)

`/clients/<id>?tab=overview|plans|logs|progress|history|content|forms|activity|notes`. Breadcrumb `My clients / Riya Sharma`. Header: avatar, naam, status badge, *"Fat loss · 62 kg goal · Your client since 3 Sep · Active 6 h ago"*; `Edit profile` (Edit details drawer), `Assign plan ▾` (Workout plan · Meal plan · Supplement plan · Habit plan → assign drawer), `⋯` (Edit profile details · Assign a plan · Send check-in reminder · Full history). 4 stats: Adherence, Weight, Workouts, Check-ins. Phone: stats ek card me 4 column, tabs side me scroll.

- **Overview** — About Riya (onboarding se), Weight trend (`Open progress`), Last 7 days, Latest note, Needs attention (row → us tab), Coaching, Current plans (→ Plans), Check-ins and schedule.
- **Plans** — `Workout` · `Meal plan` · `Supplements` · `Habits` + `Assign new plan`. Current plan card (`Current`, `Edited for Riya`, `Edit for Riya`, ⋯ Duplicate and edit · Replace · Reset to master (confirm) · Open master plan · End this plan (confirm)), Up next (`Change` / `Choose next plan`), Plan history (5, `Show all`). Workout: din ki strip, exercise rows (A1/A2, `Changed for Riya`), row → exercise drawer. Assign drawer: plan chuno → preview → *When does it start* (After current ends · Next to current · Replace current · Pick a date) → options (`Edit Riya's copy before she sees it`, `Tell Riya in the app`) → `Assign plan`. Editor me Save Riya ki apni copy banata hai; ek din badla to aage ke har hafte ka wahi din badalta hai. Workout editor: din ke exercises ki list (sets × reps · RPE · tempo · rest · load · note) + `Swap` / `Edit` / `Remove`; `Edit` (ya row tap) = *Edit exercise* drawer (Sets, Reps, RPE, Tempo, Rest, Load, Note, `Swap`, Previous / Next, `Done`). *Coach note for this day* 4 line. Exercise drawer me video / YouTube wahi chalta hai, picture tap = full screen, neeche likha *Video · YouTube link · Picture · Web link*. Meal plan `Edit for Riya` = meal editor (board `pe.meal`): din ki strip (har din ke apne meals; neela dot = us din ke apne meals), `Apply to every day`, Daily target + *"Tuesday adds up to …"* (On target / over / under), meal cards (⋯ Rename meal · Change time · Remove meal, foods P / C / F / kcal, `Add food` drawer), `Add meal`, *Portion and swaps* panel (− amount +, units menu *UNITS OF …* + *+ Add a unit in the food library*, grams/macros, *Swaps Riya may use* with match % and ×, `+ Add alternative` popover *Pick an alternative* Same group / All foods, *"Amounts give the same calories as …"*, `Remove from this meal`; tablet par side panel, phone par sheet; D-37). Food rows: `N swaps` / `No swap` badge, badla food neela dot + *Was: …*. `Add food` / `Add exercise` / `Add superset` drawers: compact rows with lines, search aur tabs upar ruke, sirf list scroll. Supplements `Edit for Riya` = supplement editor (Supplement, Dose, When, How to take, Stock at home; `Add supplement`; `Reset to master`) — sirf Riya ki copy (D-37). Unsaved din badlo to *"Save Tuesday first?"*. Save sirf Riya ki copy badalta hai; `Reset to master` copy hata deta hai. Version note modal nahi hai. `Edit habits` me har habit par `Edit` (Target, How often: Every day / On some days / Times a week, Note for Riya) — sirf Riya ke liye. Assign drawer: tabs content jitne chhote, list board jaisi (lines ke saath, ~6 rows phir andar scroll), workout Filter me Level, row me *"12 weeks · 4 days a week · Intermediate"*, `Suggested` / *Fits her level*; kuch na chuna ho to current plan ka preview (`Open in library`). Header `Assign plan ▾` ke items par icons.
- **Logs** — `Workouts` · `Meals` · `Daily check-ins` · `Weekly check-ins` · `Habits` · `Supplements`, range picker (Last 7 / 30 / 90 days, ya koi plan; Progress ke saath shared), summary line, table (phone: blocks), 10 ek page. Row → drawer (Previous / Next), coach comment (Riya ko app me milta hai), check-in par review + Undo. `Compare plans` → A vs B.
- **Progress** — change cards (Weight, Waist, Body fat, sabse badhi lift), weight chart, Measurements (Show all), Progress photos (viewer: Front/Side/Back, Compare two dates), All photos drawer, Personal bests.
- **History** — 4 summary cards, Plans over time (Now / Completed / Replaced / Up next, Today line), Journey month-wise (chips, `Export` CSV, `Show earlier months`), About her journey, Health over time.
- **Content** — chips (All · Assigned to Riya · From her plans · Everyone), `Assign content` drawer, table, row → Preview, ⋯ (Preview · Change how long · Remind her to open it · Open in library · Remove / Hide + Undo).
- **Forms** — Onboarding answers (`Print`; web par card ke andar scroll, page ruka rehta hai; completed form me 3 start photos Front / Side / Back, tap = full screen, print me bhi), Weekly check-in (`Edit for Riya` = uski copy, ⋯ Duplicate and edit · Send now · Reset to master · Stop sending / Start sending again), `Send a form` drawer (Once ya Repeats, remind after 24 h).
- **Activity** — range (Today … All time), chips with counts, din-wise rows (old → new), `Show more`.
- **Notes** — note likho + `Mark as a flag`, flagged upar amber box me, ⋯ Edit / Delete (+ Undo) sirf likhne wala ya admin.

Jo kaam trainer ke access me nahi (gym template edit, trainer badalna) wo menu me nahi.

---

### 3.7 More (phone only) — `TrainerMoreMobile`

Title **More**, group **Library** — `Programs` · `Exercises` · `Nutrition & foods` · `Habits & supplements` · `Content library`, aur `Log out`. Settings, trainers, automations yahan nahi hain.

---

## 4. Client app

Client ke liye **mobile-first** app hai. Bottom bar ke 5 tabs: `Home` · `Train` · `Food` · `Progress` · `More`. Web pe wahi content do-column layout me (`ClientHomeWeb`).

Poore client app ka ek **tone rule** hai — client apna plan **badal nahi sakta**, sirf **log** karta hai. Jahan bhi kuch badalne ka mann kare wahan line aati hai: *"Want something changed? Tell Aman in your weekly check-in."*

Toast yahan `ca-toast` style ke hote hain — `ok` / `info` / `warn` / `err` / `del` / `star` — aur jahan kuch undo ho sakta hai wahan `Undo` button hota hai.

---

### 4.1 Home — `ClientHome` / `ClientHomeHero` / `ClientHomeWeb`

Phone (ClientHomeHero, D-29): blue hero — `Fri, 9 Oct · Week 6 of 12`, white bell (Notifications sheet), **Hey Riya**, *"Cardio and core today."* (ya *"Rest day today."*) + *"3 of 5 workouts done this week."*, runner picture; week strip hero ke neeche overlap. Web (ClientHomeWeb): top line + bell, no avatar.

| Card | Kya hai | Click pe |
|---|---|---|
| **Today's workout** | Plan ka din — `Upper A · Strength`, pehle 3-4 exercises (`Bench press 4 × 6–8 · 42.5 kg`, `Seated cable row 3 × 10 · 35 kg`, …) aur `+ N more` | `See all exercises` → Train tab. Exercise tick karne pe toast *"Bench press logged — 1 of 6 done"*; last exercise pe toast *"Workout done! — Aman can see it now"* |
| **Session with** | Trainer ke saath aaj ki session, `AV` avatar | Session detail |
| **Water** | Aaj ka paani, progress ring | `+250 ml · 1 glass` / `−250 ml`. Goal pura hone pe toast *"Water goal complete!"* (`star`). Zyada pe toast *"3.8 L today, that is plenty — Slow down: too much water at once is not good for you"* (`warn`) |
| **Next meal** | Plan ka agla meal — `Breakfast 8:00 am · Oats, whey protein, banana · 450 kcal` | `Ate it` → toast *"Breakfast logged — Oats, whey protein, banana · 450 kcal"* + `Undo`. `Log food` → Food log screen. `See all` → Food tab |
| **Habits** | cap *"From your plan today"*. `Walk 8,000 steps` (*"5,240 of 8,000 steps"*), water, sleep | `Add steps` → stepper + `Save steps`. Sleep → `Save sleep`, toast *"Sleep saved — 7 h 30 m · goal met"* (ya *"· aim for 7 h tonight"*). Done pe `Logged` / `Done` |
| **Supplements** | `Whey protein` (1 scoop · morning) · `Vitamin D3` (1 tablet · morning) · `Magnesium` (1 tablet · night, before bed) | `Take` → toast *"Whey protein taken"* + `Undo`, button `Taken` ho jata hai |
| **Coming up** | Aane wali check-in, session, plan week | — |
| **Notices** | Trainer ke replies, reminders | `Mark all as read` → toast *"All notifications read"* |

Macro target — `1,650 kcal · 120 g protein · 170 g carbs · 52 g fat`.

---

### 4.2 Train — `ClientTrain`

Week strip: `Mon Upper A ✓` · `Tue Lower A ✓` · `Wed Rest` · `Thu Upper B ✓` · `Fri Cardio ← today` · `Sat Lower B` · `Sun Rest`.
Din pe tap → Home ki tarah us din ka workout (blocks + card) dikhta hai: beeta din `Done · 55 min · 12 sets` ya `Not done`, aane wala din *"Planned for … You can start it on the day."*, aur `Back to today` (Gautam, 2026-10-15).

Workout chal raha ho to banner / bar pe `⋯`: `Pause timer` / `Resume timer`, `Finish workout`, `Restart workout`, `Discard workout` (laal, pehle "Discard workout?" poochta hai). Phone par koi bottom sheet khuli ho to toast screen ke upar aata hai (D-17).

Exercise row pe dumbbell ki jagah picture / video cover / YouTube thumbnail (agar ho), video pe ▶ nishan (cover na ho to icon ke kone me chhota ▶).

`Today · Fri, 9 Oct` heading. Agar aaj ka workout ho gaya to chip `Completed today`. `History` button → past workouts list; khali pe *"No past workouts yet."*

Exercise list blocks me banti hai — `Cardio` (35 min, easy pace) · `Conditioning` (3 sets, rest 60 s) · `Core` (6 sets, rest 45 s).

Exercise pe tap → **detail sheet**: sabse upar exercise ka media (D-27): upload kiya video yahin chalta hai (Tap to play, seek bar, full screen), picture tap par full screen zoom, YouTube link ho to YouTube video yahin chalta hai (YouTube ka full screen) aur neeche `Open in YouTube` (D-28); neeche title + *From content library* / *YouTube*. Details me `Video / picture` row (*Video · 0:42* / *Picture* / *YouTube link* / *Not added yet*). Phir `Today's target` (+ *"Last time: 40 kg × 6"*), `Details`, `How to`, `Form cues`, `Muscles` (body map — `Primary muscle` / `Also works`, `Front` aur `Back` view). `PR` badge jahan personal best ho.

`Start workout` → §4.3 logger.

---

### 4.3 Workout logger — `ClientWorkout`

Ye app ka sabse interactive screen hai.

**Top bar** — workout timer chalta rehta hai, `1 min` rest chip, ⋯ menu: `Past workouts` · `Restart workout` · `Remove logged work` (laal). `Finish` button.
Logger ka `Past workouts` sirf **isi exercise** ke pichhle workouts dikhata hai (date, sets), har row pe `Use these sets`. Poore workout / All wala view sirf Train ke `History` me. Sets box me `Use last time` → jo sets tick nahi hue unme last time ki values aa jaati hain (toast + Undo). Train aur logger se bahar jaane par workout timer ruk jaata hai; `Continue workout` pe wahin se chalta hai (D-17).

**Per exercise** — naam, `Target 4 × 6–8 · 42.5 kg`, `PR 45 kg × 6`, `How to do it` button. Unit toggle `kg` / `Bodyweight`.

**Set rows** — `Prev` column (pichhli baar kya kiya), weight + reps input, `Done` tick. Row ⋯: `Delete set` → toast *"Set deleted"* + `Undo`. `BW` chip bodyweight sets pe. `Add set` → toast *"Set added — Bench press · set 5"*.

Set ko **warm-up / working** mark kar sakte hain → toast *"Working set — Bench press · counts towards volume"* ya *"Warm-up set — … not counted in volume"*.

**Rest timer** — set done hone pe apne aap chalu, `Rest` label, `−15s` / `+15s` / `Skip rest`. Notification wala bada timer pe `+15s` / `Skip`.

**Navigation** — `Previous` · `Next exercise` · `Finish workout`.

**Finish flow** — `Finish workout` pe summary sheet:
1. `Where the time went` — time breakdown, note *"Aman sees the same times with your workout."*
2. `How hard was it?` — effort scale.
3. `Note for Aman` — free text.
4. `Save and send to Aman` → toast *"Workout saved — 18 of 22 sets"* (`star`), phir `Back to home`.

**Timer rules** (board me likhe hue):
- *"The timer stops when you finish the workout. Leaving this screen does not stop it."* — screen chhodne pe timer chalta rehta hai, `Keep going` button.
- *"If you don't answer, the workout is saved at your last set after 3 hours."*

**Discard / restart**:
- `Discard workout` → confirm (`Keep it` / `Discard workout`) → toast *"Workout discarded — Nothing was saved"* (`del`).
- `Restart workout` → confirm `Restart` → toast *"Workout restarted — Timer is running from 0:00"* + `Undo`.
- `Remove logged work` → toast *"All sets cleared — Timer keeps going"* + `Undo`.

Naya best lagne pe `New best` badge.

---

### 4.4 Food (meal plan) — `ClientFood`

Aaj ka meal plan. Target `1,650 kcal · 120 g protein · 170 g carbs · 52 g fat`, upar ring + bars.

Har meal card (`Breakfast 8:00 am`, `Snack 11:00 am`, `Lunch 1:30 pm`, …) pe:

| Button | Click pe |
|---|---|
| `Mark as eaten` | Toast meal logged, button `Logged · Undo` ho jata hai |
| `Undo` | Toast *"Breakfast un-logged — 450 kcal removed from today"* (`del`) |
| `Swap` | Us food ke alternatives (`Planned` tag original pe), ya `Search any other food` |
| `Edit portions` | Sheet — har food ka quantity stepper + unit select (`g` / `1 tbsp` / `1 cup`). Cap *"Calories and macros follow your portions. This changes today only."* Buttons `Cancel` + `Save portions` → toast *"Breakfast portions saved — Now 520 kcal · 38 g protein"* |
| `Ate something else` | Food log screen (§4.5) |
| Skip | Toast *"Lunch skipped — Try to get your protein in the next meal"* (`warn`) |
| `Eaten after all` | Skip undo |

Footer cap: *"Want something changed? Tell Aman in your weekly check-in."*

Pichhle dinon ka compare bhi dikhta hai (`1,610 / 1,702 / 1,580 / 1,655 kcal`).

---

### 4.5 Log food — `ClientFoodLog` / `ClientFoodLogWeb` (built, route `/food/log?meal=`)

Header: back (→ `/food`), chhota `Log food`, aur `Add to Snack ▾` — tap pe meal picker (phone sheet, web menu "ADD TO"): har meal `Breakfast · 8:00 am`, niche `Plan: Oats, Whey…` ya `260 kcal added now`, tick on the picked one. Default = URL ka `meal`, warna aaj ka pehla khula meal.

Search (44 high, *"Search food, e.g. paneer, dal, roti"*, clear ×), `Try` chips paneer / dal / roti / rajma, tabs `All` · `Recent` · `My foods`. Count line: *"41 foods in Aman's library and yours"* / *"N results for "q""* / *"Foods you logged lately"* / *"Foods you created"*. Pehle 8 rows, phir `Show all N foods` (API 25 ka page, `Show more foods`).

| Control | Click pe |
|---|---|
| Food row ka `+` | Turant us meal me log (outbox, offline bhi). Button green tick, toast *"Apple added to Lunch — 1 piece · 94 kcal"* + Undo. Dobara tap = remove |
| Food ka naam | Portion sheet — bada stepper (number tap karke type bhi), `= 150 g`, unit chips (grams + food ke units, grams same rehte hai), kcal/P/C/F cells, `Add to Lunch` |
| Added card ka × | Entry delete, toast *"Apple removed — Taken out of Lunch"* (`del`) + Undo |
| `Done · back to meal plan` | `/food` |

**`Can't find the exact food?`** — Calories (step 25), Protein / Carbs / Fat (step 1). Har box me − / + rehte hai, **aur number tap karo to text field khulta hai, type karke Enter ya bahar tap** (Gautam). Same steppers Create custom food aur Edit portions me.
- `Quick add` — kcal zaroori; khali pe toast *"Enter the calories first — Protein, carbs and fat are optional"* (`warn`). Toast *"Quick add · 150 kcal to Lunch"*.
- `Create custom food` — sheet: Name, Serving (`1 katori`), 4 steppers (ek serving ke), `Save food` → toast *"X saved to My foods — Tap + to log it"*, tab My foods.
- `Off-plan meal` tick + chips `Ate out` / `Party` / `Travelling` — jo add hoga woh `Off-plan` (amber tag) + reason, coach ko dikhta hai.

**`Other time`** (Add to ka last item, Gautam 2026-10-16) — sheet `Other time`, cap *"Ate outside your meal times? It goes straight to your food log at this time, marked off-plan."* Name (*"e.g. Evening chai"*, khali = "Other time"), Time −/+ 15 min aur chips `Now` / `30 min ago` / `1 h ago` / `2 h ago` (sirf aaj, abhi se aage nahi). `Use this time` → toast *"Adding to Evening chai · 4:30 pm — Tap + on a food to log it"*. Header ke neeche *"Other time · 4:30 pm · off-plan"* (tap = sheet dobara). Jo bhi add ho (library, Recent, My foods, Quick add) woh off-plan, Food log me us time par row *"Evening chai · other time · 1 cup · off-plan"*; meal card me nahi aata. Off-plan tick on rehta hai (tap pe toast *"Other time food is always off-plan"*). Details sheet ka `Log more to Evening chai` wapas usi time par khulta hai.

Web (720 px content aur 520 px height se upar, Gautam 2026-10-16): header, search, Try chips aur tabs fixed; sirf food list apne card ke andar scroll hoti hai (saari loaded rows + `Show more foods`), right column alag scroll. Tabs fit width. Usse chhota = poora page scroll.

### 4.6 Nutrition (log view) — `ClientNutrition`

Food tab ka doosra view — plan ke bajaye **aaj kya log hua**.

`Today's calories` ring, `Target 1,650 kcal`, `This week` bars. Water widget (`+250 ml · 1 glass` / `−250 ml`).

Logged entries list — plan ke meals (`Log` button) aur extra entries (`Green tea, no sugar · 1 cup`). Entry delete pe toast *"Entry deleted — Masala chai · 90 kcal"* + `Undo`. Meal un-log pe toast *"Breakfast marked as not eaten — 450 kcal removed from today"*.

Buttons: `Log food` · `Copy yesterday` → toast *"Copied 3 foods from yesterday — Masala chai, Roasted makhana, …"* + `Undo`.

`Open full meal plan · options and portions` → §4.4. Khali pe *"Nothing logged yet today."*

Info modal: *"Workout calories are not added back. Your plan already accounts for training."* → `Got it`.

---

### 4.7 Progress — `ClientProgress` / `ClientProgressWeb` (built 2026-10-16, D-21)

Data: `GET me/progress/` (one answer, cached for offline). Writes go through the outbox.

**Top** — `Progress` · *"Weight, body and strength"* (web *"Weight, measurements, strength and adherence"*). Clock icon (web `View past logs`) → `/progress/history`. `Log weight` → Log weight sheet.

**Goal weight** — Start · Now · Goal cells, bar, *"3.9 kg lost since 3 Sep"* · *"39% of the way"*, pill *"6.1 kg to go"* / *"Goal reached"*. ⓘ tip: *"Set with Aman when you joined. At your pace you reach it around Dec 2026."* (pace of the last 8 weeks).

**Tabs** `Weight` · `Body` · `Strength` + `Compare` chip (shows **First day vs now**: Weight, Waist, Hips, Body fat; `Compare photos side by side` → Compare page; fewer than 2 sets → toast *"Add a second photo set first"*).
- **Weight:** Current, change pill (*"−3.9 kg in 6 wks"*), chart with goal line, dots (tap = selected box: Vs previous · Since start · To goal, ✕ closes). Range `4 wk` · `12 wk` (default) · `6 mo` · `All` filters on the phone, no request.
- **Body:** the measurements this client tracks (the coach's set, default Waist · Hips · Chest · Bicep L · R · Body fat, plus any other already logged), each opens its dated bars (Waist open first); pairs show *"28.5 · 28.5 cm"*. `Log` in the card header → **Log measurements** sheet: *"Relaxed, tape snug but not tight. Change only what you measured."*, no date to pick: one entry per period (D-25), so the box says *"This period · logged Thu, 15 Oct — Changes update this entry · next one due Sun, 1 Nov"* or *"New entry · Today, Fri 16 Oct"*; a stepper per measurement (step 0.5) starting at the last value with *"Last 79.5 cm · 15 Oct"*; only changed ones are saved; under them *Your entries* lists the last four entries with dates. Save faded until a number changes (tap → *"Change a number first"*). Saved → toast *"Measurements saved"* · *"Waist · Fri, 16 Oct"* + Undo (D-22). Cap *"Next measurements are due with your week N check-in on Sun, 1 Nov."*
- **Strength:** lifts with spark line, best, change; tap → Lift sheet.

**Photos** — latest set's Front / Side / Back (tap → Photo set sheet; no set yet → Add photos), `All photos` → `/progress/photos`, `Add photos`, `Compare`.
**Stats** — Waist (→ Body tab), Workouts (→ Workouts sheet), Bench best (→ Strength tab).
**Adherence** — 6 weeks of bars (amber under 85%), tap a bar → its line *"Week of 28 Sep · 4 of 5 workouts · 93% of the plan followed"*.

**Sheets**
- *Log weight:* big − / + (0.1, typeable), `−1 kg` `−0.5 kg` `+0.5 kg` `+1 kg`; Date `Today` `Yesterday` + 2 days; note *"Replaces the 68.1 kg you logged on Thu, 15 Oct."* / *"… · −0.4 kg since 14 Oct (68.5 kg)."* / *"Your first weigh-in."* `Cancel` / `Save`. Toast *"Weight logged"* / *"Weight updated"* (Undo), or *"New milestone: 5 kg lost"* (star) when a whole kg is crossed.
- *Workouts:* *"12 workouts done"* · since · program; This week, Planned so far, Missed (last 3 dates), Average adherence. `View past logs` → History (Workouts, 3 months).
- *Lift:* Started at, Best set, Weight went up N times, Last logged, coach note. `See every logged set` → History (Workouts, 3 months).
- *Photo set:* *"Sun, 11 Oct · Side"*, pose tabs, big photo (tap = full size) or *"No side photo in this set"*. `Compare with start` → Compare (first set vs this one; the first set vs the latest).
- *Add photos:* Pose radio cards (Front / Side / Back, `Added today` tag), `Take photo` / `Choose from gallery`, *"Front photo ready · IMG.jpg"*. `Save photo` dim until a photo; without one toast *"Take or choose a photo first"*. Saved → *"Front photo added"* (Undo deletes it) or *"… replaced"* (no Undo, the old photo is gone).

**History** (`/progress/history?type=&range=`) — `‹ Progress`, *"All your logs in one place · 10 Oct – 16 Oct 2026"*. Range `This week` · `Month` · `3 months`; chips All · Workouts · Meals · Check-ins · Weight. Summary card (Workouts done, Avg calories, Avg protein, Weight change, adherence pill; web: right column, sticks while scrolling). Days newest first, score % (green ≥ 90, amber < 75), 7 days then `Show 10 more days · N left`, end *"That's everything for the last 3 months"*. Empty: *"No workouts in this range"* + `Try 3 months` / `Show all types`. Tap a day → Day sheet (each log with its details, coach reply in green) and `Open training` / `Open check-ins` / `Open meal plan`.

**Progress photos** (`/progress/photos`) — sets by month (newest first, each month wraps into rows, no sideways scroll), pose tabs with *"2 of 2 selected · 3 Sep vs 15 Oct · −3.9 kg"* and `Compare` on their right (Gautam: at the top, not a bottom bar; fewer → toast *"Pick two sets first"*), private note, tap two sets (A / B, first and last picked at the start), due card *"Next set due Sun, 1 Nov"* (last photo set + 2 weeks, that week's Sunday) / *"Today's set · 1 of 3 poses added"* + `Add`. Web tabs are as wide as their labels.

**Compare** (`/progress/compare?a=&b=&pose=`) — `‹ Timeline`, pose tabs, A / B photos with ‹ › to step sets (A stays before B), Measurements table from the nearest measurement, *"In 42 days: weight −3.9 kg, waist −4.5 cm, hips −3 cm."* Web: photos 540 left, table right.

---

### 4.8 Habits & supplements — `ClientHabits`

Tabs `Day` / `Week`. Day: Mon–Sun strip (board jaisa), din pe tap → us din ke habits aur supplements; beeta din (7 din tak) log ho sakta hai, aane wale din pe toast *"You can log this on …"*. Week: `Habits done` %, `Supplements taken` %, sabse lambi streak, phir habits aur supplements ka grid (cell pe tap → wo din). Water ka −/+ 250 ml wahi water log hai jo Home ke water card me hai. Jo habit baad me shuru hogi uska `Remind me on Monday evening` habit reminders on karta hai (More → Reminders) (D-18).

**Habits** — `Walk 8,000 steps` (green, best streak 19), water (`250 ml` quick button), sleep. Har habit pe `Details` → sheet: `Last 7 days`, `Target set by Aman`, cap *"Want a different target? Tell Aman in your weekly check-in"* (link). Steps → `Save steps`; sleep → `Save sleep` + goal toast.

**Supplements** — cap *"Plan 'Fat loss basics' by Aman · since 1 Sep. Tap a supplement for dose and stock."*
- `Whey protein` — 1 scoop (30 g) in water · *"In water, with breakfast"* · stock 12 scoops.
- Pills `Upcoming` / `Missed` / `Starts Mon, 12 Oct`.
- `Take` → toast *"Whey protein taken — 11 scoops left at home"* + `Undo`; purane din ke liye *"Logged for Wed, 7 Oct"*. Button `Took it`.
- Un-tick → toast *"Whey protein un-ticked — Not taken today"* (`del`).

---

### 4.9 Check-ins — `ClientCheckin`

Route `/checkins` (More → Check-ins). `/checkins/daily` daily form (`?edit=1` Edit answers), `/checkins/weekly` weekly form, `/checkins/<id>` list + that check-in's sheet (reply notification). Data: `GET me/checkins/?tab=weekly|daily&before=` (D-19).

**Header** — *"Aman reads every one · <program>, week N of M"*. Cells: `N days` Daily streak · `5 of 6` Weekly on time · `−0.6 kg` Last weekly change.

**Daily card** — not sent: *"Today, Thu 15 Oct · 30 seconds"*, pill `Due today`, cap *"Weight, sleep, energy, mood, hunger and soreness. Takes about 30 seconds."*, `Start daily check-in`. Sent: *"Today · sent at 8:05 am"*, pill `Sent`, green line *"Sent at 8:05 am · 7.5 h sleep, energy Good"*, `View` (sent page) · `Edit answers`.

**Daily form** — Morning weight stepper (±0.1, *"−0.1 kg since Wed"*), Sleep last night (`5 h` … `9 h`, half hours too), Energy / Mood (`Very low` → `Great`), Hunger (`Very low` → `Very high`), Soreness (`Very sore` → `None`); label *Pick one* until picked. *Anything else?* note (optional) + chips `Felt strong today` · `Knee a bit sore` · `Slept late` · `Busy day at work`. Blue note *"Steps (8,240) and water (2.3 L) come from your habits…"*. `Send to Aman` faded until all answered; tap → warn toast *"Answer sleep, energy … first — Only the note is optional"*. Sent → toast *"Daily check-in sent — Aman will see it today · 3-day streak"* + Undo (deletes it); page shows *Sent to Aman* card with answers, `Edit answers` · `Back to check-ins`. Edit → *"Daily check-in updated"*. Offline: saved in the outbox, card says it goes when online.

**Weekly card** — *"Weekly check-in · week 7"*, *"Due Sun, 18 Oct, 6:00 pm · you can fill it in early"*, pill `Due Sun` (`Due today` on Sunday, `Late` after 6 pm). Question chips (Weight · Your week · Meal plan · 3 photos · Notes). Draft: bar + *"Draft · 2 of 5 answered"*, button `Continue check-in` (blue) instead of `Start weekly check-in` (black). Sent: *"Sent today, 5:40 pm · waiting for Aman"*, green line *"Week 7 sent · 68.2 kg · 2 photos"*, `View what you sent` (sheet).

**Weekly form** — *"Question N of 5"* + bar. Body weight stepper (*"Same as last week"* / *"−0.4 kg since last week"* green / amber up), Quick `This morning, 68.4` · `Last week, 68.9`. Scale (1–5 big), single choice (radio rows), photos (Front / Side / Back slots: tap → Take a photo / Choose from gallery on the phone, gallery on web; tap again → removed + Undo; *No photos this week* checkbox; cap *"Same spot, same light, in the morning. Only Aman sees your photos."*), text (box + *Tap to add* chips). `Back` (faded on Q1) · `Next` / `Skip` (optional, empty) / `Review` (last). Required empty → *"Pick an answer to continue — This question is required"*. Review: *"Check your answers"*, each answer with `Edit`, *Not answered · required* in red, *Skipped* grey; `Send to Aman`. Sent → toast *"Week 7 check-in sent — Aman usually replies within a day"* (`star`) + Undo; card *"Week 7 check-in sent"* with every question (long question above its answer), Weight + Change, photo thumbnails (tap → full size), `Back to check-ins`. Back arrow = save and exit → *"Draft saved — 2 of 5 answered · finish by Sun, 18 Oct, 6:00 pm"*.

**Photo weeks** (D-23, D-24) — the weekly form asks for photos only every N weeks (coach's `photo_every_weeks`, default 2); other weeks have no photo question. Photo weeks also have a **Body measurements** step before the photos: the coach's measurements with steppers starting at the last value (*"Last 79.5 cm · 15 Oct"*), all optional, *"Skip this step if you did not measure this week."*; changed ones show *"Will be saved"* and go to Progress on send.

**Both forms** — the top bar and progress stay fixed; only the questions scroll. Photo question: the coach names the photos it asks for in the question's options (e.g. `Meal`, `Label`; 1–6); none named = `Front` / `Side` / `Back`. Review shows small thumbnails under the photo answer. Returning to the list or Home shows the new state at once (they reload when the outbox syncs; a queued check-in and the weekly draft are shared by every check-ins page).

**Past check-ins** — card has a fixed height (phone 60% of the screen, 320–520 px; web 560 px) and the rows scroll inside it; tabs `Weekly` · `Daily`. Weekly rows *"Week 6 — Sun, 11 Oct · 68.9 kg · 2 photos"* with pill `Sent` (blue clock, waiting) / `Replied` (reply shown under: *Aman: …*) / `Reviewed` / `Missed` (*"Sun, 27 Sep · not sent"*). Daily rows *"Wed, 14 Oct — 7.5 h sleep · energy Good · “Felt strong today”"* `Sent` / `Replied` / `Missed` (*"Not sent · reminder went at 9:00 pm"*). More rows load at the end of the list. Header line under the title counts the whole list: *"20 check-ins · 8 sent · 12 missed"*; while rows are below, the scrollbar shows, the bottom fades and *"Scroll for older · 20 of 45 shown"* sits under the list (Gautam 2026-10-16). Empty: *"No check-ins here yet."*

**Past check-in sheet** — weekly: *"Week 5 check-in — Sent Sun, 4 Oct, 5:40 pm"*, cells Weight · Change (or *In 2 weeks*) · Workouts `4 / 4` · Meals on plan `86%`; coach reply (avatar, name, date) or *"Waiting for Aman's reply…"* / *"Aman reviewed this check-in and did not add a note."*; answers; PHOTOS: one big photo (whole photo shown) with a tab per photo name, *Tap to open* → full-size viewer (swipe, arrows, pinch zoom, Esc / ×). Missed: *"This check-in was not sent. A missed week cannot be filled in later, but the next one opens every Sunday at 6:00 pm."* Daily: cells Sleep · Energy · Mood · Steps, reply, Hunger · Soreness · Water · Morning weight · Note; missed *"Not sent. A reminder went at 9:00 pm. Daily check-ins cannot be sent for past days."* `Newer` / `Older` (ends: *"This is the newest one"* / *"No older check-ins here"*).

---

### 4.9a Form from your coach — `ClientForm` / `ClientFormWeb` (built 2026-10-22, D-49)

Coach (ya automation) koi form bheje (Monthly feedback, Liability waiver, PAR-Q, trainer ka apna form) to client yahan bharta hai.

| Element | Kya karta hai |
|---|---|
| Check-ins par form card | Naam, "From Aman · sent … · due …", `To fill` pill, "N questions. Takes about …", 5 tak question chips, `Fill in form` → `/checkins/forms/<id>`. Draft ho to bar "Draft · 1 of 3 answered" aur `Continue form` (blue). Web par right column me Past check-ins ke upar, phone par Weekly card ke neeche. |
| Sent card | 14 din tak green `Sent` card: "From Aman · you sent it today, 6:07 pm". Tap → form ka sent view. |
| Form page | Upar back (Save and exit), naam, "From Aman · due …", "Question 1 of 7" + bar. Ek page par ek sawal; Optional tag; yes/no aur single = radio rows, multiple = checkboxes ("None…" baaki hata deta hai), number = number keyboard, scale 1–5, short / long text, photo slots. Required sawal bina jawab `Next` dim aur toast "Pick an answer to continue". Optional par button `Skip`. |
| Review | "Check your answers", har jawab ke saath `Edit`. `Send to Aman` (offline me outbox). Missing required → toast "Answer “…” first". |
| Sent | Green tick card "Sent to Aman", time, har sawal + jawab, `Back to check-ins`. Toast "<form> sent" + `Undo` (24 h me, coach ne dekha na ho) → form wapas "To fill". |
| Back beech me | Draft phone par save, toast "Draft saved · 1 of 3 answered · finish by …". |
| Notification | "Form sent" / reminder → seedha ye form khulta hai. |

### 4.10 Library — `ClientLibrary` / `ClientLibraryWeb` (built 2026-10-16, D-26)

Everything the client can read or watch: what the coach shared (with an optional note), what came with the program or meal plan, and what Vimal shared with all clients. Route `/library`; `/library/<id>` opens that item (the *"New in your library: …"* notification links there).

- **Header:** back, *Library*, *"Videos, PDFs and guides from Aman"*. Progress card *"3 of 8 done"* with a bar and *"2 new from Aman"* / *"All caught up"*.
- **Search** *"Search videos, PDFs and articles"* (title, description, text and the coach note) with Try chips `squat` · `eating out` · `protein` · `check-in`. Filters `All` · `Videos` · `PDFs` · `Images` · `Articles` · `Links` · `Saved` (web shows counts; phone row scrolls sideways). `Links` is not on the board (Gautam, D-27). Line *"Everything Aman shared with you · 8"* or the filter / search name. Unread items first, then newest.
- **Row / card:** tone box with the kind icon (videos show length), title (blue dot when new), *"PDF · 6 pages · by Vimal Singh"*, where it came from (*"Assigned by Aman · 1 Oct"*, *"From Fat loss · 8 weeks"*, *"From your meal plan"*, *"For all clients · 30 Mar"*), *"Note from Aman"*, `New` or `✓ Done` pill, bookmark (toast *"Saved for later"* / *"Removed from saved"* + Undo).
- **Web:** grid of cards (3 / 2 / 1 across by width), right column with the progress card and **Notes from Aman** (every note, newest first).
- **Empty:** no match → *"Nothing found"* / *"Try another word or another type."* with `Show everything`; Saved empty → *"Nothing saved yet"* / *"Open an item and tap Save for later. It will show up here."* The search box has an × to clear it.
- **Item sheet** (opening marks it read): title, *"Video · 3:05 · Assigned by Aman · 28 Sep"*.
  - Video: player in the item's tone (210 high, 300 on web; black once the video loads), seek bar (tap / drag), full screen button; a YouTube video plays right here in the YouTube player (its own full-screen button) with `Open in YouTube` under it (D-28), label *Tap to play* / *Playing · <chapter>* / *Paused · …* / *Finished · tap to watch again*, progress bar with times, **CHAPTERS** (tap = jump there and play). Watching to the end marks it done (toast *"Video finished · marked as done"* + Undo). No file → YouTube link or *"Video not uploaded yet"*.
  - PDF: the real page (drawn on the server as a picture), tap = full screen with zoom and swipe (*"1 / 6"*); `‹ Page 1 of 6 ›`, `Download` (opens the file). If the file can't be read, the coach's page outline shows instead.
  - Link: card with the site (*healthline.com*), the address and `Open link` (opens the browser).
  - Image: the picture on a green box, 240 high (300 on web), whole picture visible (tap = full screen zoom), *"PNG image · 1 page"*, `Save image`.
  - Article: the text under a line.
  - Coach note box *"From Aman"* with avatar, then the description.
  - Footer `Save for later` / `Saved` and `Mark as done` / `Done · undo`. Toasts *"Marked as done · <title> · 4 of 8 done"*, *"All caught up!"* when the last one is done, *"Marked as not done"*, each with Undo. Save / done go through the offline outbox.

### 4.11 More — `ClientMore` / `ClientMoreWeb` (built 2026-10-16, D-23)

Routes `/more`, `/more/profile`, `/more/notifications`, `/more/activity`. Data `GET me/account/` (cached offline). Web title *My account* (no bell; the Notifications tab is there), tabs `Overview` · `Notifications · N` · `My activity`. On Notifications and My activity the header, tabs and filters stay put and only the list scrolls (phone and web, Gautam).

**Overview** — profile card (avatar, naam, *"Coach Aman · Profile & activity"* → Profile). Coach card (*"Your trainer since …"*, Next session, Daily check-in *"Every day · reminder at 9:00 pm"* / *"sent today"*, Weekly check-in *"Every Sunday, 6:00 pm · next Sun, 18 Oct"*, `Details` → sheet with next session, training days, daily / weekly check-in, reply time, program, meal plan, plan end, and `Add to calendar` (puts the next session in Google Calendar)). Plan dates = the program's start date to start + weeks − 1 day (or the end date the coach set). Web My account has no Your plan card (the sidebar has those pages, Gautam). YOUR PLAN: Habits & supplements (*"Steps, water, sleep · whey, D3, magnesium"*), Check-ins (`Due Sun`), Nutrition overview (→ `/food`), Library (→ `/library`). ACCOUNT: Notifications, Notification settings, Units & preferences, Privacy & data, My activity, Help & about. `Log out` (confirm). Footer *"Train With Vimal · Version 1.0.0"*. Deletion pending → red banner with `Cancel deletion`.

**Profile** — Email, Mobile, City, Date of birth, Height, Coach, Program, Plan dates; Goal card (bar, Start / Now / Goal, lost since start, weeks done, check-ins sent). `Edit` → sheet: name, email (new email waits for its link: `Resend link` · `Cancel change`), mobile (+91, must be free), city, height (cm, 100–250), DOB; saved → toast + Undo.

**Sheets** — *Notification settings*: Workout, Meal, Water, Supplement, Habit, Check-in, Coach updates, Progress and personal bests (each toggle saves at once + Undo), Quiet hours (from / to ±30 min), `Reset to recommended` · `Done`. *Units & preferences*: weight kg / lb, length cm / in, water L / oz, week starts Mon / Sun, theme, preview, Save + Undo. *Privacy & data*: who sees what, Share progress photos with Aman (off = new photos stay with you), Help improve the app, `Download my data` (ZIP link by email), `Delete account` → sheet (type DELETE, 14 days to change your mind). *Help & about*: FAQ, Report a problem (Broken · Wrong numbers · Idea, text, attach a screenshot of the page), Gym front desk (call), Terms / Privacy (read only), version.

**Notifications** — tabs `All` / `Unread · N`, `Mark all read` (+ Undo), gear → Notification settings. Row → sheet: `Mark as unread`, `Delete` (+ Undo), link button. More rows load on scroll.

**My activity** — *"Only you can see this · last 7 days"*, chips All · Training · Food · Check-ins · Habits · Account, grouped by day (*"Today · Fri, 16 Oct"* + count). Row → sheet with its rows and a link. A past-day or changed weight / measurement adds a line under today: *"You changed measurements for Tue, 13 Oct"* with *"Chest 92 → 91.5 cm"*; a late log shows *"Logged on Fri, 16 Oct"* (Gautam 2026-10-16).

---

### 4.12 About — `ClientAbout`

Route `/more/about` (Help & about → *About Train With Vimal*). Header `About` + *"Train With Vimal · Version 1.0.0 (1)"*, back → More.

| Control | Click pe |
|---|---|
| `Version 1.0.0 (1)` chip | Copy; toast *"Version copied"* · *"Train With Vimal 1.0.0 (1) · paste it when you report a problem"* |
| Coach card | Vimal · *Head coach · Online*, intro, stats `10+ Years coaching` · `300+ Transformations` · `17,000+ Followers` (gym settings se) |
| `WhatsApp` | wa.me khulta hai, toast *"Opening WhatsApp"* · *"Chat with +91 …"* |
| `Call` | Phone dialer, toast *"Calling +91 …"* · support hours |
| `Email` | Mail draft, toast *"Email draft opened"* · *"To …"* |
| `Website` | Browser, toast *"Opening trainwithvimal.com"* · *"In your browser"* |
| `Support hours` | Sirf info (no chevron) |
| `What's new` (`New` pill) | Sheet *"What's new"* · *"Version 1.0.0 (1) · 12 Oct 2026"*, 4 points, `Got it` |
| `Rate the app` | Play Store page, toast *"Opening the store"* |
| `Terms of use` / `Privacy policy` | Sheet with 4 points, *"Last updated · 1 Sep 2026"*, `Close` |
| `Open-source licences` | Sheet *"Thank you to these projects"*, name left + licence right, `Close` |

Number missing ho to toast *"No … yet"* · *"Ask at the front desk"*. Footer `© 2026 Train With Vimal · Made in India`. Web: do columns (app + coach left, Contact + App right).

---

### 4.13 Food — meal plan + nutrition ek saath (naya, trial) — `ClientMealNutrition` / `ClientMealNutritionWeb`

Probid ka try (2026-10-14): §4.4 (meal plan) aur §4.6 (nutrition log) do alag page the, ab ek hi page. Base nutrition page ka hai, upar week strip aa gayi.

**Page pe kya hai (upar se niche):** header `Food` + line `Fri, 9 Oct · today · 1,059 of 1,650 kcal` + `Log food` · week strip (Mon 5 – Sun 11, aaj ka cell `Today`) · calories ring card · `This week` bars · Water · tabs `My plan` / `Food log · N`.

| Control | Click pe |
|---|---|
| Week strip ka din | Sirf **meals aur food log** us din ke ho jate hai. Ring heading `Today's calories` / `Mon's calories` / `Sun's plan`, aur number `kcal left` / `kcal eaten` / `kcal planned` |
| `This week` bar | Us din ka kcal + protein niche dikhta hai. **Week strip se ye nahi badalta** (apna selection rakhta hai) |
| Water `+250 ml` / `−250 ml` | Poore din ki habit hai, isliye ye bhi week strip se nahi badalta |
| Calories card | Sheet — `Eaten` / `Left` / `Still ahead` / P / C / F, cap *"Workout calories are not added back…"* → `Got it` |
| Tab `Food log · N` | Us din ka log (§ niche) |

**`My plan` tab** — bilkul §4.4 jaise meal cards (foods andar, pill `Logged` / `Next` / `To log` / `Planned` / `Missed` / `Skipped`):

| Control | Click pe |
|---|---|
| Food row ka `Swap` | Swap sheet — `Approved by Aman · portions matched to your plan`, radio options (`Planned` tag original pe, `84% match`), `Search any other food`, footer *"Applies to today's plan only"* + `Swap` |
| `Edit portions` | Bottom sheet — har food ka stepper, total line + `+14 kcal` / `Same as now`, `Cancel` / `Save portions` → toast *"Dinner portions saved"* |
| `Mark as eaten` | Toast *"Dinner logged — 436 kcal · 176 kcal left"*, card `Logged · Undo` ho jata hai |
| `Logged · Undo` | Toast *"Dinner un-logged"* (`del`) |
| ⋯ (3-line) button | Sheet, §4.4 ke wahi chaar item: `Swap a food` · `Edit portions` · `Log something different` · `Skip meal` |
| `Skip meal` | Card `Skipped · not counted today`, toast (`warn`), button `Eaten after all` |
| `Ate something else` (sabse niche) | Log food screen (§4.5) |

**`Food log` tab** — us din ki har entry time ke hisaab se (`8:10 am Breakfast · Oats, Whey protein, Banana · 450 kcal`). Row pe chevron hai, tap pe **details sheet**:
- Plan ka meal: `Logged 8:10 am · planned for 8:00 am · from your plan`, andar ke saare foods (amount + kcal, swap hua to *"swapped from …"*), phir `Calories` / `Protein` / `Carbs` / `Fat` / `Share of today 27% of 1,650 kcal`, aur `Edit portions` + `Mark as not eaten` (sirf aaj).
- Plan ke bahar ki entry: `Logged 8:20 am · Breakfast · outside the plan`, wahi macro rows, aur `Log more to Breakfast` + `Delete entry` → toast + `Undo`.
- Buttons `Log food` + `Copy yesterday`. Purane din pe cap *"You can only add food to today. Tap Today in the strip above to log."*

Swaps aur portions sirf **aaj** ke liye lagte hai (purane/aage ke din pe plan ka original dikhta hai).

Web (1440) pe same cheezein: left column me ring + week + water, right column me tabs aur meal cards, sheets beech me centred modal (520 px).

Faisla ho gaya (Gautam, 2026-10-15): yahi combined page rahega.


**Built (2026-10-15, route `/food`, D-20).** Gautam ke changes:
- `Mark as eaten` ab dropdown hai (Edit portions ke right): `Upload photo and mark as eaten` (camera / gallery, photo optional) ya `Mark as eaten without a photo`. Photo meal card par chhota thumbnail, Food log row par thumbnail, details sheet me badi; tap pe full-size viewer.
- Web (700 px se upar): header, week strip aur tabs fixed; sirf meal cards (aur left column) scroll hote hai. Usse chhota = ek column, poora page scroll.
- Food log me har plan meal ek row, aur har extra food (search / quick add / off-plan) alag row.
- **Round 2 (2026-10-16):** `Upload photo and mark as eaten` sirf photo leta hai, meal mark nahi karta. Photo header me pill ke paas, card me *"Photo ready — Breakfast is not logged yet"* bar with `Change` (camera) aur ×. Tab button plain `Mark as eaten` ho jata hai jo photo ke saath log karta hai. Toast *"Photo added — Tap Mark as eaten to log Breakfast"*. `Mark as eaten without a photo` turant log karta hai. Logged meal ke ☰ me `Add a photo` / `Change photo` / `Remove photo`.
- Log food se kisi meal me add hua food us meal card me *"ALSO LOGGED · OUTSIDE THE PLAN · +94 kcal"* ke neeche row (naam, Off-plan tag, amount · time · reason, kcal, chevron → details sheet).
- `Copy yesterday` toast *"Copied N foods from yesterday"* + `Undo` (sirf woh copied rows hat-ti hai). Aaj jo meal pehle se logged hai woh copy nahi hota.
- Logged time = jab tap kiya (8:00 ka breakfast 8:40 par mark kiya to row *"Logged 8:40 am · planned for 8:00 am"*).
- Tabs (My plan / Food log) phone par full width, tablet / web par chhote aur fit width.
- Purane `ClientFood` aur `ClientNutrition` boards ki jagah yahi page hai; nav ka Food / Nutrition `/food` kholta hai.
---

## 5. Login, join link aur onboarding

### 5.1 Log in — `ClientLogin`

Fields `Email` + `Password`, links `Forgot password?` · `Need help?` · `Help`. Button `Log in`.

Neeche: *"New here? Open the invite link your coach sent you."* aur `Need help logging in?` → sheet, cap *"Most login problems are a pending approval or a missing invite. The gym team can check both."*

**Approval pending state** — *"Aman is still reviewing your account"*, `Check status`, `Log out`.

**Forgot password** — `Email or mobile number` → `Send reset link` → `Send again` / `Back to log in`.

Terms sheet → `I agree`.

---

### 5.2 Welcome / profile setup — `ClientWelcome`, `ClientHealth`

Login ke baad 5-step setup (`Finish later` har step pe):

| Step | Kya poochha jata hai |
|---|---|
| 1. Your goal | Main goal and training experience |
| 2. About you | Age, height, weight, where you train |
| 3. Training days | Days, session length, wake-up time |
| 4. Health & injuries | Injuries, conditions, activity, doctor's OK |
| 5. Food preferences | Diet, meals per day, foods you avoid |

Injuries options: `None` · `Knee` · `Lower back` · `Shoulder` · `Neck` · `Wrist` · `Ankle`.
Conditions: `None` · `Diabetes` · `Thyroid` · `High BP` · `PCOS` · `Asthma` · `Heart condition`.

`Tell Aman more` free-text box, cap *"Only you and your coach can see this."*

Beech me chhodne pe **confirm**: *"Aman can't build your plan until setup is done. We will remind you tomorrow, 9 am."* → `Keep going` / `Save & leave`.

Review step: cap *"Tap a row to change it"*, `Change` links, phir `Go to Home`.

---

### 5.3 Intro slides — `ClientIntro`

Pehli baar app kholne pe slides — jaise *"WHY IT MATTERS — Good health is your real wealth"* (*"More energy for work and family, better sleep and a calmer mind."*). Buttons `Skip` · `Next` · last pe `Get started`.

---

### 5.4 Join from a link — `ClientJoinLink`

Do tarah ke link:

**Invite link** (`trainwithvimal.app/join/<code>`) — `You're invited`, trainer `AV` card, pill `Link works`. Form: `Full name` · `Email` · `Phone number` · `Password` + `Terms of use` / `Privacy policy`. App store buttons `Google Play` · `App Store`. Sign-up ke baad Approvals me jata hai (agar wo setting on hai).

**Coach login link** — `Your coach added you`, sub *"Aman Verma made your Train With Vimal account. Pick a password and you are in. No approval needed."* Details dikhte hain + link `These are not my details`. Fields `New password` + `Confirm password` → `Create my account`.

Cap *"Your mobile number is how you log in, so only Aman can change it."* Link `Set up my profile on the web instead`.

**Broken link states** — expired, already used, galat code — har ek pe apna message aur `Log in` / `Invite link` / `Login link` ke rastey.

---

### 5.5 Verify email — `ClientVerifyEmail`

`Resend email` · `Change email` (drawer: `New email`, cap *"The old link stops working."*, `Save and send link`) · `Log out`. Demo ke liye `Open the link` aur `Open an old link` (expired state). Verify hone pe `Confirm my email` → `Continue`.

---

### 5.6 Reset password — `ClientResetPassword`

`Email` → `Send reset link` → `Resend email` / `Use a different email` / `Back to log in`. Link kholne pe `New password` + `Confirm new password` → `Save new password` → `Back to log in`. Expired link pe `Send a new link`.

---

### 5.7 Permissions — `ClientPermissions`

Teen permission, har ek apne waqt pe maangi jati hai. Pehle app ka apna sheet, phir OS ka dialog (`trainwithvimal.com wants to …` / `Allow`).

| Permission | Kab | Sheet | Perks |
|---|---|---|---|
| **Notifications** | *After you verify your email* | `Stay on track` — *"Get a nudge at the right time, and know the moment your coach replies."* `Allow notifications` | Account approved and check-in due alerts · Workout and meal reminders, at your times · Replies and plan updates from your coach |
| **Camera** | *When you first take a progress photo* | `Use your camera` — *"Take progress and meal photos right inside the app."* `Allow camera` | Front, side and back progress photos · Snap a meal for your coach to check · Photos stay private to you and your coach |
| **Photos** | *When you first pick a photo* | `Pick from your photos` — *"Choose photos you already took, like last month's progress shot."* `Allow photos` | Add older progress photos to compare · Only the photos you pick are uploaded · See your change side by side |

Buttons `Not now` / `Open settings` (jab pehle deny kiya ho). OS dialog ke options: `Show notifications` / `Use your camera` / `See your photos` vs `Don't allow`. Link `Help`.

---

## 6. Common patterns

Ye cheezein har screen pe same tarah chalti hain — Flutter me inko **ek baar** banana hai aur reuse karna hai.

### 6.1 Data table
Header row (sticky), `num` columns right-aligned, row hover `#FAFAFA`, row click = detail kholna, aakhiri column `Actions` me 3-dot. Table ke neeche footnote jo batata hai *"Showing 8 of 24"* + metric ka matlab.

### 6.2 Filter
`Filter` button pe count chip (`Filter · 2`). Dropdown me groups, har group ka pehla option `Any`. Neeche `Clear filters`. Chuni hui values **chips** ban jati hain table ke upar, har chip pe `×`, aur `Clear` sab hata deta hai. Kuch match na ho to empty state + `Clear filters`.

### 6.3 Dropdown / 3-dot menu
Rows `mi`, laal wala `mi danger` sabse neeche. Click outside se band. Ek waqt me ek hi menu khula rehta hai (`mo` state).

### 6.4 Modal vs drawer
- **Modal** — chhota faisla ya confirm. Do buttons: safe wala `out`, action wala `pri` ya `danger`. Destructive confirm me hamesha likha hota hai kya bachega (*"Workouts they already logged stay safe."*).
- **Drawer** (right side) — form bharna. Niche fixed footer me `Cancel` + primary. Footer ke upar `dr-fnote` line jo bataati hai kya zaroori nahi hai ya kahan se badalna hai.

### 6.5 Toast
Niche se slide, ~4 s, ek waqt me ek. Title **past tense** (*"Program duplicated"*), neeche grey detail line. Jo undo ho sakta hai uspe `Undo` (`×` se pehle). Toast kabhi kisi cheez ka **akela record** nahi hota. Jis error pe faisla chahiye wo modal hai, toast nahi.

**Box dono jagah same** — admin/trainer (`.pg-toast`, dark `#1F1F1F`) aur client app (`.ca-toast`, colour per kind) ka **width 360**, **height ~49**, **radius 14**. Sirf fill alag hota hai.

**Jagah khud dhoondta hai** — bottom pe hi rehta hai, par kitna upar wo screen dekh ke tay hota hai:

| Screen pe kya hai | Toast ka bottom |
|---|---|
| Koi bottom bar nahi (web pages, login/onboarding phone boards) | **20** |
| Bottom bar hai — client ke 5 tabs ya admin/trainer phone nav (dono 71 high) | **83**, yaani bar se 12 upar |
| Bottom sheet khula hai | wapas **20** — bar scrim ke peeche hai, to toast screen ke bottom pe aakar sheet ke **upar** float karta hai |

Sheet khuli ho aur toast dikhe, to **sheet apna bottom padding 78 kar leti hai**, taaki toast kabhi uske buttons na dhake. Flutter me bhi yahi chahiye: bottom bar ki height + 12, aur sheet ke upar.

### 6.6 Empty states
Title + ek line explanation + (agar ho) action. Filter ki wajah se khali hai to action `Clear filters` hota hai, warna `New …`.

### 6.7 Badges
`b-ok` (green · Active, Verified) · `b-warn` (amber · Pending, Expires soon, Full) · `b-bad` (red · At risk, Missed) · `b-neu` (grey · Paused, Not checked) · `plain` variants.

---
