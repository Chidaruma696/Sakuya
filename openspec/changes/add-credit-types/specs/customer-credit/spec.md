## ADDED Requirements

### Requirement: No credit out of the box
A new installation SHALL give no credit and SHALL declare no credit types until the business saves a credit rule of its own.

#### Scenario: Selling on account with no rule saved
- **WHEN** a cashier without `customers.force_credit` checks out a sale with an amount on a customer's account and no credit rule has been saved
- **THEN** the sale is not recorded, the cashier sees that the business does not sell on account, and the attempt is left in Review under the cashier's name

#### Scenario: Customer form with no types declared
- **WHEN** a customer is created or edited and the credit rule declares no types
- **THEN** the form offers no credit type to choose

### Requirement: Credit types are declared in the credit rule
The credit rule SHALL accept top-level declarations of credit types, each with a key, a display name and a body that ends in a decision. Declared types SHALL be known without running the rule. A rule with no declarations SHALL behave as a single rule for every customer.

#### Scenario: Declared types are offered to customers
- **WHEN** the saved credit rule declares the types `:note-by-note` "Note by note" and `:limit` "Credit limit"
- **THEN** the customer form offers "Note by note", "Credit limit" and "none"

#### Scenario: A rule without declarations decides for everyone
- **WHEN** the saved credit rule has no type declarations and a sale goes on any customer's account
- **THEN** the whole rule decides, whatever credit type the customer carries

#### Scenario: Two types with the same key
- **WHEN** a credit rule that declares the same key twice is saved
- **THEN** it is not saved and the editor says which key is repeated

#### Scenario: A declaration without a name or a body
- **WHEN** a credit rule with a declaration that lacks its display name or its body is saved
- **THEN** it is not saved and the editor says which declaration is incomplete

### Requirement: A customer carries a credit type and a cut-off day
A customer SHALL carry at most one credit type, chosen from the declared ones, and optionally one weekly cut-off day. Both SHALL be editable by whoever can edit customers, without editing the rule.

#### Scenario: Assigning a type
- **WHEN** a customer is saved with the type "Note by note"
- **THEN** the customer list and the customer's account show "Note by note"

#### Scenario: A type that is no longer declared
- **WHEN** a customer carries a type that the saved credit rule no longer declares
- **THEN** the customer keeps it, the customer list flags it as unknown, and the customer gets no credit until it is fixed

#### Scenario: Saving a rule that drops a type in use
- **WHEN** a credit rule is saved that no longer declares a type some customers carry
- **THEN** the editor warns how many customers carry it before saving

### Requirement: The customer's type decides a sale on account
When the credit rule declares types and a sale goes on account, the body of the customer's type SHALL decide. A customer with no type SHALL get no credit.

#### Scenario: The customer's own type decides
- **WHEN** a customer of type `:limit` buys on account and the body of `:limit` allows it
- **THEN** the sale is recorded and the amount is charged to the customer's account

#### Scenario: Customer without a type
- **WHEN** the credit rule declares types and a customer with no type buys on account
- **THEN** the sale is stopped with the reason that the customer has no credit type

#### Scenario: The body of one type fails
- **WHEN** the body of a customer's type raises an error while deciding
- **THEN** the built-in rule decides for that sale, the failure is reported once on the shift, and customers of other types are not affected

### Requirement: Breaking the terms stops the sale and reports it
A sale on account that the credit rule rejects SHALL NOT be recorded for a user without `customers.force_credit`, and the attempt SHALL be left in Review. A user with the permission SHALL go through and the sale SHALL be left for review with the rule's reason.

#### Scenario: Note by note, with a note still unpaid
- **WHEN** a customer of a type that rejects with an unpaid charge from a previous day tries to take a new sale on account, and the cashier does not have `customers.force_credit`
- **THEN** nothing is sold, no stock moves, the cashier sees the customer's name and the reason, and the attempt is in Review marked as stopped

#### Scenario: A supervisor lets it through
- **WHEN** the same sale is checked out by a user with `customers.force_credit`
- **THEN** the sale is recorded, the amount is charged to the account, and the sale is left for review with the rule's reason

#### Scenario: The previous note is paid
- **WHEN** the customer pays what they owe and then takes a new sale on account
- **THEN** the sale is recorded without a review

### Requirement: The credit rule can read the unpaid charges and the cut-off day
The credit rule SHALL be able to read how many charges are unpaid, the age of the oldest one, the customer's cut-off day and the days since a given weekday, besides what it could already read. Payments SHALL settle the oldest charges first.

#### Scenario: Counting unpaid charges
- **WHEN** a customer has charges of 100, 200 and 300 and has paid 250
- **THEN** `(open-charges)` is 2

#### Scenario: Age of the oldest unpaid charge
- **WHEN** a customer's oldest unpaid charge is from three days ago
- **THEN** `(oldest-charge-days)` is 3

#### Scenario: Nothing owed
- **WHEN** a customer owes nothing
- **THEN** `(open-charges)` is 0 and `(oldest-charge-days)` is -1

#### Scenario: Cut-off day
- **WHEN** a customer's cut-off day is Friday and today is Sunday
- **THEN** `(cutoff-day)` is `:friday` and `(days-since :friday)` is 2

#### Scenario: Today is the weekday asked about
- **WHEN** today is Friday
- **THEN** `(days-since :friday)` is 0

#### Scenario: Customer without a cut-off day
- **WHEN** a customer has no cut-off day
- **THEN** `(cutoff-day)` is nothing, and `(or (cutoff-day) :monday)` is `:monday`

### Requirement: Rules written for the earlier contract keep working
A credit rule saved under contract 1 SHALL decide exactly as before and SHALL be flagged in the editor as written for an older contract.

#### Scenario: A version 1 rule after the upgrade
- **WHEN** an installation with a saved contract 1 credit rule is upgraded
- **THEN** sales on account are decided as before, and the editor shows the older-contract notice

#### Scenario: Importing an exported rules file
- **WHEN** a rules file exported before the upgrade is imported
- **THEN** its credit rule is recorded with contract 1 and decides as before

### Requirement: An example with six common types
The editor SHALL offer an example credit rule that declares six types: cash only, note by note, credit limit, weekly, cash paying down and special. The example SHALL NOT be active until it is saved.

#### Scenario: The example is not active
- **WHEN** the editor is opened on a new installation and nothing is saved
- **THEN** nobody gets credit and no type is offered to customers

#### Scenario: Cash only
- **WHEN** the example is saved and a `:cash` customer buys on account
- **THEN** the sale is stopped because the customer is cash only

#### Scenario: Note by note
- **WHEN** the example is saved and a `:note-by-note` customer with an unpaid charge from yesterday buys on account
- **THEN** the sale is stopped because a previous note is unpaid

#### Scenario: Note by note, second note of the day
- **WHEN** the example is saved and a `:note-by-note` customer whose only unpaid charge is from today buys on account again
- **THEN** the sale is allowed

#### Scenario: Credit limit
- **WHEN** the example is saved and a `:limit` customer who owes 800 with a limit of 1,000 buys 300 on account
- **THEN** the sale is stopped because it takes them over their limit

#### Scenario: Weekly, past the cut-off
- **WHEN** the example is saved and a `:weekly` customer with a Friday cut-off has an unpaid charge from Thursday and buys on account on Saturday
- **THEN** the sale is stopped because their cut-off day passed with an unpaid balance

#### Scenario: Weekly, within the week
- **WHEN** the same customer's only unpaid charge is from Saturday and they buy on account on Monday
- **THEN** the sale is allowed

#### Scenario: Cash, paying down
- **WHEN** the example is saved and a `:paying-down` customer who owes money made their last payment eight days ago and buys on account
- **THEN** the sale is stopped because they have not paid in the last seven days

#### Scenario: Special without a cut-off day
- **WHEN** the example is saved and a `:special` customer with no cut-off day and an old unpaid balance buys on account
- **THEN** the sale is allowed

### Requirement: Trying a type before saving
The credit rule editor SHALL let a rule be tried against a real customer, or against a made-up account with a chosen type, unpaid charges, age and cut-off day, without recording anything.

#### Scenario: Trying against a real customer
- **WHEN** a rule is tried with a real customer selected
- **THEN** the result uses that customer's type, account and cut-off day, shows what would happen at the till including the effect of the permission, and nothing is saved

#### Scenario: Trying a made-up case
- **WHEN** a rule is tried with a made-up account of type `:note-by-note` and one unpaid charge from two days ago
- **THEN** the result shows the sale would be stopped and why
