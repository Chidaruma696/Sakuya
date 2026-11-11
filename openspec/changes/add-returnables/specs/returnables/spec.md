## ADDED Requirements

### Requirement: No returnables out of the box
A new installation SHALL declare no returnable kinds, and the till SHALL ask for none, until the business switches the feature on and saves a returnables rule of its own.

#### Scenario: The feature is off
- **WHEN** the returnables feature is off
- **THEN** the till, the ticket, the customer screens and the settings menu show nothing about returnables

#### Scenario: The feature is on and nothing is declared
- **WHEN** the feature is on, no returnables rule has been saved and a customer is chosen at the till
- **THEN** the till shows no counters and the sale is checked out as before

### Requirement: Returnable kinds are declared in the returnables rule
The returnables rule SHALL accept top-level declarations of kinds, each with a key, a display name, an optional value per piece and a body that ends in a decision. Declared kinds SHALL be known without running the rule.

#### Scenario: Declared kinds are offered at the till
- **WHEN** the saved rule declares `:crate` "Crate" and `:bottle` "Glass bottle" and a customer is chosen at the till
- **THEN** the till shows a leaving counter and a coming back counter for "Crate" and for "Glass bottle"

#### Scenario: Two kinds with the same key
- **WHEN** a rule that declares the same key twice is saved
- **THEN** it is not saved and the editor says which key is repeated

#### Scenario: An incomplete declaration
- **WHEN** a rule with a declaration that lacks its name or its body, or carries an option it does not know, is saved
- **THEN** it is not saved and the editor says which declaration is wrong

### Requirement: Sakuya knows the pieces each customer owes
Every piece that leaves with a customer, comes back, is written off or is entered loose SHALL be recorded in an insert-only ledger, per customer and kind. What a customer owes of a kind SHALL be the sum, and pieces that come back SHALL settle the oldest ones first.

#### Scenario: Pieces leave and come back
- **WHEN** a customer takes 10 crates on Monday, 5 more on Wednesday and brings back 12 on Friday
- **THEN** the customer owes 3 crates and the oldest one still out is from Wednesday

#### Scenario: Shown with the customer
- **WHEN** a customer owes 3 crates and 24 glass bottles
- **THEN** the customer list and the customer's account show both counts by the kinds' names

### Requirement: A returnable product declares what it releases
A product marked as leaving in returnable containers SHALL declare at least one release: the kind, the quantity on a ticket line from which it counts and, optionally, one piece per every how many units. A product SHALL be able to release more than one kind. At the till the pieces leaving SHALL start at what the products on the ticket release, each ticket line counted on its own.

#### Scenario: A returnable product without a release
- **WHEN** a product is marked as returnable and saved with no release
- **THEN** it is not saved and the form says a kind and a quantity are needed

#### Scenario: One piece per weighing
- **WHEN** a product releases a crate from 15 kg and a ticket has one line of 18 kg and another of 22 kg
- **THEN** the till proposes 2 crates leaving

#### Scenario: Below the quantity
- **WHEN** the same product is sold in a line of 10 kg
- **THEN** the till proposes no crate

#### Scenario: A product that releases two kinds
- **WHEN** a product releases a case from 8 pieces, one per every 8, and a bottle from 1 piece, one per every 1, and 16 pieces are sold
- **THEN** the till proposes 2 cases and 16 bottles leaving

#### Scenario: Fewer pieces than a case
- **WHEN** 5 pieces of that product are sold
- **THEN** the till proposes 5 bottles and no case

#### Scenario: A release of a kind that is no longer declared
- **WHEN** a product releases a kind the saved rule no longer declares
- **THEN** the product is flagged and that release counts nothing at the till

#### Scenario: The feature is off
- **WHEN** the returnables feature is off
- **THEN** the product form shows nothing about returnables

### Requirement: Bringing back more than owed is stopped
Pieces coming back beyond what the customer owes of that kind SHALL be stopped with a dialog, at the till and on the customer's account. Only a user with `returnables.in_favor` SHALL be able to accept them; the surplus SHALL then be kept as pieces in the customer's favor, the movement SHALL be left in Review, and the next pieces of that kind that leave SHALL use up the favor first.

#### Scenario: Without the permission
- **WHEN** a customer who owes 3 crates is recorded as bringing back 4 by a user without `returnables.in_favor`
- **THEN** a dialog says the customer owes 3 and 4 were typed, nothing is recorded, and the dialog offers no way through

#### Scenario: With the permission
- **WHEN** the same return is recorded by a user with `returnables.in_favor` who accepts it in the dialog
- **THEN** the customer owes no crates, has 1 in their favor, and the movement is in Review

#### Scenario: The favor is used first
- **WHEN** a customer with 1 crate in their favor takes 3
- **THEN** the customer owes 2 crates and the rule read 2 as owed afterwards

### Requirement: Loose entries need their own permission
A user with `returnables.adjust` SHALL be able to record, on the customer's account and with a note, pieces a customer already holds or pieces in the customer's favor, with no sale behind them. Every such entry SHALL be left in Review. No other permission SHALL allow it.

#### Scenario: Pieces already out
- **WHEN** a user with `returnables.adjust` enters 12 crates out for a customer, with a note
- **THEN** the customer owes 12 crates, dated that day, and the entry is in Review

#### Scenario: Pieces in favor
- **WHEN** a user with `returnables.adjust` enters 2 crates in favor of a customer who owes none
- **THEN** the customer has 2 crates in their favor and the entry is in Review

#### Scenario: Without the permission
- **WHEN** a user with `returnables.receive` but without `returnables.adjust` tries to record a loose entry
- **THEN** it is refused

#### Scenario: Without the note
- **WHEN** a loose entry is recorded with no note
- **THEN** it is refused

### Requirement: The rule of each kind decides whether pieces may leave
When pieces of a kind leave with a sale, the body of that kind SHALL decide, reading the pieces owed, in favor, leaving and coming back, the age of the oldest piece out, the customer's credit type and whether whoever checks out may force it. Pieces coming back SHALL NOT be judged.

#### Scenario: Within the rule
- **WHEN** a kind allows up to 10 pieces out, the customer owes 4 and takes 5
- **THEN** the sale is recorded and the customer owes 9

#### Scenario: Bringing back makes room
- **WHEN** the same kind allows up to 10, the customer owes 10, brings back 6 and takes 6 in the same sale
- **THEN** the sale is recorded and the customer owes 10

#### Scenario: Only coming back
- **WHEN** a customer buys and only brings pieces back
- **THEN** no returnables rule is asked and the pieces are taken off their count

#### Scenario: Reading the credit type
- **WHEN** a kind's body rejects customers whose `(credit-type)` is `:cash` and such a customer takes a piece
- **THEN** the sale is stopped with the body's reason

#### Scenario: A kind's body fails
- **WHEN** the body of a kind raises an error while deciding
- **THEN** pieces of that kind are refused for that sale, the failure is reported once on the shift, and other kinds decide normally

### Requirement: Breaking the rule stops the sale and reports it
A sale with pieces that the returnables rule rejects SHALL NOT be recorded for a user without `returnables.force`, and the attempt SHALL be left in Review. A user with the permission SHALL go through and the sale SHALL be left for review with the rule's reason.

#### Scenario: Too many pieces out
- **WHEN** a kind allows up to 10 pieces out, the customer owes 10 and the cashier, without `returnables.force`, checks out a sale with 2 more leaving
- **THEN** nothing is sold, no stock moves, no pieces are recorded, the cashier sees the kind and the reason, and the attempt is in Review marked as stopped

#### Scenario: A supervisor lets it through
- **WHEN** the same sale is checked out by a user with `returnables.force`
- **THEN** the sale and the pieces are recorded, and the sale is left for review with the rule's reason

#### Scenario: Pieces leaving without a customer
- **WHEN** a sale with pieces leaving is checked out with no customer chosen
- **THEN** it is refused with a message asking for the customer, and nothing is reported

#### Scenario: Offline
- **WHEN** a sale made offline is uploaded
- **THEN** it carries no returnables

### Requirement: Pieces can come back without a sale
A user with `returnables.receive` SHALL be able to record pieces a customer brings back from the customer's account, up to what the customer owes, without a sale and without asking any rule.

#### Scenario: A loose return
- **WHEN** a customer who owes 8 crates brings back 5 and buys nothing
- **THEN** the customer owes 3 and the return shows in their returnables history with who received it

### Requirement: Pieces that will not come back can be written off
A user with `returnables.write_off` SHALL be able to write off pieces a customer owes, with a reason. The pieces SHALL leave the customer's count, the write-off SHALL be left in Review, and if the kind declares a value the pieces SHALL be charged to the customer's account at that value.

#### Scenario: Writing off with a value
- **WHEN** 2 crates of a kind worth 85 are written off for a customer
- **THEN** the customer owes 2 crates fewer, 170 is charged to their account, and the write-off is in Review with that value

#### Scenario: Writing off without a value
- **WHEN** pieces of a kind that declares no value are written off
- **THEN** the pieces leave the count, nothing is charged, and the Review says so

#### Scenario: Without the reason
- **WHEN** a write-off is recorded with no reason
- **THEN** it is refused

### Requirement: The ticket shows the returnables
The ticket of a sale that moved pieces SHALL show, per kind, the pieces that left, the pieces that came back and what the customer owes afterwards.

#### Scenario: A sale with crates
- **WHEN** a customer who owed 4 crates takes 5 and brings back 2
- **THEN** the ticket shows crates: 5 out, 2 back, owes 7

### Requirement: A kind that is no longer declared
Pieces of a kind the saved rule stops declaring SHALL stay in the ledger, SHALL show as not declared, SHALL NOT be able to leave, and SHALL still be able to come back or be written off.

#### Scenario: Saving a rule that drops a kind still out
- **WHEN** a rule is saved that no longer declares a kind of which customers still owe pieces
- **THEN** the editor warns how many pieces and customers before saving

#### Scenario: Returning pieces of a dropped kind
- **WHEN** a customer brings back pieces of a kind that is no longer declared
- **THEN** they are taken off the count

### Requirement: Trying a kind before saving
The returnables rule editor SHALL let a rule be tried against a real customer or a made-up count — kind, pieces owed, leaving, coming back and age of the oldest — without recording anything, and SHALL offer an example that is not active until saved.

#### Scenario: Trying a made-up case
- **WHEN** the example is tried with the kind `:crate`, 9 owed and 2 leaving
- **THEN** the result shows the sale would be stopped and why, and nothing is saved

#### Scenario: The example is not active
- **WHEN** the editor is opened on a new installation and nothing is saved
- **THEN** no kind exists and the till asks for none

### Requirement: The REPL can list the pieces owed
The REPL SHALL offer a read-only query that lists, per customer and kind, the pieces owed and the age of the oldest one.

#### Scenario: Who owes the most crates
- **WHEN** `(sort-by-desc :owed (where :kind :crate (returnables)))` is evaluated
- **THEN** the result lists the customers who owe crates, most first
