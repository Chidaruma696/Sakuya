## 1. Sessions as rows, with a limit per user

- [x] 1.1 Migration: `user_sessions` (user, token digest, started_at, last_used_at, device), `users.session_limit` (default 1, check 1..5), `sales.uploaded_by_id`; schema on SQLite and PostgreSQL
- [x] 1.2 `UserSession`: start (new token, digest stored, surplus beyond the limit ended oldest first), find by cookie (constant-time compare), end; a short device reading from the User-Agent; model tests
- [x] 1.3 `start_session`, `user_from_cookie` and `close_session` go through `UserSession`; the cookie carries `session id:token:user id`; `User#session_stamp` goes away; a password change or switching the user off ends every session (changing one's own keeps the current one); tests: limit of 1, limit of 2, two users, signing out, copied cookie
- [x] 1.4 The limit in the user form (`admin.users`), validated 1..5; lowering it ends the surplus; texts in en, es and de; tests

## 2. The device left behind

- [x] 2.1 A cookie whose session is gone: pages go to sign-in with `session.opened_elsewhere` or `session.closed_idle`; JSON gets 401 with the notice and `signed_out: true`; the cookie is deleted; texts in en, es and de; tests for page, JSON and a never-valid cookie
- [x] 2.2 `GET /till/token` and `POST /till/checkout` answer the same 401 to a signed-out till; test that nothing is recorded

## 3. "Are you still there?"

- [x] 3.1 Server: `last_used_at` moves on requests a person causes (not on `X-Background`), written at most once a minute; a session unused for longer than `IDLE_AFTER + COUNTDOWN` is ended; `POST /session/keep`; the 14-day cookie window is removed; tests with `travel`
- [x] 3.2 The till's upload, token and catalog requests send `X-Background: 1`; test that an abandoned till's session ends while it keeps polling
- [x] 3.3 `idle_controller.js` and its dialog in the layout: the 15-minute timer restarted by keys, clicks, touches and scans; the countdown; "I'm still here"; sign out at zero; a keep-alive at most every 5 minutes while working; activity shared between tabs; nothing while offline; texts in en, es and de
- [x] 3.4 (headless Chrome, 10 Nov: the dialog, the countdown, a stray key ignored, answering, letting it close, two tabs) Seen in a real browser: the dialog, the countdown, answering, letting it close, two tabs, and a till left alone

## 4. Sessions in the user list

- [x] 4.1 The user list shows each live session (since, last used, device) with an "End" button; `DELETE /admin/users/:user_id/sessions/:id` (`admin.users`); texts in en, es and de; tests for the list, the button and the refusal without permission

## 5. The shift stays out of it

- [x] 5.1 Tests only: a shift stays open, with its figures, through every way a session ends; whoever signs in next sells on it; a user moved to another branch finds that branch's own shift

## 6. Offline sales keep their seller

- [x] 6.1 `Till.checkout!` takes `uploaded_by:`; the controller resolves `sold_by` (offline only, same branch, active or not); reviews and rule permissions go by the seller; tests for every scenario in the spec
- [ ] 6.2 (done: sales list, Review and REPL; pending: the printed ticket and ESC/POS) The ticket, the sales list and Review show "uploaded by" when it differs from the seller; the REPL's `(sales)` gets `:uploaded-by`; tests
- [x] 6.3 `offline.js` / `pos_controller.js`: the queued sale stores the signed-in user's id and sends it as `sold_by`

## 7. The till without a session

- [x] 7.1 `pos#sync` and `pos#checkout` read the 401: the banner shows "sign in on this device to upload N sales" with a link, the retry timer stops, checkout is refused with the same notice; the queue is not touched; texts in en, es and de
- [x] 7.2 (headless Chrome, 10 Nov) Seen in a real browser with the server running: sign in on a second browser, watch the first till get the notice with sales queued, sign in again and watch them upload under the right cashier

## 8. Docs and checks

- [ ] 8.1 (done: decisions and both READMEs; pending: architecture) `docs/decisions.md` (limit per user and why a number, oldest session ends, the idle rule and why background requests do not count, why the seller id is trusted), `docs/architecture.md`, both READMEs
- [ ] 8.2 (done: SQLite, rubocop, brakeman; pending: PostgreSQL, which CI runs on push) Full suite on SQLite and PostgreSQL, rubocop and brakeman clean
