## Context

Selling on account already goes through a Lisp hook (`CreditRule`, contract 1). The rule reads `(amount)`, `(total)`, `(balance)`, `(limit)`, `(overdue N)`, `(days-since-payment)`, `(customer)` and `(authorized)`, and answers `(allow)`, `(to-review reason)` or `(reject reason)`. The built-in rule is `(reject :no-credit)`. The till stops a rejected sale unless whoever checks out has `customers.force_credit`, and reports it in Review either way.

`docs/decisions.md` chose a Lisp hook *instead of* fixed credit types. That still holds: this change does not add an enum of types to the core. What is missing is a way to say which terms apply to which customer, and enough account facts for the rule to express those terms. `CustomerAccount#open_charges` already works out, first in first out, which charges are still unpaid; the rule just cannot see it.

A customer has `credit_limit_cents` and nothing else about credit.

## Goals / Non-Goals

**Goals:**
- A business defines its own credit types in Lisp and assigns one to each customer on a normal screen.
- The till refuses a sale on account that breaks the customer's terms, with a reason the cashier can read.
- Nothing is configured out of the box, and nothing changes for a business that never touches this.
- Existing rules keep working.

**Non-Goals:**
- Fixed credit types in the core, or a settings screen of checkboxes per type.
- Returnable containers and locking by pieces owed (next change).
- Routes and deliveries (a later change).
- A manual block or one-time unblock per customer. Forcing with the permission already covers "let this one through".
- Selling on account offline.

## Decisions

### 1. Types are declared inside the credit rule

A top-level form declares a type:

```lisp
(credit-type :note-by-note "Note by note"
  (if (> (oldest-charge-days) 0) (reject :open-charge) (allow)))
```

A key, a display name, and a body that ends in a decision. The credit rule program is then a list of declarations plus whatever helpers they share (`define`).

Declarations are *read*, not run, to know which types exist — the same way a plugin file is read on install. When a sale goes on account, the shared forms run first and then only the body of the customer's type.

*Why not a `(credit-type)` function and a `cond` in a plain rule?* The customer form needs the list of types to offer, and a `cond` cannot be listed without running it. A free-text field instead would turn a typo into "no credit" with no warning.

*Why not a table of types edited on a screen, each with its own rule?* That is a second place for rules to live, with its own versions, export and editor. One program in the existing `rules` table keeps one history, one file to export and one editor.

*Why not a new special form in the evaluator?* The evaluator stays generic. `CreditRule` splits the program itself: it is the only place that knows what a credit type is.

### 2. A program without declarations is still a plain rule

If the program has no `credit-type` form it behaves exactly as contract 1: the whole program is the decision, for every customer. This is what keeps saved rules working and lets a business that wants one rule for everyone keep it that simple.

A program with at least one declaration is typed: a customer without a type, or with a type the program no longer declares, is answered by the built-in rule (`reject`), with the reason `:no-credit-type`.

### 3. What a customer carries is data, entered on a screen

`customers.credit_type` (the key, nullable) and `customers.cutoff_day` (a weekday, nullable), next to the limit that is already there. The form offers the declared types by name and "none".

The definition of a type and its policy live in Lisp; which customer has which type, their limit and their cut-off day are day-to-day data that whoever manages customers must be able to change without editing a program.

If a customer's type disappears from the rule, nothing is rewritten: the customer keeps the key, gets no credit, and the customer list flags it so it can be fixed.

### 4. Contract 2: four new readings

| Function | Returns |
|---|---|
| `(open-charges)` | how many charges are still unpaid, after applying payments oldest first |
| `(oldest-charge-days)` | age in days of the oldest unpaid charge; `-1` if nothing is owed |
| `(cutoff-day)` | the customer's cut-off weekday as a keyword (`:monday` … `:sunday`), or nothing |
| `(days-since weekday)` | days since the most recent such weekday; `0` if it is today |

All four come from data the account already has. Nothing is added to the ledger.

Contract 2 only adds; it removes and renames nothing. A version 1 rule runs unchanged and the editor shows the existing "written for an older contract" notice, which is accurate: it predates credit types.

*Why `(days-since weekday)` and `(cutoff-day)` separately instead of one `(days-since-cutoff)`?* A business-wide cut-off day is then a literal in the rule — `(days-since (or (cutoff-day) :friday))` — and needs no setting.

### 5. New reasons the till can show

`:cash-only`, `:open-charge`, `:cutoff-passed`, `:no-payment`, `:no-credit-type`, translated in en, es and de, next to the existing `:no-credit` and `:over-limit`. A rule can still give its own text as a string.

### 6. The six types ship as the editor's example

`CreditRule::EXAMPLE` becomes this program. It is shown in the editor and nothing is active until the business saves it; `DEFAULT` stays `(reject :no-credit)`.

```lisp
; Credit types. Give each customer one in Customers; without one they get no credit.

(define (cutoff-passed? day)          ; an unpaid charge from that day or before
  (>= (oldest-charge-days) (days-since day)))

(define (days-without-paying)         ; never paid: since their oldest unpaid charge
  (if (< (days-since-payment) 0) (oldest-charge-days) (days-since-payment)))

; Never on account.
(credit-type :cash "Cash only"
  (reject :cash-only))

; Pay the previous note to take a new one. Notes from the same day do not
; block each other; use (> (open-charges) 0) to allow strictly one.
(credit-type :note-by-note "Note by note"
  (if (> (oldest-charge-days) 0) (reject :open-charge) (allow)))

; What they owe plus this sale must fit under their limit.
(credit-type :limit "Credit limit"
  (if (> (+ (balance) (amount)) (limit)) (reject :over-limit) (allow)))

; On their cut-off day, everything bought up to that day must be paid.
(credit-type :weekly "Weekly"
  (if (cutoff-passed? (or (cutoff-day) :monday)) (reject :cutoff-passed) (allow)))

; May owe, as long as they paid something in the last 7 days.
(credit-type :paying-down "Cash, paying down"
  (if (and (> (balance) 0) (> (days-without-paying) 7)) (reject :no-payment) (allow)))

; No automatic lock unless they have a cut-off day.
(credit-type :special "Special"
  (if (and (cutoff-day) (cutoff-passed? (cutoff-day))) (reject :cutoff-passed) (allow)))
```

The example is covered by tests, one case per type, so it cannot rot.

### 7. Nothing changes at the till

`Till.judge_credit!` already raises `Stopped` on a rejection without the permission and returns a review reason otherwise. It keeps calling `CreditRule.decide`; the type lookup happens inside. The account row of the customer is already read inside the sale's transaction.

## Risks / Trade-offs

- **A type is deleted or renamed in the rule while customers still carry it** → those customers get no credit (the strict side), the list flags them, and saving the rule warns how many customers use a key that is about to disappear.
- **A broken body in one type** → only customers of that type fall to the built-in rule; the failure is reported once per shift as today. A syntax error anywhere still rejects the whole save, as today.
- **Display names are not translated** → they are the business's own words, like a plugin's name. Acceptable.
- **`(oldest-charge-days)` uses the charge's date, and today is the server's date** → a sale keyed in after midnight counts as the next day. Same behaviour as `(overdue N)` today.
- **Two tills selling to the same customer at once** → both could read the same balance before either charge is written. This exists today for the limit rule; this change does not make it worse, and it does not fix it. Noted as an open question.

## Migration Plan

1. One migration adds the two nullable columns. No data is moved.
2. Deploy. Businesses without a credit rule see no difference. Businesses with a version 1 rule see no difference except the "old contract" notice.
3. Rollback is reverting the code; the columns can stay.

## Open Questions

1. **Note by note, same day.** The example lets a customer take several notes on the same day and blocks only when one from a previous day is unpaid. Should the shipped example be the strict one instead (one open note, ever)?
2. **Limit of zero.** In the example a limit of 0 means no credit. Some businesses read 0 as "no limit". The example can go either way.
3. **Concurrent sales to one customer.** Lock the customer row while the credit rule decides and the charge is written? It is cheap, but it touches the till's transaction and deserves its own change.
4. **Cut-off day on the customer.** One weekday per customer is assumed. Is a day of the month ever needed?
