# Decisions

Why Sakuya is the way it is. Newest first.

## The code is in English (3 Oct 2026)

Models, columns, routes, locale keys, comments and tests are all in English; only the translations (`config/locales/es.yml`, `de.yml`) are in other languages. Sakuya started with its models and keys in Spanish, which kept anyone who doesn't read Spanish out of the code. The switch was made in one go, with a single new migration that creates the English schema: there were no installations with data to carry over.

## Closing the till asks a rule (3 Oct 2026)

The second hook, and the first one that decides something: when a shift is closed, the rule reads the count in money (`(difference)`, `(expected)`, `(limit)`, `(authorized)`…) and answers `(allow)`, `(to-review "reason")` or `(reject "reason")`. The default one uses the cap from Settings › Till. A rejection stops the cashier, but not someone with `till.difference`: for that person it counts as a review. I'm not fully convinced, but a badly written rule must not leave a till impossible to close at eleven at night. If the rule crashes, the default decides and the failure is noted in the shift's review. It is edited in Settings › Advanced options, next to the dashboard, and tested with a made-up case (expected, counted, and whether someone with the permission is closing); since 3 Oct also against the real open shift.

## Every rule knows which contract it was written for (3 Oct 2026)

Every hook carries a contract number (`VERSION` in its module) and every rule stores the one it was written for. If what a hook receives or expects ever changes, the number goes up and old rules are flagged in their editor instead of breaking silently. Restoring or importing a version keeps the number it came with; only saving from the editor stamps today's. There are no automatic rule migrations yet: flagging is the minimum.

## The whole sale is asked too (3 Oct 2026)

Besides the price of each line, the complete sale goes through a rule right before checkout: total, products, payment methods, time and day. By default it stops nothing, because prices already have their rule and a normal sale is not irregular; it is there for whatever each business needs (no alcohol after hours, big sales to review). What it stops is not charged and is reported on the shift; with the new permission `till.force_sale` it is charged and left for review. The same when receiving goods: a rule looks at what arrives, from whom and with which papers (delivery note, invoice); by default it stops nothing, what it stops does not come in and is reported on the supplier, and with `purchases.force_receipt` it comes in for review.

## The till keeps selling offline (3 Oct 2026)

If the network goes down, the till doesn't stop. While online, it stores the branch catalog on the device (IndexedDB) and the service worker stores the till page; offline, the page comes from there, scanned items are looked up in the stored catalog and every sale is queued with its unique key and the time it was made. When the network is back they upload by themselves, one by one (the key prevents duplicates), and the shift screen warns if the device still has sales to upload.

When they upload, the server does not stop them: the goods already left. Whatever a rule would have stopped, stock reserved for orders or the cash limit is recorded anyway and reported in Review as an offline sale, and the sale carries the mark and its real time. What the server simply cannot accept (for instance, there is no stock in the system) stays in the queue with its error, in sight, until it's fixed; it is never lost. Offline there are no sales on account and no orders are charged, because they depend on the customer's account. Browsers only allow service workers over HTTPS or on localhost: on a local network over plain http the queue works while the page stays open, but the till cannot be reloaded without the network.

## Orders reserve stock (3 Oct 2026)

An open order reserves in its branch what it asks for: that stock is not sold at the till nor sent in a stock transfer until the order is charged (its own sale does take it) or cancelled. If what is available is not enough, the order is not saved and says what is missing; it can be saved without reserving, for future orders. Waste and adjustments can touch reserved stock, because they record something that already happened, so the available quantity can go negative and it shows. The inventory shows reserved and available stock, so does `(stock)` in the REPL, and restocking counts the available quantity.

## Restocking by minimums and maximums (3 Oct 2026)

Each branch has minimums and maximums per product (Warehouses › Restock). Whatever is below its minimum is suggested up to its maximum, and "Build transfer" opens the usual stock transfer already filled in: it is reviewed and registered like any other. There is no separate path that moves goods. Stock transfers are still instant (out and in at the same time), so there is no "in transit" to subtract.

## ESC/POS receipts (3 Oct 2026)

The receipt also comes out as ESC/POS bytes, the language of thermal printers, with no driver in between: code page PC850 (accents, ñ, ¿ and ¡; € prints as EUR), the total at double size, the receipt's EAN-13 and the paper cut, at 32 or 48 columns depending on the paper. Each branch picks in Admin › Branches how it prints: with the browser (as before), on a network thermal printer (the server opens its port, almost always 9100, and writes) or on a cable one from Chrome with Web Serial (the first time you pick the port; then the browser remembers it). The `.bin` can always be downloaded. The network one is tested against a fake port; the cable one and a real printer, not tested yet. The logo prints as a 30 mm bitmap and the shift summary also goes to the thermal printer.

## PostgreSQL when many branches are needed (3 Oct 2026)

SQLite is still the default: one file, nothing to administer, and it holds a shop. For many branches hitting it at once, Sakuya runs the same on PostgreSQL by just setting `DATABASE_URL`; not a line of logic had to change, because everything goes through Active Record and the few hand-written queries are plain SQL (locks are `SELECT … FOR UPDATE` and folios an atomic `UPDATE`). To keep it that way, CI runs the whole test suite against both databases. To move an installation that already has data: load the schema into the empty PostgreSQL and `bin/rails "sakuya:copy_database[postgres://…]"` copies table by table in foreign-key order, fixes the sequences and compares the counts; if the target already has data, it touches nothing.

## Plugins in Lisp (3 Oct 2026)

A plugin is a `.lisp` file that only declares: a header `(plugin "id" …)`, functions with the plugin prefix (`(define (fonda/margin …) …)`) that every rule, the dashboard and the REPL can then use, named reports that show up as buttons in the REPL, and translations (`(translation "fr" "Français" ("key" "text") …)`). Installing it reads and checks it, but nothing runs; any other form is rejected, and it arrives switched off. Functions carry a prefix so they don't clash with Sakuya's or another plugin's. The defaults run without plugins: if a plugin breaks something, the business rule fails and the default decides, as with any error.

Translations sit in front of the YAML files (a chained I18n backend of our own): a plugin can bring a whole language or change texts of an existing one, and whatever it doesn't translate falls back to the built-in texts. Keys are checked on install (that they exist, and that they aren't `*_html`, which are rendered unescaped). If the plugin is switched off, whoever had that language goes back to a built-in one.

Pending: a place to download community plugins from. For now they are shared as files.

## A REPL to ask the data (3 Oct 2026)

Settings › Advanced options › REPL evaluates Lisp against live data: queries that return lists of maps (`(sales)`, `(stock)`, `(customers)`, `(cash-counts)`, `(reviews)`…) and tools to filter, sort, group and sum them; a list of maps is shown as a table. It is read-only twice over: the Lisp can only call what it is given, and on top of that every evaluation runs with writes blocked in the database (`while_preventing_writes`), with a step limit and 500 rows. It needs the same permission as editing rules because it shows everything; the head office sees every branch and a store only its own. Nothing is kept except the last questions in the session. Every question goes into an insert-only log (who, from which branch, what, and whether it ran), next to the REPL.

## Customers and credit, with credit in Lisp (3 Oct 2026)

Customers come back as their own feature, switched off by default. Selling on account is one more payment method ("On account", which puts no money in the drawer) and charges the customer's account, an insert-only ledger. Instead of fixed credit types (cash, invoice by invoice, limit, weekly…), the decision is a Lisp hook that reads balance, limit, what is overdue at N days and the days without a payment: by default nobody gets credit, and the example rule is the limit one. What it stops is not charged and is reported; with `customers.force_credit` credit is given and left for review. Returning something sold on account first lowers that sale's debt and only the rest comes out of the drawer. Account payments go into the open till (cash, into the shift's drawer) and the statement shows what is owed by age.

Customer orders are the minimum: what they want and for when. They don't reserve stock or carry a price; they are charged at the till ("Charge at the till" builds the receipt with its customer) and go through the usual rules, and once charged they are delivered and linked to their sale. Orders from a branch to the head office with minimums and maximums are left for later.

## Rules travel in a .lisp file (3 Oct 2026)

Settings › Advanced options › Export and import downloads every current rule in a single text file, each under a header `;;; hook: shift (contract 1)`, and uploads it again. Plain text was chosen over JSON because it can be read and edited by hand, and passed from one business to another like sharing an Emacs init file. On upload, whatever changed is recorded as a new version with the contract version it carries; if a single rule can't be read, none goes in.

## Dry runs against the real thing (3 Oct 2026)

Rules that decide are tested in their editor against real data without touching anything: closing and withdrawals against the branch's open shift, prices by replaying an already charged sale line by line, invoices against one already registered and its receipts, inventory with today's stock. The rolled-back transaction from the original plan wasn't needed, because no rule writes: they only read. The editor shows what would really happen, permission included: if the rule stops someone who has the permission, it shows up as a review.

## The first hook is the dashboard (30 Sep 2026)

The Home dashboard is the first Lisp program: it only reads, so it is the risk-free place to debut the language before putting it in the till. The program ends in `(dashboard …)` with `(tile …)` and `(panel …)`; the default figures (`:sales`, `:tickets`…) can also be read as functions to compute your own, and money arrives as exact decimals. If the saved program crashes, Home shows the default one and a notice to whoever can fix it; never a broken page. It is edited in Settings › Advanced options, the home of everything programmed in Lisp, with a preview and nothing saved until it runs, and each version is recorded in `rules` (insert-only). New permission: `rules.edit`.

## Business rules are written in Lisp (30 Sep 2026)

Every business wants something different at the same points: one sells on credit and another never does, one tolerates a hundred of difference in the till and another not a cent, one lets prices drop by half and another never. Adding each variant as one more setting ends in a screen with a thousand checkboxes; coding it by hand for each customer ends in a thousand branches. The way out is Emacs's or AutoCAD's: a fixed core and a language inside for what changes.

How it will be:

- **A small Lisp written in Ruby, inside the app.** Not full Common Lisp or Scheme: reader, `eval`, `define`, `lambda`, `let`, `if`, `cond`, lists and maps. Money is `BigDecimal`, never floating point.
- **The rule proposes, the core disposes.** A rule reads through narrow functions (`(stock product branch)`, `(total sale)`…) and returns a decision: `(allow)`, `(reject "reason")`, `(to-review "reason")` or a value (a price). The core applies it through its usual paths. No rule writes to the database, so none can bypass `Inventory.move!` or edit a ledger.
- **Sandboxed by construction.** Only the functions Sakuya registers exist: no files, no network, no processes. Every rule runs with a step counter and a recursion limit, because it runs inside a sale's transaction and an infinite loop must not freeze the till. If a rule crashes, the default applies and the failure lands in Review.
- **Hooks with a contract and a version.** Every point where the core asks (closing a sale, a line's price, the shift difference, receiving goods) says what it receives and what it may return, and carries a version. That is what avoids Odoo's problem: you customize, you upgrade, and everything breaks.
- **Rules are data.** They live in an insert-only table with who changed what and when; going back is recording the previous version. They are edited in the app with syntax checking and their own permission, dry-run against a real sale, and exported as one file per business.
- **All in English.** Lisp functions have English names (`allow`, `reject`), like Emacs; what changes language is the interface, not the rule language.
- **Later:** a read-only REPL in the browser to ask live data, and community Lisp plugins, including interface translations to more languages.

Why our own Lisp and not Ruby: foreign Ruby can't be run safely since Ruby 3 removed `$SAFE`; an evaluator of our own only knows what you give it. And why not real Common Lisp as a separate service: two runtimes, a network hop on every rule, and the rules far from the transaction.

## Stricter by default (30 Sep 2026)

Whatever needs a supervisor waits for one by default: the general rule is not "do it with a reason and review later", it is "stop". A business that wants it looser relaxes it with a rule. The default roles already come with just enough: the till sells, opens, withdraws and views the inventory; giving money back is a supervisor's job and receiving goods is the warehouse's. Stop and report: what is irregular doesn't go through and the attempt stays in Review under the name of whoever made it, so nothing is lost even though it didn't happen. Since 3 Oct 2026 closing the till works like that: over the cap, the cashier can't close even with a reason and the attempt is reported; someone with `till.difference` closes, with a reason, and it is also left for review. Since the same day, prices too: going below what applies (the promotion or the catalog) stops a till without the permission and the attempt is reported on the shift; with `till.lower_price` it is charged under that person's name and the line is left for review. The floor from Settings › Till still belongs to the core: not even a rule crosses it. And withdrawals: without `till.withdraw` nothing comes out and the attempt is reported; with the permission, by default, it just goes, because taking cash to the safe is normal and not an irregularity. The same for manual inventory movements (loose inflows, adjustments, waste): without `inventory.adjust` nothing moves and the attempt is reported, attached to the product because there is no shift there. And supplier invoices: the lock in Settings › Purchases comes on by default (it used to be off) and, with the lock, invoicing more than was received is not recorded and the attempt is reported on the supplier; with `purchases.exceed` it is recorded with a reason and left for review. With this nothing is left with the old deferred authorization: everything irregular is stopped and reported, and each business relaxes it with its rule.

## Sakuya starts with only the generic parts (30 Sep 2026)

What any business needs: till, inventory, administration, settings, review, purchases, warehouses and stock counts. Orders and customers with credit come later as features of their own; credit, forbidden by default and allowed by a rule. The schema starts in a single migration.

## Base decisions

- **Rails and SQLite.** A POS that can't charge on day one is useless; Rails with Hotwire gives screens fast. SQLite in IMMEDIATE mode holds a shop; PostgreSQL comes in when several branches hit it at once.
- **A single door to the inventory, and insert-only ledgers.** Correcting means recording, never editing.
- **Folios per branch, with the prefix the business chooses**, or a single running number. The counter goes per document, not per letter.
- **The first administrator is created from the screen**, not from the seeds; while there are no users, everything leads to `/install`.
- **One schema and features that switch off.** The business type chosen at start-up is only a preset.
- **The receipt is designed by looking at the receipt.**
- **Purchases without cost in inventory**: the purchase price only lives in the invoice.
- **Count the drawer by notes and coins**, with a difference cap.
- **Three languages, English by default.** The code is in English as well (since 3 Oct 2026).
- **Apache 2.0.** So it gets used, changed and even sold.
