# Top-level architecture

Sakuya is a single system and a single database, split into **features**. A feature is a self-contained set: its tables, its rules, its permissions and its tab on the ribbon. It is switched on or off per business (the business type chosen at start-up is only a preset; afterwards Settings › Features rules). Switched off, it disappears from the ribbon, from the roles and from its screens; its data stays, and it can't be switched off with work still open. Nothing new goes "inside" an existing feature: if it is something else, it is another feature.

## Core (always on)

| Set | What it is | Own tables | Permissions | Tab |
|---|---|---|---|---|
| **Till** | Selling, receipt (browser or ESC/POS thermal printer over the network or a cable, per branch), drawer, shifts, withdrawals, refunds; offline it sells with the device's catalog and queues (`offline.js`, service worker). | sales, sale_lines, payments, shifts, withdrawals, refunds, refund_lines | `till.*` | Till |
| **Inventory** | Stock per branch and product, kardex, manual inflows and adjustments. It is the only door to move stock (`Inventory.move!`). | stock_levels, movements | `inventory.*` | Inventory |
| **Administration** | Catalogs and people: products, barcodes, promotions, branch prices, users, roles, branches. | products, product_barcodes, promotions, branch_prices, users, user_sessions, roles, branches | `admin.*` | Admin |
| **Settings** | Each person's preferences (language, theme, density, text size) and the business's (receipt, currency, folios, till, purchases, features). Admin creates, Settings configures. Its advanced options hold everything programmed in Lisp. | settings | `admin.users` for the system part; `rules.edit` for the advanced part | Home › Settings |
| **Review** | What a rule stopped (the attempt, marked as stopped) and what went through with a permission but needs a look; the supervisor approves or flags it and can charge it to someone. | reviews, charges | `reviews.*` | Home |

## Features

| Feature | What it is | Own tables | Permissions | Tab |
|---|---|---|---|---|
| **Purchases** | Suppliers, goods receipt (an inflow with supplier and delivery note), supplier invoice with lines, accounts payable, payment from the drawer. No cost in inventory. | suppliers, receipts, receipt_lines, supplier_invoices, supplier_invoice_lines, supplier_movements, supplier_payments | `purchases.*` | Purchases |
| **Warehouses** | *Warehouse* branches (storage only: no till and no counts), stock transfers between branches and restocking by minimums and maximums (it builds the transfer). | stock_transfers, stock_transfer_lines, minimums (and the `warehouse` kind in branches) | `warehouses.*` | Warehouses |
| **Stock counts** | Physical counts: pieces are scanned and fractional quantities are typed; the shortage is charged to the person responsible. | stock_counts, stock_count_lines | `stock_counts.*` | Stock counts |
| **Customers** (off by default) | Customers with a credit type (declared in the credit rule) and a weekly cut-off day, selling on account (the "On account" payment method), customer account with ageing, account payments into the till, orders that reserve stock and are charged at the till. | customers, credit_movements, account_payments, orders, order_lines | `customers.*` | Customers |
| **Returnables** (off by default, needs Customers) | Containers that leave with the goods and must come back: the kinds are declared in the returnables rule, each returnable product says what it releases, the till counts what leaves and what comes back per customer, and from the customer's account pieces are received, written off (charged at the declared value) or entered loose. | returnable_movements, product_returnables | `returnables.*` | none of its own: Till, Customers and the product form |

## Cross-cutting rules

- **A single door to the inventory**: everything goes through `Inventory.move!`, which writes the movement and the stock level in the same transaction. No feature touches `stock_levels` directly.
- **Insert-only ledgers** for money and debt (supplier debt, customer accounts, account payments, kardex, the returnable containers each customer holds) and for whatever leaves a trail (rules and their versions, the REPL log): the balance is the sum; nothing is edited or deleted; correcting means recording.
- **Folios per branch** with a prefix per document (B sale, C shift, D refund, RC receipt, TG stock transfer, K stock count, AB account payment, P order), unique per branch.
- **Idempotency** for what the browser captures and might resend (sale, receipt, stock transfer): a key, and the same key returns the same document.
- **Stop and report**: at every sensitive point a rule decides; by default what is irregular doesn't go through and the attempt stays in Review under the name of whoever made it. Someone with the permission is never stuck: for that person, stopping means going through and being left for review.
- **Sessions are rows** (`UserSession`): each user has a limit of live sessions (1 by default, up to 5, set in the user form); signing in beyond it ends the oldest one, and that device is told why. A session nobody uses is asked "are you still there?" and ends by itself, in the browser and on the server; what the till does on its own (`X-Background`) does not count as use. A session never closes a shift: a shift ends when someone counts it. An offline sale stays under whoever sold it, and `sales.uploaded_by` keeps who sent it when it was someone else.
- **Reserved stock**: an open order reserves stock; selling and transferring respect it (`Reservations.check!`), waste and adjustments don't.
- **Two databases**: SQLite by default, PostgreSQL with `DATABASE_URL`; no SQL specific to just one, and CI tests both.
- **Branch kinds**: head office (where everything comes from), store (sells), warehouse (storage only). Rules derive from the kind, never from a separate flag.
- **Full i18n** (English by default, Spanish, German): every visible text goes through `t(...)`, including notices, errors and JS. In tests a missing translation is a failure. A plugin can bring another language or change texts (a chained backend of our own, in front of the YAML files).
- **English code**: identifiers, comments, docs and tests are in English; only the locale files carry other languages.

## Rules in Lisp

The core asks at fixed points (**hooks**) and a rule written in Sakuya's Lisp (`lib/lisp*.rb`) answers. The rule proposes, the core disposes: it reads through narrow functions and returns a decision; it never writes to the database. Details in `decisions.md`.

| Hook | Module | Question | Default |
|---|---|---|---|
| dashboard | `Dashboard` | which figures and lists show on Home | the usual ones |
| price | `PriceRule` | every line being charged | below what applies, stops |
| sale | `SaleRule` | the whole sale before checkout | lets it through |
| credit | `CreditRule` | what goes on a customer's account; it can declare credit types and then the customer's own decides | stops (no credit, no types) |
| returnable | `ReturnableRule` | the containers of a kind leaving with a customer; it declares the kinds, and each kind's own rule decides | no kinds: nothing to count, nothing leaves |
| shift | `ShiftRule` | the difference when closing | over the cap, stops |
| withdrawal | `WithdrawalRule` | taking cash out of the drawer | without permission, stops |
| movement | `MovementRule` | loose inflows, adjustments and waste | without permission, stops |
| receipt | `ReceiptRule` | goods arriving from the supplier | lets it through |
| invoice | `InvoiceRule` | invoicing more than was received | with the lock, stops |

What the deciding hooks share lives in `Hook`; each one carries its contract `VERSION` and every rule stores its own (`Rule::CONTRACTS`). Everything is edited in Settings › Advanced options (a shared editor in `RulesController`, with a dry run against real data), exported and imported as a `.lisp` file (`RulesFile`), and the read-only REPL (`Repl`, with its log) and the plugins (`Plugin`: prefixed functions, reports and translations; the defaults run without them) live there too.

## How to add a feature

1. A key in `Features::OPTIONAL` (and in `DEPENDS` if it hangs from another one, in `ANY` if one of several is enough, in `BUSINESS_TYPES` where it starts switched on, in `check_switchable!` if it can have open work).
2. Its permissions with their own prefix in `Permission` and the prefix in `Features::PERMISSIONS`; the supervisor role usually gets `prefix.*`.
3. `Setting::DEFAULTS["features.<key>"] = "1"` (or `"0"` if it starts switched off, like customers).
4. Its controllers with `tab :<key>` and `feature :<key>`; its tab in `RibbonHelper::TABS` (a feature that lives inside other screens, like returnables, has no tab and checks `Features.active?` where it shows).
5. Texts `features.<key>.{name,what}`, `ribbon.tabs.<key>`, permissions, in es/en/de.
6. Tests: the flow, and that once switched off it disappears from the ribbon and its screens answer 404.
