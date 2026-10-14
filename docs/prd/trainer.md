# Trainer area

Sidebar: Dashboard · My clients · Check-ins (count) · Calendar — *Library:* Programs · Exercises · Nutrition & foods ·
Habits & supplements · Content library — *You:* My profile. Phone: bottom nav + More (`TrainerMoreMobile`).
Behaviour: `../screens/behaviour.md` §3. Library screens are the same as Admin's, limited by the trainer's permissions.

| Screen | Board | What it does | API |
|---|---|---|---|
| Dashboard | `TrainerDashboard(Mobile)` | Today (sessions, check-ins to review), needs attention (at-risk, missed workouts, flags), client activity feed (realtime) | `dashboard/trainer/` |
| My clients | `TrainerClients(Mobile)` | Own clients with adherence, last activity, at-risk | `clients/` |
| Client profile | `TrainerClientProfile(Mobile)` | Same as admin's, without admin-only actions | `clients/<id>/…` |
| Check-ins | `TrainerCheckins(Mobile)` | Review queue, previous week side by side, reply, mark reviewed / undo | `checkins/` |
| Calendar | `TrainerCalendar(Mobile)` | Own sessions, availability | `sessions/`, `availability/` |
| Me / My profile | `TrainerMe(Mobile)` | Own profile, public card visibility, documents, access requests | `trainers/me/…` |
