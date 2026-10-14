# Rules

## Product
1. UI same-to-same as the canvas (`design/screens`). Every button does something. No "coming soon".
2. Clients log; they never change their plan.
3. Trainers only see their own clients unless Admin gives wider access.
4. Every screen works on phone, tablet and desktop.

## Code
1. Read `docs/screens/behaviour.md` for a screen before building it.
2. No hard-coded colours, sizes or fonts in Flutter — use theme tokens.
3. Every list that can grow is paginated and filtered in the database.
4. Every client query goes through `visible_clients()`.
5. Validate on the server even if the app already validated.
6. Writes from the client app send an `Idempotency-Key`.
7. Keep docs in sync in the same commit (`docs/changes.md` for anything that changes a decision).

## Git
1. Daily work on `working`. Merge to `develop` for testing. `main` = production.
2. Meaningful commits, not one per tiny edit.
3. Author and committer: `Gautam <gautampaldiya@gmail.com>`. No Claude/Anthropic names or trailers.
4. Never commit `.env`, keys, or service-account files.

More detail: `../rulebooks/`.
