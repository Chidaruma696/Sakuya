## Why

A user can be signed in on any number of devices at once, and a session left open on a shared computer stays usable for as long as someone keeps visiting. Whatever happens under that name could then have been done by anyone in front of one of those screens: Review points at a name, not at a person. The database already refuses to record the same thing twice; what is missing is that a user name means one person at one screen, and that a screen nobody is using closes by itself, the way a banking app does it.

## What Changes

- **A limit of live sessions per user, one unless the administrator says otherwise.** Each user has a number of sessions they may hold at once (1 by default), set in the user form by someone with `admin.users`. Signing in beyond the limit ends that user's oldest session. The device left behind finds out on its next request and is sent to the sign-in screen with the reason: the session was opened on another device.
- **"Are you still there?"** After 15 minutes without anyone touching the screen, a dialog asks, with a clock counting down. Answering keeps the session; letting the clock reach zero signs the device out. The server enforces the same limit, so closing the dialog by other means changes nothing.
- **Signing out ends that session for real**, not only on the device that pressed the button.
- **The session and the till shift are separate things.** A session ending (by another sign-in, by the clock, by signing out) never closes the shift: the shift closes when someone chooses to close it and counts the drawer, as today. Each branch has its own shift, opened with its own float and counted on its own.
- **Sales made offline keep their cashier.** A sale waiting on a device remembers who made it. When it is uploaded, by whoever is signed in on that device by then, it is recorded under the name of the person who sold it; the uploader is kept too.
- **A till that lost its session says so.** With sales waiting to upload and no session, the till shows that it must be signed in to upload them, and how many are waiting. Nothing waiting is lost or discarded.
- **The administrator can see and end sessions**: the user list shows each user's live sessions (since when, last used, on what kind of device), with a button to end each one.

The first sign-in after the update is also the moment everyone is asked to sign in once more.

## Capabilities

### New Capabilities
- `user-sessions`: signing in and out, how many sessions a user may hold, what the device left behind is told, the idle question and its countdown, ending sessions from the user list, and whose name an offline sale is recorded under.

### Modified Capabilities

None. The till's offline queue and the shift are described here only where the session touches them.

## Impact

- **Schema**: a new table `user_sessions`; `users.session_limit` (default 1); `sales.uploaded_by_id`.
- **Code**: `ApplicationController` (session start, check, activity and end), `SessionsController` (sign in, sign out, keep alive), `Admin::UsersController` with its form and list, `TillController#checkout` and `Till.checkout!` (the seller of an offline sale), a new `idle_controller.js` with its dialog in the layout, `pos_controller.js` and `offline.js`.
- **Translations**: en, es and de.
- **Docs**: `docs/decisions.md`, `docs/architecture.md`, both READMEs.
- **Not touched**: permissions and roles, the rules in Lisp, the password itself, the wait after wrong passwords, opening and closing shifts.
- **Not in this change**: a PIN or second factor; registering trusted devices; switching cashier at a till without signing out; a history of past sign-ins; making the 15 minutes a setting.
