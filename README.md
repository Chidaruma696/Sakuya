[🇪🇸 Español](README.es.md)

<div align="center">
  <br/>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/logo/sakuya-logo-w.png">
  <img src="docs/logo/sakuya-logo-b.png" width="140" alt="Sakuya">
</picture>

# Sakuya

**咲 · Point of sale and back office for small businesses that bends with Lisp: the till, stock by branch, purchasing, warehouses and stock counts, with the rules around them written in a small Lisp that lives inside the app. Ruby on Rails.**

<br/>

![Rails 8.1](https://img.shields.io/badge/rails-8.1-cc0000?style=for-the-badge&logo=rubyonrails&logoColor=white)
![Ruby 3.4](https://img.shields.io/badge/ruby-3.4-cc342d?style=for-the-badge&logo=ruby&logoColor=white)
![SQLite](https://img.shields.io/badge/sqlite-single%20server-003b57?style=for-the-badge&logo=sqlite&logoColor=white)
![Lisp](https://img.shields.io/badge/rules-lisp-4659a8?style=for-the-badge)
![Apache 2.0 License](https://img.shields.io/badge/license-Apache_2.0-1c2139?style=for-the-badge)

<br/>

*Money in whole cents · insert-only ledgers · one transaction per operation · strict by default, relaxed by rules*

</div>

---

> [!NOTE]
> Sakuya runs a small business from **one server**, for the head office and its branches. The core is fixed; what each business does differently (who sells on credit, how big a till difference is too big, how low a price can go) is meant to live in rules written in Lisp, the way Emacs lives inside Emacs Lisp. The home dashboard and the rules at the till, in the stock and in purchases already work.

> [!IMPORTANT]
> **Sakuya is experimental software in its early phase.** It may have bugs, and a lot will change between versions. If you want to try it in your business, you are welcome to: do it calmly, back up your database often, and keep your current system until it earns your trust. It is shared as is, without warranty (as the [Apache 2.0 licence](LICENSE) says), and I cannot take responsibility for what happens through its use or for any errors it may have. If you find one, opening an [issue](https://github.com/Chidaruma696/Sakuya/issues) helps a lot.

<br/>

## 🏪 What it is

One system, one database, and **modules that turn on or off per business**. The till, stock, administration, settings and review are always there; the rest is switched in Settings. On the first run, with an empty database, it asks for the business name, the head office, the kind of business and the first administrator, and logs in with them.

| Kind of business | Modules that start on |
|---|---|
| **One shop** | till, stock, purchasing and stock counts. |
| **Several branches** | the above plus warehouses and transfers between branches. |
| **Everything on** | every module. |

| Area | What it does | Rule it enforces |
|---|---|---|
| **Till** | Sell by barcode, PLU or code, split payments, receipts with their own barcode, cash count by denomination, cash drops. | Returns only with the receipt. The till is closed by counting the cash. |
| **Stock** | Stock per branch and product, manual entries and adjustments. | The stock ledger (kardex) is insert-only. An adjustment without permission is stopped and reported. |
| **Administration** | Products, barcodes, prices per branch, promotions, users, roles, branches. | Admin is the catalogue; Settings is how the business works. They are separate screens. |
| **Review** | What a rule stopped, and what went through with permission but needs a look. | Nothing irregular gets lost: a supervisor approves it or flags it, and can charge it to someone. |
| **Purchasing** *(module)* | Suppliers, receiving goods, supplier invoices, accounts payable, paying from the till. | The invoice is the only thing that creates debt. Cash leaves the till by one path. |
| **Warehouses** *(module)* | Storage-only branches and transfers between branches. | A warehouse has no till. A transfer goes out and in within one transaction. |
| **Stock counts** *(module)* | Full or partial counts, scanning pieces by their code; what goes by kilo, litre or metre is typed. | The count rules, and the shortfall is charged to whoever is responsible. |
| **Customers** *(module, off by default)* | Customers, selling on account, payments at the till, account statements and orders charged at the till. | Out of the box nobody gets credit: a rule in Lisp decides. |

Factory roles: administrator, cashier (sell, open the till, cash drops, see stock), warehouse keeper and supervisor. The interface speaks English, Spanish and German.

<br/>

## 🔪 The dashboard, in Lisp

The home dashboard is a program, and the first place where Sakuya bends. Out of the box it is this:

```lisp
(dashboard
  (tile :sales)
  (tile :tickets)
  (tile :average-ticket)
  (panel :top-products))
```

Change the order, drop what you don't look at, or compute your own figures:

```lisp
(define margin (- (sales) (returns)))
(dashboard
  (tile "Margin" margin :money)
  (tile "Per day" (/ (sales) (days)) :money)
  (when (> (returns) 0) (tile :returns))
  (panel :top-products 5))
```

It is edited in **Settings › Advanced options › Dashboard in Lisp**, with a preview that can be filled with sample figures. Nothing is saved until it runs, every version is kept, and if a saved one ever breaks, the factory dashboard shows instead.

<br/>

## ⚖️ Rules that decide

Every sensitive spot asks a rule before doing anything: the price of each line, the whole sale before charging it, closing the session, withdrawals, loose entries, adjustments and waste, what arrives from the supplier and its invoice. The rule answers `(allow)`, `(to-review "reason")` or `(reject "reason")`:

```lisp
; Price: small discounts pass, medium ones go to review, ketchup never goes down
(cond ((= (discount) 0) (allow))
      ((= (product) "CATS") (reject "Ketchup is never discounted"))
      ((<= (discount) 5) (allow))
      (else (to-review "Medium discount")))
```

Out of the box, everything irregular **is stopped and reported**: it does not go through and the attempt lands in Review under the name of whoever tried it. Someone with the permission is never stuck; for them, stopping means going through and to review. Each rule is tested in its editor against the real thing (the open session, a sale already charged, a recorded invoice), keeps the contract version of its hook, and they all travel together in a `.lisp` file to back them up or take them to another business.

The Lisp is Sakuya's own, written in Ruby (`lib/lisp*.rb`): a reader, an evaluator with limits on steps and depth, decimals for money, and functions named in English. A program can only call what the app hands it; it cannot touch files, the network or the database directly.

<br/>

## 🧭 Design

- **The rule proposes, the core disposes.** A rule answers with a decision (`(allow)`, `(reject "reason")`, `(to-review "reason")`) and the core applies it through its usual paths, so no rule can skip the stock ledger or edit a book.
- **Strict by default.** What needs a supervisor waits for one. A business that wants it looser says so in a rule, and that rule is versioned and tested dry against real data before it goes live.
- **Hooks are a contract.** Closing a sale, the price of a line, the till difference, receiving goods: each hook has a version, so updating Sakuya does not break a business's rules.
- **One transaction per operation, money in integer cents, ledgers that are only appended to.** Voiding compensates; nothing is edited in place.

`docs/decisiones.md` has the reasons behind each choice; `docs/arquitectura.md`, the map of modules.

<br/>

## 🗺️ Roadmap

- **A read-only REPL** in the browser, to ask the live data questions.
- **Branch orders to the head office** with minimums and maximums, and customer orders that can hold stock.
- **Plugins in Lisp**, including translations of the interface into other languages.
- Printing to ESC/POS, a till that survives a dropped connection, PostgreSQL for many branches.

<br/>

## 🚀 Run it

```sh
bin/setup        # gems, database, seeds
bin/dev          # http://localhost:3000
```

The seeds only create the base roles; the rest comes from the first run. Tests (124 today): `bin/rails test`.

<br/>

## 📚 Credits and names

Sakuya Izayoi and Touhou Project belong to Team Shanghai Alice (ZUN). The name, and the two crossed knives of the logo, are an unofficial fan tribute with no affiliation, made under their guidelines for derivative works.

<br/>

## 📄 License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
