# D-47 · Admin Clients and Approvals

Date: 2026-10-22

## Decision
- **One Clients page for both roles.** The admin Clients page (boards `Clients` / `ClientsMobile`, route `/clients`)
  is the trainer's My clients code with `admin: true`: every client (not only own), a Trainer and a Joined column,
  Trainer in Filter (Anyone / each trainer / No trainer), sub line "N clients · N active · N need a trainer", and
  `Invite link` + `Add client` at the top (icons only on narrow widths). Row ⋯ adds `Change trainer`,
  `Pause` / `Resume` (confirm, Undo) and `Delete client` (confirm, Undo through `restore/`). Phone rows show a
  "No trainer" badge or "Trainer · Goal". Export stays off, the same as My clients (Gautam, D-33).
- **Client profile for admin** (boards `ClientProfile` / `ClientProfileMobile`, route `/clients/<id>`) is the trainer
  client profile with `admin: true`: breadcrumb "Clients", sub line "Trainer X" / "No trainer", header menu
  `Change trainer`, Coaching card Trainer row with `Change` (or `Pick one`), no "(you)".
- **Edit details (admin only extras).** A "Sign-in" section: set a new password (min 8, checked by Django's
  password rules, saved only as a hash, signs the client out on every device, sends a "password changed" notice)
  or `Send a reset link` (email). Trainers can't send a password (403). A "Trainer" line with `Change trainer`.
- **Add client drawer** (admin): Must have (name, mobile with a live "already used" check), Good to have, Goal and
  body, Coaching (trainer with load, workout program, meal plan, plans start date, default next Monday), Access
  (`Active now` / `Send to Approvals`, send login link, ask for PAR-Q). Everything is saved in one transaction, so a
  bad program or meal plan leaves nothing half made. After saving, a toast with `View` (or "is in Approvals").
- **Change trainer drawer**: search, trainers with load bar and tags (Current, Full, Good fit; full ones can't be
  picked), switches, a note for the new trainer (saved as a client note), button "Move to X".
  - "Move open check-ins" is on by default. Off means the open check-ins are marked as seen, so the new trainer
    starts fresh (moving is what happens anyway, because check-ins belong to the client, not the trainer).
  - "Tell old trainer" sends the old trainer a notice that the client moved. The board's "keeps read-only access"
    line is not true in this app (a trainer only sees their own clients), so the sub line says only the notice.
  - `ClientProfile.trainer_since` is new: set on approve, Add client and Change trainer; the drawer shows "since".
- **Invite links modal** (boards' `il-modal`): three tabs.
  - Invite link: real QR code, Copy, WhatsApp, Email, Download QR (PNG). Settings save at once.
  - New link: trainer, name, expiry, max people, code (3 suggestions).
  - All links: summary numbers, rows with ⋯ (open, copy, on / off, delete with Undo).
- **Approvals page** (boards `Approvals` / `ApprovalsMobile`, route `/approvals`, `?tab=history`):
  - Waiting: oldest first, people moved back on top with a "Moved back" tag. Search name, phone or email.
    Filter: Invited by, Profile setup, Waiting, Health note, Signed up from. Chips with × and Clear. 20 a page.
    Amber after 1 day, red after 2 days. Phone: one line per person with a `Review` button (as ApprovalsMobile).
  - Review drawer: setup / invited by / waiting numbers, health note, contact, setup checklist, onboarding answers,
    trainer pick (Invited them / Good fit / Full tags, full can't be picked), approve switches; footer Reject (red),
    Ask for info, `Approve and assign` (or `Approve anyway` when setup is not finished). `‹ ›` step through the page.
  - Reject modal (reason required, "Something else" needs a message), Ask for info modal (things to ask and
    channels), History with `Move back` modal for rejected people.
  - The sidebar badge loads the waiting count on app start for admin, not only after the page opens.
  - The sub line's "oldest waiting" comes from `approvals/counts/` (`oldest_hours`), so it is right on every page.
- **Pronouns.** Texts use she / he / they from the client's gender, with matching verbs ("They see", "She sees").

## Not built
- The board's invite-link summary card on the Approvals page (top 3 links). The same data is in the Invite link
  modal's `All links` tab, opened from the header button.
- Export on Clients (off on purpose).
