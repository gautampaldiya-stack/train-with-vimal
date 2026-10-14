# D-09 · Tree editors save the whole tree, update rows by id

- **Date:** 2026-10-14
- **Status:** Accepted

## Decision
Program, meal plan, form, supplement and automation editors send the whole tree in one PUT. Rows with an id are updated in place, so logs stay linked. Undo sends the previous tree back.

## Why
Logs stay linked when a plan changes; easy Undo.
