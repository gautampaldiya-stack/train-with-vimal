# D-49 · Client fills the forms the coach sends; admin Check-ins; notification links

Date: 2026-10-22

## Decision
- **New boards `ClientForm` / `ClientFormWeb`** (made from ClientCheckin, approved by Gautam). Until now a client had
  no page to fill a form the coach sent (Monthly feedback, Liability waiver, PAR-Q, a trainer's own form): the
  backend had `FormRequest` and the submit endpoint, the app had nothing.
- **Check-ins page shows a card per form** (`me/checkins/` → `forms`): waiting forms first (oldest due first) with
  "To fill", the question count and time ("3 questions. Takes about a minute.", about 20 s a question), up to 5
  question chips, a draft bar and "Continue form" when a draft is on the phone. Forms filled in the last 14 days
  stay as a green "Sent" card. Weekly and daily requests are left out: they have their own cards.
- **The form page** is `/checkins/forms/<request id>` (`GET me/forms/<id>/`): one question a page with the weekly
  check-in's look, every question type (yes / no and single as radio rows, pick-many as checkboxes where a "None…"
  option clears the others, dropdown as radio rows, number with the number keyboard, scale 1–5, short, long,
  photos by slot), Optional tag, required questions block Next, review page with Edit, "Send to Aman", sent card
  with every answer, toast with Undo. Answers are a draft on the phone (`form:draft:<id>`) until sent; sending goes
  through the outbox, so it works offline.
- **The router gets a third level** (`/:section/:id/:sub`) for this path; map key `/checkins/forms/:sub`.
- **Server rules:** a request already filled can not be sent again ("You sent this form already."); Undo (delete
  the submission, same 24 h / not reviewed rule) puts the request back to "To fill"; another client's request is 404.
- **Notification links:** form sent / reminder open the form (`/checkins/forms/<id>`; weekly and daily requests open
  their own form). Session notifications open `/train` and trainer meal plans `/nutrition/<id>` (the old
  `/sessions/<id>` and `/meal-plans/<id>` pages never existed).
- **Admin Check-ins:** `/checkins` and `/checkins/<id>` for the admin reuse the trainer Check-ins page over every
  client (there is no admin Check-ins board; the dashboard's "Check-ins to review" opens it).
- **PAR-Q is not part of the new onboarding** (its Health step has its own questions). It stays a built-in form on
  Forms & check-ins; a coach sends it and the client fills it on this page (Gautam, 22 Oct).
- Question chips for the built-in forms (Monthly feedback, Liability waiver, PAR-Q) were added to `CHIPS`.
