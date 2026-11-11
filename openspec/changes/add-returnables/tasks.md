## 1. Feature and ledger

- [x] 1.1 Feature `returnables` (off by default, needs `customers`) with permissions `returnables.view`, `returnables.receive`, `returnables.write_off`, `returnables.force`, `returnables.in_favor`, `returnables.adjust` (the last two for no role but the administrator); tests that it hides with the feature off
- [x] 1.2 Migration: `returnable_movements` (customer, kind, signed quantity, reason, note, date, branch, user, polymorphic reference), `product_returnables` (product, kind, from quantity, per quantity), `products.returnable` and `credit_movements.kind` accepting `returnable`; insert-only ledger model
- [x] 1.3 `ReturnableAccount`: pieces owed and in favor per kind and age of the oldest piece out, settling the oldest first, the favor used up first; model tests
- [x] 1.4 Product form: the returnable flag and its release lines (kind, from, per), at least one line required when flagged, a release of an undeclared kind flagged; counting a ticket line into pieces per kind, with tests for the weighing, the case and the bottles

## 2. The rule

- [x] 2.1 `ReturnableRule` (hook `returnable`, contract 1): read `(returnable :key "Name" [:value n] body…)` without running it; reject a repeated key, a missing name or body and an unknown option with translated errors
- [x] 2.2 Readings `owed`, `in-favor`, `leaving`, `returning`, `owed-after`, `oldest-days`, `owed-all`, `credit-type`, `customer`, `authorized`; reasons `too-many-out`, `not-returned`, `no-returnables` in en, es and de; a test per reading
- [x] 2.3 Decide per kind: shared forms, then the body of the kind; an undeclared kind is refused; a failing body refuses that kind only and carries the error
- [x] 2.4 `EXAMPLE` with the two kinds, covered by tests; `DEFAULT` declares nothing

## 3. Till, on the server

- [x] 3.1 `Till.checkout!` takes `returnables: [{ kind:, out:, back: }]`: needs a customer for pieces leaving, judges each kind leaving, stops and reports on a rejection, goes through for review with `returnables.force`, writes the movements in the sale's transaction; nothing offline
- [x] 3.2 End-to-end tests for the scenarios under "Breaking the rule stops the sale and reports it" and "The rule of each kind decides"
- [x] 3.3 Coming back above what is owed stops the checkout; with `returnables.in_favor` and the acceptance sent, the surplus goes in favor and the sale is left for review; tests for both

## 4. Till, on the screen

- [x] 4.1 Counters per declared kind once a customer is chosen, the leaving one filled from the products on the ticket, sent with the checkout; hidden with the feature off or nothing declared
- [x] 4.2 The "more than owed" dialog, with the way through only for `returnables.in_favor`
- [x] 4.3 The ticket (screen and ESC/POS) prints pieces out, back and owed per kind

## 5. Outside a sale

- [x] 5.1 Customer account: pieces owed per kind, history, and "Receive" for a loose return (`returnables.receive`)
- [x] 5.2 Write-off with a reason (`returnables.write_off`): pieces off the count, the value charged to the account when the kind declares one, a Review either way
- [x] 5.3 Customer list shows the pieces owed and in favor; a kind that is no longer declared is flagged
- [x] 5.4 Loose entry with a note (`returnables.adjust`): pieces out or in favor, a Review either way; "Receive" above what is owed opens the same dialog as the till

## 6. Editor

- [x] 6.1 The rules editor serves the `returnable` hook under Advanced options, only with the feature on; help text lists the readings and the declaration form
- [x] 6.2 Test case: a real customer or a made-up count (kind, owed, leaving, coming back, age of the oldest)
- [x] 6.3 Warning before saving a rule that drops a kind still out or still released by products

## 7. Around it

- [x] 7.1 REPL `(returnables)`; the rules file exports and imports the new hook
- [x] 7.2 `docs/decisions.md`, `docs/architecture.md` (feature row, hook table), `README.md` and `README.es.md`
- [ ] 7.3 Full suite on SQLite and on PostgreSQL, `bin/rubocop`, `bin/brakeman` — SQLite, rubocop and brakeman done locally; PostgreSQL is left to CI (`test_postgres`) on the next push
