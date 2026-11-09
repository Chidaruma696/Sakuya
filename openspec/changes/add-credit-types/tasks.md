## 1. Account facts

- [x] 1.1 `CustomerAccount#open_charge_count` and `#oldest_charge_days` (−1 when nothing is owed), with model tests for partial payments, overpayment and an empty account
- [x] 1.2 Migration: nullable `customers.credit_type` (string) and `customers.cutoff_day` (integer weekday); `Customer` validates the weekday range and exposes the cut-off day as a keyword

## 2. Contract 2

- [x] 2.1 `CreditRule`: `VERSION = 2`; `Input` and `functions` gain `open-charges`, `oldest-charge-days`, `cutoff-day`, `days-since`; tests for each reading, including today being the weekday asked about and a customer without a cut-off day
- [x] 2.2 New reasons `cash-only`, `open-charge`, `cutoff-passed`, `no-payment`, `no-credit-type` in `REASONS`, translated in en, es and de
- [x] 2.3 Test that a saved contract 1 rule decides as before and is flagged `old?`; test that an exported contract 1 rules file imports and decides as before

## 3. Type declarations

- [x] 3.1 Read `(credit-type :key "Name" body…)` declarations from a program without running it; reject a repeated key, a missing name or a missing body with a translated error
- [x] 3.2 Decide with types: run the shared forms, then only the body of the customer's type; a program without declarations decides whole; no type or an undeclared type falls to the built-in rule with `:no-credit-type`
- [x] 3.3 A failing body falls to the built-in rule for that sale only and carries the error, with a test that another type still decides
- [x] 3.4 Saving the rule validates the declarations and warns how many customers carry a key the new version drops

## 4. Customers

- [x] 4.1 Customer form: credit type select fed by the declared types plus "none", and a cut-off day select; permitted in `CustomersController`
- [x] 4.2 Customer list and account show the type by its declared name and flag a type that is no longer declared
- [x] 4.3 Controller tests reading the real field names from the rendered form

## 5. Till

- [x] 5.1 End-to-end test: a note-by-note customer with an unpaid charge from a previous day is stopped (no sale, no stock movement, a stopped Review with the reason); with `customers.force_credit` the sale is recorded and left for review; after paying, it goes through clean
- [x] 5.2 Test that a customer without a type is stopped with `:no-credit-type` when the rule declares types

## 6. Editor

- [x] 6.1 `CreditRule::EXAMPLE` becomes the six-type program; one test per type against the example, covering the scenarios in the spec
- [x] 6.2 Credit test case: for a made-up account, choose type, number of unpaid charges, age of the oldest and cut-off day; for a real customer, use theirs
- [x] 6.3 Editor help text lists the new functions and the declaration form, in en, es and de

## 7. Around it

- [x] 7.1 REPL `(customers)` includes the credit type and cut-off day
- [x] 7.2 `docs/decisions.md` (new entry), `docs/architecture.md` (hook table and the Customers row), `README.md` and `README.es.md`
- [ ] 7.3 Full suite on SQLite and on PostgreSQL, `bin/rubocop`, `bin/brakeman` — done on SQLite (211 of 212; the one failure is `DatabaseCopyTest` on a checkout path with a space, unrelated), rubocop and brakeman clean; PostgreSQL not run locally, left to CI
