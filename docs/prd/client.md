# Client app

Tabs: **Home · Train · Food · Progress · More**. Phone boards (390) and web boards (`…Web`). Behaviour: `../screens/behaviour.md` §4.
All logging works **offline** and syncs later (decision D-07).

| Screen | Board | What it does | API |
|---|---|---|---|
| Home | `ClientHome`, `ClientHomeHero`, `ClientHomeWeb` | Today: workout, meals, water, habits, check-in due, coach message, onboarding left | `me/home/` |
| Train | `ClientTrain(Web)` | Week strip, today's workout, program progress, history | `me/train/` |
| Workout logger | `ClientWorkout(Web)` | Sets (weight/reps/time), last time, rest timer, PRs, finish with effort + note, auto-save after 3 h | `me/workouts/…` |
| Food | `ClientMealNutrition(Web)` | Meals from plan: eat / skip / swap / portions / option, totals vs targets, water | `me/food/…` |
| Log food | `ClientFoodLog(Web)` | Search foods, recent, quick add, copy yesterday | `me/food-log/`, `me/foods/` |
| Progress | `ClientProgress(Web)` | Weight chart, measurements, photos, PRs, streak | `me/progress/`, `me/weights/`, `me/photos/` |
| Habits & supplements | `ClientHabits(Web)` | Daily ticks/counters, supplements taken | `me/habits/…` |
| Check-ins | `ClientCheckin(Web)` | Due forms, fill + photos, past answers, coach reply | `me/checkins/…` |
| Library | `ClientLibrary(Web)` | Shared videos/articles/PDFs, save, progress | `me/library/` |
| More | `ClientMore(Web)` | Profile, coach card, sessions, units, notifications, devices, delete account | `auth/…`, `me/…` |
| About | `ClientAbout(Web)` | App info | — |

Not built (D-06): `ClientFood`, `ClientNutrition` — replaced by `ClientMealNutrition`.
