# D-15 · Account links: full pages, lifetimes from the boards, why an invite ended

- **Date:** 2026-10-15
- **Status:** Accepted

## Decision
1. **Forgot password is a page, not a sheet.** Log in → "Forgot password?" opens `/forgot` (board `ClientResetPassword`,
   states forgot → sent). The email link opens `/reset-password?token=…` on the same board (states set → done, or bad).
   The old "Forgot password" bottom sheet is removed.
2. **Link lifetimes come from the boards** (`TOKEN_TTL_MINUTES` in settings):

   | Link | Lifetime | Board text |
   |---|---|---|
   | Reset password | 15 minutes | "It works once, for 15 minutes." |
   | Verify email | 24 hours | "The link works once, for 24 hours." |
   | Login link (coach added the client) | 7 days | — |

   Every link works once. Emails say the same lifetime.
3. **An invite link says why it stopped.** `InviteLink.end_reason` = `expired` / `full` / `off` (null while it works).
   `GET join/<code>/` returns `reason`, and `POST` refuses with `link_expired` / `link_full` / `link_off`.
   The join page shows a different message for each (board `ClientJoinLink`, state bad).
4. **"This is not me"** on the login link page calls `POST auth/login-link/not-me/`: the link is used up and the coach
   gets a `login_link_not_me` notification.

## Pages and routes (Flutter)
| Route | Board | Who |
|---|---|---|
| `/forgot` | ClientResetPassword (forgot, sent) | signed out |
| `/reset-password?token=` | ClientResetPassword (set, done, bad) | anyone (from email) |
| `/join/:code` | ClientJoinLink (inv, form, made, bad) | signed out |
| `/login-link?token=` | ClientJoinLink (log, ready, bad) | anyone (from email / SMS) |
| `/verify` | ClientVerifyEmail (inbox, ok) | signed in, email not verified |
| `/verify-email?token=` | ClientVerifyEmail (checking, ok, bad) | anyone (from email) |
| `/permissions` | ClientPermissions | signed-in client, after verify |

## Why
Gautam tests flows end to end; a link in an email must land on its own page. The boards state the lifetimes, so the
backend and the emails must say the same thing.
