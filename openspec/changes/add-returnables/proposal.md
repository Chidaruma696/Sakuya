## Why

Goods often leave in something that has to come back: crates, glass bottles, trays, gas cylinders. Today Sakuya does not know that a customer is holding thirty crates, so nothing stops the thirty-first from leaving and nobody can say who owes what. The till must be able to refuse to release more containers to a customer who has not brought the previous ones back, the same way it now refuses credit to one who breaks the terms of their credit type.

## What Changes

- A business declares its **returnables** in a new rule, in Lisp: a key, a name, optionally what one piece is worth, and the rule that decides whether more pieces may leave. Sakuya ships none.
- A new insert-only ledger records, per customer and per kind, the pieces that left and the pieces that came back. What a customer owes is the sum.
- A product that leaves in returnable containers says so on its own form, and then must say which kind it releases and from what quantity: chicken sold by weight releases a crate on a weighing of 15 kg or more; a soft drink releases one bottle per piece and one case per eight. One product can release more than one kind.
- At the till, with a customer chosen, the pieces leaving are counted from the products on the ticket and the cashier types how many come back. Pieces leaving are judged by the rule of their kind; pieces coming back are accepted up to what the customer owes.
- Bringing back more than owed is stopped with a dialog. Only someone with the new permission `returnables.in_favor` can accept it, and the surplus is kept as pieces in the customer's favor.
- Counts that do not come from a sale (a business that starts with crates already out, pieces in a customer's favor) are loose entries on the customer's account, only for someone with the new permission `returnables.adjust`, and left in Review.
- Breaking the rule stops the sale and reports the attempt, as every other rule does. Someone with the new permission `returnables.force` goes through and is left for review.
- Pieces can also come back without a sale, from the customer's account screen.
- Pieces that will never come back (broken, lost) are written off by someone with `returnables.write_off`: they leave the customer's count and, if the kind declares a value, that value is charged to the customer's account. Every write-off is left in Review.
- The customer list, the customer's account and the ticket show the pieces owed. The REPL can list them.
- The rules editor gets the new hook, with a test case and an example.

Out of the box nothing changes: no kind exists, the till asks for nothing, and the feature is switched off.

## Capabilities

### New Capabilities
- `returnables`: containers that leave with goods and must come back — the kinds declared in Lisp, the pieces a customer owes, what the rule can read, what each product releases, what happens at the till when it refuses, returning pieces, pieces in a customer's favor, loose entries and writing pieces off.

### Modified Capabilities

None. `customer-credit` is not changed: the returnables rule can read the customer's credit type, but credit is still decided by its own rule.

## Impact

- **Feature**: `returnables`, off by default, needs `customers`. Permissions `returnables.view`, `returnables.receive`, `returnables.write_off`, `returnables.force`, `returnables.in_favor`, `returnables.adjust`.
- **Schema**: two new tables, `returnable_movements` and `product_returnables`, and a flag `products.returnable`. `credit_movements.kind` accepts `returnable` (a write-off charged to the account).
- **Code**: new `ReturnableRule` (hook `returnable`, contract 1) and `ReturnableAccount`; `Till.checkout!` takes the pieces and judges them; the product form, the till screen, the ticket, the customer list and account, the rules editor, the REPL.
- **Translations**: en, es and de.
- **Docs**: `docs/decisions.md`, `docs/architecture.md`, both READMEs.
- **Not touched**: prices, stock of goods, credit rules, orders, purchases.
- **Not in this change**: routes and deliveries; a deposit paid per container; the business's own stock of empty containers; containers owed to suppliers; moving returnables offline.
