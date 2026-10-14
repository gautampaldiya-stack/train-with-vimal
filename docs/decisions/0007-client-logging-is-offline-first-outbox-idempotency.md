# D-07 · Client logging is offline-first (outbox + `Idempotency-Key`, server accepts back-dated logs up to 7 days)

- **Date:** 2026-10-14
- **Status:** Accepted

## Decision
Client logs (food, sets, habits, water, check-ins) go to a local outbox with an `Idempotency-Key` and the local time, then sync when online. The server replays the stored response for a repeated key, so nothing is doubled, and accepts logs up to 7 days back.

## Why
Bad network on the gym floor; logs must never be lost or doubled.
