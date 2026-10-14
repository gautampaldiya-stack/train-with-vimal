# Auth and onboarding

Boards: `ClientLogin(Web)`, `ClientWelcome`, `ClientHealth(Web)`, `ClientIntro`, `ClientJoinLink(Web)`, `ClientVerifyEmail(Web)`,
`ClientResetPassword(Web)`, `ClientPermissions(Web)`. Behaviour: `../screens/behaviour.md` §5.

## Login
- One login screen for all roles. Email **or** mobile + password. Wrong details → one generic message (never says which part is wrong).
- After login the app opens the role's home: Admin dashboard, Trainer dashboard, or Client Home.
- Forgot password → email link → Reset password screen (link checked first; expired/used links show their own state).
- Every login is a **session** (device, platform, city, last active). Users can log out one device or all others.

## Joining
| Way in | What happens |
|---|---|
| Coach adds the client | Client gets a login link → picks a password → in (no approval) |
| Invite link (`/join/<code>`) | Client signs up → waits in **Approvals** (unless the link skips approval) |
| Approval decisions | Approve (pick trainer), Reject (reason + message), Ask for info (pick items + channels) |

Invite links: label, trainer, expiry, max uses, needs approval, on/off.

## Onboarding (client, 5 steps)
1. Account made (email and phone checked)
2. Basic details (name, age, city)
3. Goal and body (goal, height, weight, target)
4. Health and PAR-Q (7 health questions; "yes" answers flag the trainer)
5. Food preferences

Steps can be skipped and finished later; Home shows what is left. Onboarding reminders go out on a schedule until done.
Then: Intro slides and Permissions (notifications, camera/photos, health data) screens.

## Verify email
Changing email sends a link to the new address; the old address stays active until verified. Resend and cancel are allowed.
