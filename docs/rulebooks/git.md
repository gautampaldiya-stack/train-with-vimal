# Rulebook — Git

- `working` = all daily work. `develop` = testing (merge `working` → `develop` when Gautam wants to test). `main` = production.
- Commit in meaningful chunks, not every small edit. Message: short title + what changed.
- Author and committer: `Gautam <gautampaldiya@gmail.com>`:
  `git -c user.name=Gautam -c user.email=gautampaldiya@gmail.com commit -m "..."`
- No Claude / Anthropic names, no `Co-Authored-By`, no session links.
- Never commit `backend/.env`, keys, `google-services.json`, `GoogleService-Info.plist` or service-account JSON.
- Update the matching doc (decisions, phases, changes) in the same commit.
- Push `working` after every finished piece (a screen, a module), and update `docs/phases/CURRENT.md` + the phase checklist in the same commit.
  Usage limits can stop a session at any time; the repo must always be enough to resume.
