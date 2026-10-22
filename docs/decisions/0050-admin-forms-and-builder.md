# D-50 · Admin Forms & check-ins and the Form builder

**Date:** 2026-10-22 · **Boards:** Forms, FormsMobile, FormBuilder, FormBuilderMobile

## What was decided

1. **Real forms, real questions.** The list and the builder read the forms in the database. The onboarding
   questionnaire ("New client questionnaire", 57 questions) is the one the client app asks at sign-up (D-36),
   not the board's old 15 sample questions (Gautam: "ye old wala mat rakhna"). PAR-Q stays a form in this list,
   sent from Forms, not asked in onboarding (D-49).
2. **Drafts on a published form.** The board saves every change at once ("Changes are saved automatically")
   and also says "Clients get the old version until you publish". So a change to a published form is kept in
   `Form.draft_questions` (JSON list of questions, ids kept) and the form shows **Draft** with **Publish**.
   The form stays `published`, so the weekly / daily check-in and onboarding keep working with the live
   questions. Publish writes the draft into the questions (answered questions that were removed are hidden,
   not deleted). A form that was never published saves straight into its questions.
   - ⋯ **Move back to draft** starts a draft of the live questions; its toast **Undo** throws the draft away
     (`discard/`).
   - Duplicate copies what the builder shows (the draft when there is one).
3. **Onboarding questions that fill a profile field** (`profile_key`) keep their answer type and options; the
   builder lets you change only the words, help text and Required (a note in the editor says so). Removing one
   means the app no longer asks it; a new question is an extra question (D-36).
4. **How it is sent.** Automations that send the form first ("+N more"). When none, the way the app itself asks
   it: `Client setup · asked at sign-up` (the live questionnaire), `Client app · every week, due Sunday 6 pm`
   (the live weekly), `Client app · every day` (the live daily). Else "Sent by hand" + Set up automation.
5. **Answers so far** (this month, clients the person can see): weekly = active clients × Sundays so far, daily =
   active clients × days so far, questionnaire = clients who joined / finished, other forms = sent requests /
   filled. "See <name>'s answers" opens the latest client's profile on the Forms tab (the board says
   "Check-ins"; the app's client profile tab with form answers is called Forms, so the hint says Forms).
6. **Small changes from the board:** a choice question may have one option when "Other" is on ("No" + Other,
   used by the questionnaire). Up to 80 questions (the questionnaire alone has 57). Header ⋯ has the board's
   three items (Duplicate form, Move back to draft, Archive form). On narrow pages (no palette) the dashed
   Add question opens the 9 answer types as a sheet first, as on FormBuilderMobile.

## API
- `GET forms/` rows: `built_in`, `has_draft` added. `GET forms/<id>/`: `questions` = draft or live, `sent_by`,
  `built_in`, `stats {sent, answered, rate, latest {id, first_name}}`.
- `PUT forms/<id>/questions/`: draft on a published form. `POST publish/` returns the detail.
- New: `POST forms/<id>/draft/`, `POST forms/<id>/discard/`.

## Code
`backend/apps/checkins/library.py` (new), views.py, serializers.py, models.py + migration 0007,
`backend/tests/test_forms_library.py`; `app/lib/features/admin/forms/` (forms_common.dart, forms_screen.dart,
form_builder_screen.dart), router `/forms`, `/forms/:id`.
