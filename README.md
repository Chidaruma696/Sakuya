[🇪🇸 Español](README.es.md)

<div align="center">

# 咲夜

**Sakuya** · <sub>*a point of sale and back office you can bend with Lisp*</sub>

*"Time stops until the books balance."*

</div>

<br/>

Sakuya runs a small business from one server: the till, stock by branch, purchasing from suppliers, stock counts and transfers between branches. It is strict by default. Every operation lives in one transaction, money is whole cents, the ledgers are insert-only, and anything that needs a supervisor either waits for one or goes on record for review.

Each business works differently, and Sakuya is meant to bend to that. The core stays fixed; the rules around it (who can sell on credit, how big a till difference is too big, what a price can drop to) will be written in a small Lisp that lives inside the app, the way Emacs lives inside Emacs Lisp. That part is still being built.

Ruby on Rails, SQLite, Hotwire. The interface speaks English, Spanish and German.

<br/>

## What it does today

| Area | What's in it |
|---|---|
| Till | Sell by barcode, PLU or code, split payments, receipts with their own barcode, returns only with the receipt, cash count by denomination, cash drops |
| Stock | Stock per branch and product, insert-only ledger (kardex), manual entries and adjustments that go to review when made without permission |
| Admin | Products, barcodes, prices per branch, promotions, users, roles, branches |
| Review | Anything done without the right permission is done with a reason and waits for a supervisor to approve it or charge it to someone |
| Purchasing | Suppliers, receiving goods, supplier invoices, accounts payable, paying from the till |
| Warehouses | Storage-only branches and transfers between branches |
| Stock counts | Full or partial counts; the count rules and the shortfall is charged to whoever is responsible |

Purchasing, warehouses and stock counts are modules: each business turns on what it needs.

<br/>

## Running it

```sh
bin/setup        # gems, database, seeds
bin/dev          # http://localhost:3000
```

The first time, with an empty database, Sakuya asks for the business name, the head office and the first administrator, then logs in with them. The seeds only create the base roles. Tests: `bin/rails test`.

<br/>

## What's coming

- **The rules in Lisp.** A small Lisp interpreter inside the app. A rule reads what it needs through narrow functions and answers with a decision (`(allow)`, `(reject "reason")`, `(to-review "reason")`, a price); the core applies it through its usual paths, so no rule can skip the stock ledger or edit a book. Rules are versioned, tested dry against real data before they go live, and a rule that fails falls back to the default and lands in review. The hooks (closing a sale, the price of a line, the till difference, receiving goods) are a versioned contract.
- **Stricter defaults, relaxed by rules.** Out of the box, what needs a supervisor waits for one. A business that wants it looser says so in a rule.
- **Customers and credit, and orders**, as modules of their own.
- **Plugins in Lisp**, including translations of the interface into other languages.
- Printing to ESC/POS, a till that survives a dropped connection, PostgreSQL for many branches.

`docs/decisiones.md` has the reasons behind each choice; `docs/arquitectura.md`, the map of modules.

<br/>

## License

Apache 2.0.

Sakuya Izayoi and Touhou Project belong to Team Shanghai Alice (ZUN). The name is an unofficial fan tribute with no affiliation, made under their guidelines for derivative works.
