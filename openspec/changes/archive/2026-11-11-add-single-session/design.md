## Context

Since 2026-11-10 the session cookie carries `"<user id>:<stamp>"`, where the stamp is derived from the user's password digest (`User#session_stamp`). It expires after 14 days without use and every page visit pushes it back. Changing the password or switching the user off ends every session. Nothing distinguishes one device from another: every device of the same user holds the same stamp, so all of them are valid at once, and nothing ever asks whether someone is still in front of the screen.

The till works offline: the page is served from the service worker's cache, sales are queued in IndexedDB on the device, and `pos#sync` uploads them every 30 seconds through `POST /till/checkout` after asking `GET /till/token` for a fresh CSRF token. An uploaded sale is recorded under `current_user`, whoever that is at upload time.

The shift (`Shift`) belongs to a branch, not to a user or a session: one open shift per branch, opened with a float and closed by counting. Nothing in this change alters that.

## Goals / Non-Goals

**Goals**
- A user name in Review, on a ticket or in the kardex means one person at one screen, unless the administrator decided that user may hold more.
- A screen nobody is using closes by itself, with a warning first.
- Losing a session never loses a sale, never changes who sold it and never closes a shift.
- The device that was left behind is told why, in plain words.

**Non-Goals**
- Stopping two different users from working at once (the duplicate guards already cover what could collide).
- Device registration, PINs, two-factor.
- A sign-in history.

## Decisions

### 1. Sessions are rows, and each user has a limit

`user_sessions` holds one row per live session: user, a digest of its token, when it started, when it was last used and a short reading of the device. The cookie carries `"<session id>:<token>:<user id>"`; a request is signed in when the row exists, the digest matches (constant time) and the session has not gone idle (decision 3).

`users.session_limit` (integer, 1 to 5, default 1) is how many live sessions that user may hold. It is a field in the user form, next to the role, for whoever has `admin.users`. Signing in creates a row; if the user then holds more than their limit, the oldest rows (by start) are deleted. Lowering a user's limit deletes the surplus the same way.

Signing out deletes the row. Changing the password or switching the user off deletes all of that user's rows, which replaces the password-derived stamp; someone changing their own password keeps the session they are in.

*Why a number per user and not a permission:* a permission can only say yes or no, and "any number of sessions" is exactly what this change removes. A number lets the head office administrator hold a desktop and a phone (2) without opening the door for everyone with that role.

*Why not refuse the sign-in when the limit is reached:* a device that is switched off, stolen or broken would lock its user out until an administrator stepped in. Ending the oldest means the person in front of a screen with the right password always gets in.

*Why a table now:* with a limit above one there can be several live sessions per user, each ended on its own (the idle clock, the administrator's button). The token is stored as a digest so that reading the table does not give anyone a session.

### 2. The device left behind is told why

A request whose cookie names a session that no longer exists is not an anonymous visitor: it is a device that lost its session. Pages redirect to sign-in with a notice; JSON requests answer 401 with the same text and `{ signed_out: true }`. The stale cookie is deleted so the message shows once. To give the right reason after the row is gone, the cookie also carries the user id, and `users.session_ended_reason`/`_at` is not needed: the reason is derived (an idle session is found by its own `last_used_at`; anything else that is missing was ended elsewhere).

A cookie that never matched (tampered, or from before this change) gets the ordinary "sign in to continue".

### 3. "Are you still there?": 15 minutes, then a countdown

Three constants: `IDLE_AFTER = 15.minutes`, `COUNTDOWN = 60.seconds` and, on the server only, `GRACE = 2.minutes`.

**In the browser** (`idle_controller.js`, on every signed-in layout): any key, click, touch or scan restarts a 15-minute timer. When it runs out a dialog opens over everything, in the style of the existing dialogs: "Are you still there?", a clock counting down from 60 and one button, "I'm still here". The button (or any key) calls `POST /session/keep`, closes the dialog and restarts the timer. At zero the page calls `DELETE /logout` and goes to the sign-in screen with "the session closed after 15 minutes without use". Activity in one tab is shared with the others through `localStorage`, so two tabs do not ask twice or close each other.

**On the server**, the same limit holds whatever the browser does: a session whose `last_used_at` is older than `IDLE_AFTER + COUNTDOWN + GRACE` is treated as ended and deleted. The margin exists because the server's clock runs behind the screen's (see the keep-alive below): without it, someone who answers in the last seconds could be turned away. `last_used_at` moves on requests a person causes: page loads, form posts, the checkout, and `POST /session/keep`. It does not move on what the page does by itself: the till's 30-second upload and its token and catalog requests send a header (`X-Background: 1`) and are left out, otherwise an abandoned till would stay alive forever. While someone is working, the browser also calls `/session/keep` at most once a minute if there was activity, so that a long ticket being typed does not run the server's clock out.

The 14-day cookie window goes away: the cookie lasts as long as the browser session plus the idle rule, which is always the shorter leash.

**Offline** the clock does not close anything: a till without a network cannot sign back in, and closing it would stop the selling that offline mode exists for. The dialog and the countdown only run while the device is online; the server applies its limit when the device comes back, and decision 6 takes over from there.

### 4. The shift does not follow the session

No way of ending a session closes, pauses or reassigns a shift. The shift stays open in its branch until someone with `till.open` closes it by counting the drawer, and whoever signs in next at that branch finds it open. A user who signs in at another branch works with that branch's own shift, with its own float and its own count.

The only contact is a warning: the idle dialog and the "session opened elsewhere" notice say nothing about the shift, and the sign-in screen does not either. This is stated here because the question came up, not because code changes.

### 5. Sessions in the user list

The administrator's user list shows, per user, their live sessions: since when, last used and the device ("Chrome on Windows", "Safari on iPhone"; the raw User-Agent is not stored), each with an "End" button (`admin.users`) that deletes the row. The limit shows next to the name when it is not 1.

### 6. An offline sale carries its seller

When a sale is queued, the device stores the seller's user id next to it. On upload the id travels as `sold_by`. The server records the sale under that user when all of these hold, and otherwise under the uploader as today:
- the sale comes with `sold_at` (it is an offline upload);
- `sold_by` is a user of the same branch as the uploader, active or not (a cashier who was switched off after selling still sold it).

`sales.uploaded_by_id` keeps who uploaded it when that is someone else. The reviews an offline sale opens go under the seller's name; whether a rule would have stopped it is judged with the seller's permissions.

*Why trust an id sent by the browser:* it can only name a user of the uploader's own branch, it only applies to offline uploads, and the uploader is always recorded next to it. Signing each queued sale on the device would need a secret the device holds offline, which protects nothing.

### 7. The till without a session

`pos#sync` already stops when `/till/token` does not answer with a token. With this change the 401 tells it why: the connection banner shows "Sign in on this device to upload N sales" with a link to the sign-in screen, and the automatic retry stops until the page is loaded again. The queue is untouched. After signing in (as anyone of the branch) the till page loads, `sync` runs and the sales go up under their sellers.

A till that knows its session is gone does not check out: the notice takes the place of the checkout button until someone signs in. A till that is offline cannot know, and keeps selling as today.

## Risks / Trade-offs

- **People sharing one user sign each other out** → Intended and documented; the fix is one user per person, or raising that user's limit knowingly.
- **A cashier is asked "are you still there?" in a slow hour** → One key press answers it; scanning a product counts as activity. Letting it close costs a sign-in, never a sale or the shift.
- **A raised limit brings back shared sessions** → Only by an explicit choice of the administrator, per user, capped at 5, and every session is listed with its device.
- **`sold_by` could be abused to sell under a colleague's name** → Only offline uploads, only users of the same branch, and `uploaded_by_id` records who really sent it.
- **One write per person-caused request on `user_sessions`** → To keep it light, `last_used_at` is only written when it is more than a minute old.
- **The service worker serves a cached page to a signed-out device** → Expected: the page loads, its first request gets the 401 and shows the notice.

## Migration Plan

1. Migration creates `user_sessions` and adds `users.session_limit` (default 1, not null) and `sales.uploaded_by_id` (nullable); no backfill.
2. On deploy every existing cookie stops matching (there are no rows yet): everyone signs in once. Sales already queued on devices have no seller id and are recorded under whoever uploads them, exactly as before.
3. Rollback: revert the code; the table and columns can stay unused.

## Open Questions

1. **How long is the countdown?** The design says 60 seconds after the 15 minutes.
2. **Does the till get the same 15 minutes as the office screens?** The design treats every screen alike. A till in a quiet shop will ask often; the alternative is a longer wait on the till screen only.
3. **Warn before taking over a session?** For example "this ends your session on Chrome on Windows, open since 08:12". The design does not ask; it ends the oldest and goes ahead.
4. **Is 5 the right ceiling for the limit?** And should the installing administrator start with 2 instead of 1?
