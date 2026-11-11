# User sessions

## Purpose

How many devices a user can be signed in on at once, what ends a session (a sign-in elsewhere, a screen nobody uses, signing out, a password change, an administrator), what the device left behind is told, and under whose name an offline sale is recorded. A session never closes a till shift.

## Requirements

### Requirement: A user holds as many sessions as their limit, one by default
Every user SHALL have a session limit between 1 and 5, 1 unless someone with `admin.users` sets another. Signing in SHALL always succeed with the right password and, when the user would then hold more sessions than their limit, SHALL end their oldest ones.

#### Scenario: Signing in on a second device with a limit of 1
- **WHEN** a user with a limit of 1 who is signed in on device A signs in on device B
- **THEN** device B is signed in and the next request from device A is not

#### Scenario: A limit of 2
- **WHEN** a user with a limit of 2 who is signed in on devices A and B signs in on device C
- **THEN** B and C are signed in and A, the oldest, is not

#### Scenario: Two different users at once
- **WHEN** two different users are signed in, each on their own device
- **THEN** both stay signed in

#### Scenario: Setting the limit
- **WHEN** an administrator saves a user with a limit of 2
- **THEN** that user can be signed in on two devices at once

#### Scenario: Lowering the limit
- **WHEN** an administrator lowers to 1 the limit of a user who holds two sessions
- **THEN** the older of the two is ended

#### Scenario: A limit out of range
- **WHEN** a user is saved with a limit of 0 or of 6
- **THEN** it is refused

#### Scenario: Without the permission
- **WHEN** a user without `admin.users` tries to change a session limit
- **THEN** it is refused

### Requirement: The device left behind is told why
A device whose session was ended SHALL be told why, in the user's language, the first time it asks for anything.

#### Scenario: Ended by a sign-in elsewhere, page request
- **WHEN** a device whose session was ended by a sign-in on another device requests a page
- **THEN** it is sent to the sign-in screen with a notice that the session was opened on another device

#### Scenario: Ended, background request
- **WHEN** a device whose session was ended sends a JSON request
- **THEN** the answer is 401 with the notice and a mark that it was signed out, and nothing is recorded

#### Scenario: A device that never had a session
- **WHEN** a device with no session, or with a session cookie from before this change, requests a page
- **THEN** it is sent to the sign-in screen with the ordinary request to sign in

### Requirement: A screen nobody uses asks, counts down and closes
After 15 minutes without anyone using a signed-in screen, it SHALL ask whether the user is still there and show a countdown of 60 seconds. Answering SHALL keep the session; the countdown reaching zero SHALL sign that device out. The server SHALL end a session left unused for that long regardless of what the browser does.

#### Scenario: Nobody touches the screen
- **WHEN** a signed-in screen goes 15 minutes without a key, a click, a touch or a scan
- **THEN** a dialog asks "Are you still there?" with a clock counting down from 60 seconds

#### Scenario: The user answers
- **WHEN** the user presses "I'm still here" before the clock reaches zero
- **THEN** the dialog closes, the session continues and the 15 minutes start over

#### Scenario: Nobody answers
- **WHEN** the clock reaches zero
- **THEN** that device is signed out and shows the sign-in screen saying the session closed for lack of use

#### Scenario: The browser was closed or asleep
- **WHEN** a request arrives on a session not used for more than 18 minutes (the 15, the countdown and a margin of two)
- **THEN** it is not signed in and the device is told the session closed for lack of use

#### Scenario: Working counts
- **WHEN** a user keeps typing a long ticket for 20 minutes without loading another page
- **THEN** the dialog never appears and the session continues

#### Scenario: What the page does by itself does not count
- **WHEN** a till is left alone for more than 18 minutes while it keeps checking for sales to upload
- **THEN** its session is ended

#### Scenario: Two tabs
- **WHEN** a user works in one tab while another tab of the same session sits untouched
- **THEN** the untouched tab does not ask and is not signed out

#### Scenario: Offline
- **WHEN** a till that is offline goes 15 minutes without use
- **THEN** no dialog appears and it can keep selling

### Requirement: Signing out ends the session everywhere
Signing out SHALL end that session so that no copy of its cookie works afterwards, and SHALL leave the user's other sessions alone.

#### Scenario: A copied cookie after signing out
- **WHEN** a user signs out and a request arrives with the cookie that session had
- **THEN** the request is not signed in

#### Scenario: Another session of the same user
- **WHEN** a user with a limit of 2 signs out on device A
- **THEN** their session on device B continues

### Requirement: Password changes and switched-off users end every session
Changing a user's password or switching the user off SHALL end all of that user's sessions. A user changing their own password SHALL stay signed in on the device where they did it.

#### Scenario: An administrator changes another user's password
- **WHEN** an administrator changes the password of a user who is signed in
- **THEN** none of that user's devices is signed in on its next request

#### Scenario: Changing one's own password
- **WHEN** a signed-in administrator changes their own password
- **THEN** their next request from that device is still signed in, and their other devices are not

#### Scenario: A user is switched off
- **WHEN** a signed-in user is switched off
- **THEN** that user's next request is not signed in

### Requirement: Ending a session never touches the shift
No way a session ends SHALL close, pause or reassign a till shift. A shift SHALL close only when someone closes it by counting its drawer, and each branch's shift SHALL be opened and counted on its own.

#### Scenario: The session ends with the shift open
- **WHEN** a cashier's session ends, by a sign-in elsewhere, by the countdown or by signing out, while their branch has an open shift
- **THEN** the shift is still open, with the same float, sales and withdrawals

#### Scenario: Signing back in
- **WHEN** someone with `till.sell` signs in at that branch afterwards
- **THEN** they sell on the same open shift

#### Scenario: The same user at another branch
- **WHEN** a user who opened a shift at one branch is moved to another branch and signs in there
- **THEN** the first branch's shift stays open until it is counted and closed, and the other branch works with its own shift, opened with its own float

### Requirement: Administrators see and end sessions
The user list SHALL show each user's live sessions (since when, last used and what kind of device) and SHALL let someone with `admin.users` end any of them.

#### Scenario: The list shows who is signed in
- **WHEN** an administrator opens the user list while a cashier is signed in
- **THEN** the cashier's row shows when the session started, when it was last used and a short description of the device

#### Scenario: Ending a session
- **WHEN** an administrator ends a cashier's session from the list
- **THEN** the cashier's next request is not signed in and the row no longer shows that session

#### Scenario: Without the permission
- **WHEN** a user without `admin.users` tries to end someone's session
- **THEN** it is refused

### Requirement: An offline sale is recorded under whoever sold it
A sale made offline SHALL be recorded under the user who was signed in on the device when it was made, whoever is signed in when it is uploaded. When the two differ, the sale SHALL also keep who uploaded it.

#### Scenario: Uploaded by the same cashier
- **WHEN** a cashier sells offline and the sale is uploaded while that cashier is signed in
- **THEN** the sale is recorded under that cashier and has no separate uploader

#### Scenario: Uploaded by someone else
- **WHEN** cashier A sells offline, loses the session, and supervisor B of the same branch signs in on that device and the sale uploads
- **THEN** the sale is recorded under A, B is kept as who uploaded it, and anything it leaves in Review is under A's name

#### Scenario: The seller was switched off meanwhile
- **WHEN** an offline sale by a cashier who has since been switched off is uploaded
- **THEN** the sale is still recorded under that cashier

#### Scenario: A seller from another branch
- **WHEN** an upload names as its seller a user of a different branch than the uploader's
- **THEN** the sale is recorded under the uploader

#### Scenario: A sale made online
- **WHEN** a sale is checked out online and names a different seller
- **THEN** the sale is recorded under whoever is signed in

#### Scenario: A sale queued before this change
- **WHEN** a sale queued on a device before this change, with no seller, is uploaded
- **THEN** it is recorded under whoever uploads it

### Requirement: A till without a session keeps its sales and says what to do
A till whose session ended SHALL keep every sale waiting to upload and SHALL tell whoever is in front of it to sign in to upload them.

#### Scenario: The session ended with sales waiting
- **WHEN** a till with three sales waiting to upload learns that its session ended
- **THEN** it shows that signing in on this device is needed to upload 3 sales, with a way to the sign-in screen, and the three sales remain on the device

#### Scenario: Signing in again
- **WHEN** a user of the branch signs in on that device and opens the till
- **THEN** the waiting sales upload and each is recorded under whoever sold it

#### Scenario: No checkout without a session
- **WHEN** a till that knows its session ended is asked to check out a ticket
- **THEN** it does not check out and shows the same notice
