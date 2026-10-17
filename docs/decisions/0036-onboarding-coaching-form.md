# D-36 · Onboarding = the gym's coaching form, answers on the profile

Date: 2026-10-17

## Decision
- Gautam chose: "Client onboarding ko aapke Google Form (52 questions) jaisa bana dein — Haan, poora form"
  (his "Online Training Form TWV"). The client setup asks it in **9 steps**: Your goal · About you · Training ·
  Health & injuries · Food & lifestyle · Your day of eating · Supplements & medicines · Measurements & photos ·
  Last step (note, extra questions, terms + "I agree"). Phone and web layouts are the setup boards' (`wl-onb`).
- One list, `backend/apps/clients/onboarding.py` `FIELDS`, says for every answer its key, step, kind, question,
  required mark and where it is kept. The setup check / save, Edit profile, Overview → About and Forms → Onboarding
  questionnaire all read it. No answer lives only in the app.
- Answers are **ClientProfile fields** (migration `clients/0005`): goal_detail, experience, enrolled_for, workout_days,
  workout_place, workout_time, current_exercise, activity_level, injury_areas, conditions, doctor_ok, past_injuries,
  surgeries, addictions, digestive_issues, stresses, diet_type, common_foods, food_allergies, smoking, 7 meal_* fields,
  takes_supplements, supplements_detail, supplement_brands, open_to_supplements, takes_medicines, medicines_detail,
  onboarding_note, terms_agreed_at. Phone, date of birth and gender stay on User; current injuries = `health_notes`.
  Choice fields keep an option key, or the client's own words when they picked "Other" (or "Yes" for allergies /
  smoking).
- Age is never stored: it is worked out from the date of birth (the form's "Age" is asked as a date of birth, picked
  not typed). Weight is saved as the first weigh-in (`WeightLog.source = onboarding`), the 11 measurements as the
  first Measurement (cm), the 3 photos as the "Start photos" set (front / right side / back).
- The onboarding questionnaire is still a Form the admin edits ("New client questionnaire"). Each question has
  `Question.profile_key` (migration `checkins/0006`). A removed question is not asked, a renamed one shows the new
  words, a question with no key is an **extra** question: asked on the last step, kept in
  `onboarding["agree"]["extra"]` by question id and listed in Forms → Onboarding questionnaire. `seed_defaults`
  turns an old questionnaire (no keys) into the coaching form; answered old questions stay readable.
- Edit profile drawer (My clients → Edit details, Client profile → Edit profile): Must have, Good to have, Goal and
  body as on the board, plus Training, Health, Food and lifestyle, Supplements and medicines. Selects for choices
  (options from `clients/<id>/` `options`), "Other…" opens a text box, chips for lists, multi-line boxes for text,
  date picker for the date of birth (age shows next to it). `PATCH clients/<id>/` takes every field; goal / goal
  weight / health note changes still go to History.
- About card = `overview.about.items` from the server: Age, Gender, Height, Start weight, Now, Goal weight, Diet,
  Trains at, Experience, Daily activity, Workout time, Injuries, Enrolled for, Medicines, Food allergies; "—" only when
  nothing is there.
- Demo: `seed_demo` fills every answer for every client who finished setup (Riya and Aditya as written in
  `PERSONAS`, the others from pools), first measurements and start photos where there were none.

## Not done
- The form's "Email" and "Full name" questions are not asked again (the account has them).
- Photo-type extra questions the admin adds are not asked in the setup (photos go through the 3 start photo slots).
