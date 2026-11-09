## Why

A wholesaler does not give every customer the same credit. One pays note by note, another has a limit, another settles every week on a fixed day. Today Sakuya has a single credit rule that sees a balance and a limit, and a customer has nothing that says which kind of credit they have, so one business-wide rule has to guess. The till must be able to refuse to release goods to a customer who breaks the terms of their own kind of credit, and say why.

## What Changes

- A business declares its **credit types** in the credit rule, in Lisp: a key, a name and the rule that decides for customers of that type. Sakuya ships none.
- A customer can be given one of the declared types, and optionally a weekly cut-off day, from the customer screen.
- When a sale goes on account, the rule of the customer's type decides. A customer with no type gets no credit.
- The credit rule can read more about the account: how many charges are still unpaid, how old the oldest one is, the customer's cut-off day and how long ago a given weekday was. This raises the credit contract to version 2; rules written for version 1 keep working and are flagged as old in the editor.
- Breaking the terms stops the sale and reports the attempt, as every other rule does. Someone with `customers.force_credit` goes through and is left for review. No change to that mechanism.
- The editor's example becomes a set of six common types (cash only, note by note, credit limit, weekly, cash paying down, special), ready to adapt. It is an example: nothing is active until the business saves it.
- The editor's test case lets you try a type against a real customer or a made-up account.

Out of the box nothing changes: nobody gets credit and no type exists.

## Capabilities

### New Capabilities
- `customer-credit`: how selling on account is decided — credit types declared in Lisp, the type and cut-off day a customer carries, what the credit rule can read, and what happens at the till when the terms are broken.

### Modified Capabilities

None. There are no specs yet; this is the first one.

## Impact

- **Schema**: two nullable columns on `customers` (credit type key, cut-off weekday). New migration; existing customers stay without a type.
- **Code**: `CreditRule` (contract 2, declarations, new functions), `CustomerAccount` (open charges), `Customer`, `CustomersController` and its form, the rules editor and its credit test case, the REPL's `(customers)`.
- **Translations**: new reasons and labels in en, es and de.
- **Docs**: `docs/decisions.md`, `docs/architecture.md`, both READMEs.
- **Existing installations**: a saved version 1 credit rule behaves exactly as before and shows the "old contract" notice. Exported rule files import unchanged.
- **Not touched**: the till's checkout flow, the customer ledger, account payments, orders, offline selling (still no sales on account offline).
- **Not in this change**: returnable containers and their lock by pieces, routes, a manual block on a customer, customer cards.
