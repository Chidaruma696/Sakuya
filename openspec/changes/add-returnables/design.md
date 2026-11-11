## Context

`add-credit-types` gave the credit rule declarations: `(credit-type :key "Name" body)` is read without running to know which types exist, and on a sale only the customer's own body decides. The same shape fits containers: a business has a handful of kinds, each with its own tolerance, and the core should not know any of them.

Nothing about containers exists today. A sale has lines of products and payments; a customer has a credit ledger (`credit_movements`, insert-only) read through `CustomerAccount`. `Till.checkout!` already judges the sale and the credit inside one transaction, raises `Stopped` to refuse and report, and collects rule failures to report once per shift.

Sakuya has no payroll and no routes yet. Whoever loses a container here is the customer.

## Goals / Non-Goals

**Goals:**
- A business declares its container kinds and their rule in Lisp; nothing is configured out of the box.
- Sakuya knows, per customer and kind, how many pieces are out and since when.
- The till refuses to release more pieces when the rule says so, with a reason the cashier can read.
- Pieces that will not come back can be written off and charged.

**Non-Goals:**
- Routes, drivers, loading and settling a truck (next change).
- A deposit paid in cash per container and refunded on return.
- The business's own stock of empties per branch.
- Containers the business owes to its suppliers.
- Returnables offline: they depend on the customer's count, like credit.

## Decisions

### 1. Kinds are declared in their own rule

A new hook, `returnable` (`ReturnableRule`, contract 1). Its program is a list of declarations plus shared helpers:

```lisp
(returnable :crate "Crate" :value 85
  (if (> (owed-after) 10) (reject :too-many-out) (allow)))
```

A key, a display name, optional keyword options, and a body that ends in a decision. The only option in contract 1 is `:value`, the money one piece is worth. Declarations are read without running; the body of a kind runs only when pieces of that kind leave.

*Why a new hook and not more forms in the credit rule?* Different question, different versions, different people editing it. A business can use returnables and give no credit at all.

*Why not a catalog table of kinds edited on a screen?* Same reason as credit types: the kind and its policy are one thing, and a second home for rules means a second history and a second export. The standing rule is that policy is written in Lisp.

*Why keyword options instead of positional arguments?* Contract 2 can add options without breaking a saved rule.

### 2. One insert-only ledger

`returnable_movements`: customer, kind (the key), quantity (a signed whole number: positive leaves with the customer, negative comes back or is written off), reason (`out`, `back`, `write_off`, `entry`), date, branch, user, a note, and a polymorphic reference (the sale, or nothing for a loose return or entry). The sum per customer and kind is the count: above zero the customer owes pieces, below zero the customer has pieces in their favor. Nothing is edited or deleted.

`ReturnableAccount` reads it the way `CustomerAccount` reads the credit ledger: pieces owed per kind, pieces in favor, and the age of the oldest piece still out, settling the oldest first. Pieces in favor are used up first by the next pieces that leave, so they never count as out and have no age.

The count only goes below zero through the two doors of decision 10; everywhere else, bringing back more than owed is stopped.

### 3. What the rule reads

| Function | Returns |
|---|---|
| `(owed)` | pieces of this kind the customer owes before this sale; never below zero |
| `(in-favor)` | pieces of this kind the customer has in their favor before this sale |
| `(leaving)` | pieces of this kind leaving with this sale |
| `(returning)` | pieces of this kind coming back with this sale |
| `(owed-after)` | `owed − in-favor + leaving − returning`, never below zero |
| `(oldest-days)` | age in days of the oldest piece still out; `-1` if none |
| `(owed-all)` | pieces of every kind the customer owes before this sale |
| `(credit-type)` | the customer's credit type as a keyword, or nothing |
| `(customer)` | their name |
| `(authorized)` | whether whoever checks out has `returnables.force` |

Answers are the usual `(allow)`, `(to-review reason)`, `(reject reason)`. Known reasons: `:too-many-out`, `:not-returned`, `:no-returnables`.

`(credit-type)` lets a business tie the two together ("cash-only customers take no crates") without the core knowing about it.

### 4. At the till

When the feature is on, kinds are declared and a customer is chosen, the till shows two counters per kind: leaving and coming back. The leaving counter starts at what the products on the ticket release (decision 9); the cashier types what comes back. Checkout sends them with the sale.

- Pieces coming back beyond what the customer owes stop the checkout with a dialog (decision 10).
- Pieces leaving need a customer. Without one the sale is refused with a message, before any rule runs.
- Each kind with pieces leaving is judged by its body. Coming back alone is never judged.
- Any rejection stops the whole sale: nothing is sold, no stock moves, the attempt is reported on the shift with the kind and the reason. With `returnables.force` the sale goes through and is left for review.
- A kind the rule does not declare cannot move. A body that fails falls to the built-in answer for that kind (reject) and the failure is reported once per shift.
- The movements are written in the sale's transaction, referencing the sale.
- An offline sale carries no returnables.

The ticket prints what left, what came back and what the customer now owes of each kind.

### 5. Returning without buying

On the customer's account, someone with `returnables.receive` records pieces that came back, up to what the customer owes of that kind. No rule is asked: coming back is always good news. More than owed is stopped the same way as at the till (decision 10).

### 6. Writing off

On the same screen, someone with `returnables.write_off` records pieces that will not come back, with a reason. They leave the count. If the kind declares a `:value`, pieces × value is charged to the customer's account as a new kind of credit movement, `returnable`; the credit rule is not asked, because this is a debt and not a sale. Every write-off opens a Review with its value.

Without a `:value` only the pieces are written off, and the Review says nothing was charged.

### 7. The built-in rule declares nothing

`DEFAULT` is a comment. With no kinds declared the till shows no counters and the ledger stays empty. `EXAMPLE` declares two kinds and is covered by tests:

```lisp
; Returnable containers. Nothing here is active until you save it.

; Up to ten crates out at a time.
(returnable :crate "Crate" :value 85
  (if (> (owed-after) 10) (reject :too-many-out) (allow)))

; Bottles are swapped one for one; the first two cases (48) are on trust,
; and nothing more leaves while a bottle has been out for over 30 days.
(returnable :bottle "Glass bottle" :value 6
  (cond ((> (oldest-days) 30) (reject :not-returned))
        ((> (owed-after) 48) (reject :too-many-out))
        (else (allow))))
```

### 8. Dropping a kind that is still out

Saving a rule that stops declaring a kind customers still owe warns how many pieces and customers, through the `warning` step the editor already has. The pieces stay in the ledger under their key and show as "not declared"; they can still come back or be written off (without a value). The same warning counts the products that release the dropped kind; those lines stay on the product, flagged, and release nothing until the kind is declared again.

### 9. A returnable product says what it releases

A product can be marked as leaving in returnable containers. A product marked so MUST carry at least one release line; it cannot be saved without one. Each line says:

- **which kind** it releases, chosen from the declared ones;
- **from what quantity** on a ticket line it starts to count;
- optionally **one piece per every how many** units. Left empty, a ticket line that reaches the quantity releases one piece, whatever its size.

A product can carry several lines, because one product can release more than one kind. The two cases this was designed from:

| Product | Line | A ticket line of… | releases |
|---|---|---|---|
| Chicken, by weight | `:crate` from 15 kg | 18 kg | 1 crate |
| Soft drink, by the piece | `:case` from 8, one per every 8 | 8 pieces | 1 case |
| | `:bottle` from 1, one per every 1 | 8 pieces | 8 bottles |

Each ticket line is counted on its own (a weighing is a line), and the till adds the pieces per kind into the leaving counters.

*Why on the product and not in the rule?* Which product leaves in which container is a fact about each product, like a customer's credit type is a fact about each customer: it lives on the product form, edited by whoever edits products. The policy, whether those pieces may leave, stays in Lisp.

*Why a table of lines and not two columns on the product?* The soft drink needs two lines.

New table `product_returnables` (product, kind, from quantity, per quantity) and a flag `products.returnable`. With the feature off the product form shows none of it.

### 10. More than owed, and loose entries

Two things can leave a count that did not come from a sale or a plain return. Each has its own permission and both are left in Review.

**Bringing back more than owed.** At the till and on the customer's account, a return above what the customer owes of that kind is stopped with a dialog that says how many they owe and how many were typed. Most of the time it is a typing mistake, so the stop itself is not reported. Only a user with `returnables.in_favor` gets, in that same dialog, the choice to accept it: the surplus is kept as pieces in the customer's favor and the movement is left in Review.

**Loose entries.** On the customer's account, a user with `returnables.adjust` records an entry with no sale behind it, with a note: pieces out (the customer already holds them, as when a business starts using this with crates in the street) or pieces in the customer's favor. Every entry is left in Review. Nobody without the permission sees the form.

`returnables.receive` alone therefore never takes a count below zero, and no role gets `returnables.adjust` or `returnables.in_favor` out of the box except the administrator.

## Risks / Trade-offs

- **The till proposes, the cashier still confirms** → the leaving counters come from the products, so forgetting is no longer the usual mistake; what comes back is still typed by hand and nothing can check it against the pavement.
- **A returnable product sold with no customer chosen** → its pieces have nobody to be counted against and the sale is refused asking for the customer. A business that sells such products to walk-in customers will feel this.
- **Offline** → an offline sale carries no returnables, so containers that leave while the till is offline are not counted.
- **Brand and colour multiply the kinds** → a crate that exists in three brands and two colours is six declarations. It is honest and simple, and it may be too many; see the open questions.
- **Charging a write-off skips the credit rule** → a cash-only customer ends up with a balance. That is the point: they owe it.
- **Two tills moving the same customer's pieces at once** → both read the same count. Same unsolved case as credit.
- **The till screen changes** → it only shows the counters with the feature on, kinds declared and a customer chosen, so a business that does not use this sees nothing new.

## Migration Plan

1. One migration: the two new tables, `products.returnable` and the wider check on `credit_movements.kind`.
2. Deploy. The feature is off; nothing is visible.
3. Rollback is reverting the code; the tables can stay.

## Answered by the owner (2026-11-11)

- **Pieces from products**: yes, and declaring them is mandatory for a returnable product: which kind and from what quantity (decision 9).
- **Opening counts**: loose entries, only with their own permission, of pieces out or of pieces in the customer's favor (decision 10).
- **Returning more than owed**: stopped with a dialog; only a specific permission lets it in as pieces in favor (decision 10).

Confirmed the same day, with the go-ahead to apply:

- **Brand and colour**: one kind per combination; a red crate and a blue crate are two declarations with two counts.
- **How a product's pieces are counted**: a 30 kg weighing of a "from 15 kg" product releases one crate (one per weighing, not one per 15 kg) and 10 kg releases none; 5 soft drinks release 5 bottles and no case, 16 release 16 bottles and 2 cases.
- **Write-offs**: charged to the customer's account at the declared value.
- **Correcting the counter**: the cashier may lower what the till proposes as leaving, and a sale that releases fewer pieces than its products call for is left for review.

## Open Questions

None.
