require "test_helper"

class CreditTypesTest < ActiveSupport::TestCase
  # 2026-11-09 is a Monday: the 5th a Thursday, the 6th a Friday, the 7th a Saturday, the 8th a Sunday.
  THURSDAY = Date.new(2026, 11, 5)
  FRIDAY = Date.new(2026, 11, 6)
  SATURDAY = Date.new(2026, 11, 7)
  SUNDAY = Date.new(2026, 11, 8)
  MONDAY = Date.new(2026, 11, 9)

  V1 = <<~LISP.freeze
    (cond ((> (overdue 30) 0) (reject "Owes from more than 30 days ago"))
          ((> (+ (balance) (amount)) (limit)) (reject :over-limit))
          (else (allow)))
  LISP

  setup do
    @store = branches(:store)
    @cashier = users(:cashier)
    @ketchup = products(:ketchup)
    @lupita = Customer.create!(name: "Lupita's Diner", credit_limit: "1000")
  end

  def charge(cents, date, customer: @lupita) = move("charge", cents, date, customer)
  def pay(cents, date, customer: @lupita) = move("account_payment", -cents, date, customer)

  def move(kind, cents, date, customer)
    CreditMovement.create!(customer: customer, branch: @store, user: @cashier, kind: kind, amount_cents: cents, date: date)
  end

  def save_rule(code = CreditRule::EXAMPLE, **options) = Rule.create!(hook: "credit", code: code, user: users(:admin), **options)

  def customer(type, **attributes) = Customer.create!(name: "Customer #{type}", credit_type: type, **attributes)

  def decide(customer, cents = 10_000, **options)
    CreditRule.decide(CreditRule.data(customer, amount: cents, total: cents, authorized: false), **options)
  end

  def on_account(customer, quantity: 1, user: @cashier)
    Till.checkout!(branch: @store, user: user, key: SecureRandom.uuid, customer: customer, lines: [ { product_id: @ketchup.id, quantity: quantity } ],
                   payments: [ { payment_method: "credit", amount_cents: 4_200 * quantity } ])
  end

  test "the account counts the unpaid charges and the age of the oldest, settling the oldest first" do
    assert_equal [ 0, -1 ], [ @lupita.account.open_charge_count, @lupita.account.oldest_charge_days ], "an empty account"
    charge(10_000, 10.days.ago.to_date)
    charge(20_000, 3.days.ago.to_date)
    charge(30_000, Date.current)
    pay(25_000, Date.current)
    assert_equal [ 2, 3 ], [ @lupita.account.open_charge_count, @lupita.account.oldest_charge_days ], "100 paid in full, 200 in part"

    ahead = Customer.create!(name: "Pays ahead")
    charge(10_000, 5.days.ago.to_date, customer: ahead)
    pay(15_000, 4.days.ago.to_date, customer: ahead)
    charge(3_000, 2.days.ago.to_date, customer: ahead)
    assert_equal [ 0, -1 ], [ ahead.account.open_charge_count, ahead.account.oldest_charge_days ], "what was overpaid covers the next charge"
    charge(3_000, 1.day.ago.to_date, customer: ahead)
    assert_equal [ 1, 1 ], [ ahead.account.open_charge_count, ahead.account.oldest_charge_days ]
  end

  test "contract 2 reads the unpaid charges, the cut-off day and the days since a weekday" do
    assert_equal 2, CreditRule::VERSION
    @lupita.update!(cutoff_day: 5)
    travel_to SUNDAY.noon do
      code = '(if (and (= (cutoff-day) :friday) (= (days-since :friday) 2) (= (days-since :sunday) 0) (= (open-charges) 0) (= (oldest-charge-days) -1)) (allow) (reject "no"))'
      assert decide(@lupita, code: code).allows?
      charge(5_000, THURSDAY)
      charge(5_000, SATURDAY)
      assert decide(@lupita, code: '(if (and (= (open-charges) 2) (= (oldest-charge-days) 3)) (allow) (reject "no"))').allows?
      nobody = Customer.create!(name: "No cut-off")
      assert_nil nobody.cutoff_keyword
      assert decide(nobody, code: '(if (= (or (cutoff-day) :monday) :monday) (allow) (reject "no"))').allows?
      failed = decide(@lupita, code: '(if (> (days-since "friday") 1) (allow) (allow))')
      assert failed.rejects?
      assert_match "days-since takes a weekday", failed.error
    end
    assert_not Customer.new(name: "x", cutoff_day: 7).valid?
  end

  test "a rule saved under contract 1 decides as before and is flagged as old; an exported one imports the same" do
    rule = save_rule(V1, version: 1)
    assert rule.old?
    assert decide(@lupita, 90_000).allows?
    assert_match "over their limit", decide(@lupita, 110_000).reason
    @lupita.update_column(:credit_type, "anything")
    assert decide(@lupita, 90_000).allows?, "without declarations the whole rule decides, whatever the customer carries"

    Rule.delete_all
    assert_equal [ "credit" ], RulesFile.import!(";;; hook: credit (contract 1)\n#{V1}", user: users(:admin))
    assert_equal [ 1, true ], [ Rule.current("credit").version, Rule.current("credit").old? ]
    assert_match "over their limit", decide(@lupita, 110_000).reason
  end

  test "types are read from the rule without running it; a repeated or incomplete declaration is an error" do
    assert_equal({}, CreditRule.types, "out of the box no type exists")
    assert_equal %w[cash note-by-note limit weekly paying-down special], CreditRule.types(CreditRule::EXAMPLE).keys
    assert_equal "Note by note", CreditRule.types(CreditRule::EXAMPLE)["note-by-note"]
    assert_equal({ "a" => "A" }, CreditRule.types('(credit-type :a "A" (this-function-does-not-exist))'), "reading does not run the body")
    assert_match "credit type :a is declared twice", assert_raises(Lisp::Error) { CreditRule.read('(credit-type :a "A" (allow)) (credit-type :a "B" (allow))') }.message
    [ "(credit-type :a (allow))", '(credit-type :a "A")', '(credit-type "a" "A" (allow))', '(credit-type :a "" (allow))' ].each do |code|
      assert_match "needs a key, a name and a rule", assert_raises(Lisp::Error) { CreditRule.read(code) }.message
    end
    assert_equal({}, CreditRule.types("(credit-type :a"), "a rule that cannot be read declares none")
  end

  test "with types declared the customer's own decides; without a type, or with an undeclared one, there is no credit" do
    save_rule('(define (ok) (allow)) (credit-type :open "Open" (ok)) (credit-type :closed "Closed" (reject "closed"))')
    assert decide(customer("open")).allows?, "the shared forms run before the body"
    assert_equal "closed", decide(customer("closed")).reason
    none = decide(@lupita)
    assert_equal [ true, "this customer has no credit type", nil ], [ none.rejects?, none.reason, none.error ]

    gone = customer("open")
    save_rule('(credit-type :closed "Closed" (reject "closed"))')
    assert_equal "this customer has no credit type", decide(gone).reason
    assert gone.update(phone: "555"), "a type the rule stopped declaring stays on the customer"
    assert_not gone.update(credit_type: "invented"), "but an undeclared one cannot be chosen"
    assert gone.update(credit_type: ""), "and it can be taken away"
    assert_nil gone.reload.credit_type
  end

  test "a type whose body fails falls to the built-in rule for its own customers only" do
    save_rule('(credit-type :broken "Broken" (this-function-does-not-exist)) (credit-type :fine "Fine" (allow))')
    broken = decide(customer("broken"))
    assert_equal [ true, "this business does not sell on account" ], [ broken.rejects?, broken.reason ]
    assert_match "this-function-does-not-exist", broken.error
    assert decide(customer("fine")).allows?
  end

  test "saving a rule that stops declaring a type in use warns how many customers carry it" do
    save_rule
    customer("weekly")
    customer("weekly").update!(name: "Another weekly")
    customer("cash")
    assert_nil CreditRule.warning(CreditRule::EXAMPLE)
    assert_match(/2 customers have a credit type this rule does not declare — :weekly \(2\)/, CreditRule.warning('(credit-type :cash "Cash only" (reject :cash-only))'))
    assert_nil CreditRule.warning("(allow)"), "a rule without types decides for everyone"
  end

  test "the example: cash only, note by note and credit limit" do
    save_rule
    assert_equal "this customer is cash only", decide(customer("cash")).reason

    note = customer("note-by-note")
    assert decide(note).allows?, "owes nothing"
    charge(5_000, Date.current, customer: note)
    assert decide(note).allows?, "the second note of the same day"
    charge(5_000, 1.day.ago.to_date, customer: note)
    assert_equal "they have an unpaid note (owes $100.00)", decide(note).reason
    pay(10_000, Date.current, customer: note)
    assert decide(note).allows?

    limit = customer("limit", credit_limit: "1000")
    charge(80_000, 2.days.ago.to_date, customer: limit)
    assert_match "over their limit (owes $800.00", decide(limit, 30_000).reason
    assert decide(limit, 20_000).allows?
  end

  test "the example: weekly with a cut-off day" do
    save_rule
    weekly = customer("weekly", cutoff_day: 5)
    charge(5_000, THURSDAY, customer: weekly)
    travel_to(THURSDAY.noon) { assert decide(weekly).allows?, "before the cut-off" }
    travel_to(SATURDAY.noon) { assert_equal "their cut-off day passed and they still owe $50.00", decide(weekly).reason }
    pay(5_000, SATURDAY, customer: weekly)
    charge(5_000, SATURDAY, customer: weekly)
    travel_to(MONDAY.noon) { assert decide(weekly).allows?, "bought after the cut-off: it is due next Friday" }
    travel_to((FRIDAY + 7).noon) { assert decide(weekly).rejects? }

    monday = customer("weekly").tap { |c| c.update!(name: "No day: Monday") }
    charge(5_000, SUNDAY, customer: monday)
    travel_to(MONDAY.noon) { assert decide(monday).rejects?, "without a cut-off day the example uses Monday" }
  end

  test "the example: cash paying down, and special" do
    save_rule
    paying = customer("paying-down")
    assert decide(paying).allows?, "owes nothing"
    charge(50_000, 20.days.ago.to_date, customer: paying)
    assert_equal "they have not made a payment lately (owes $500.00)", decide(paying).reason, "never paid: counts from the oldest charge"
    pay(10_000, 8.days.ago.to_date, customer: paying)
    assert decide(paying).rejects?, "the last payment was eight days ago"
    pay(10_000, 3.days.ago.to_date, customer: paying)
    assert decide(paying).allows?

    special = customer("special")
    charge(50_000, 60.days.ago.to_date, customer: special)
    assert decide(special).allows?, "no cut-off day, no lock"
    special.update!(cutoff_day: Date.current.wday)
    assert_match "cut-off day passed", decide(special).reason
  end

  test "at the till: breaking the terms stops the sale and reports it, a supervisor forces it, and paying clears it" do
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 20, user: @cashier)
    save_rule
    note = customer("note-by-note")
    charge(4_200, 1.day.ago.to_date, customer: note)
    movements = Movement.count

    stopped = assert_raises(Till::Stopped) { on_account(note) }
    assert_match "they have an unpaid note", stopped.message
    assert_equal [ 0, movements, 4_200 ], [ Sale.count, Movement.count, note.balance_cents ]
    review = Review.last
    assert_equal [ true, @cashier ], [ review.stopped, review.user ]
    assert_match "On account for Customer note-by-note, $42.00, stopped", review.reason
    assert_match "unpaid note", review.reason

    forced = on_account(note, user: users(:supervisor))
    assert_equal 8_400, note.balance_cents
    assert_equal [ forced, false ], [ Review.last.reviewable, Review.last.stopped ]
    assert_match "unpaid note", Review.last.reason

    pay(8_400, Date.current, customer: note)
    reviews = Review.count
    clean = on_account(note)
    assert_equal [ note, 4_200, reviews ], [ clean.customer, note.balance_cents, Review.count ]

    assert_match "this customer has no credit type", assert_raises(Till::Stopped) { on_account(@lupita) }.message
  end

  test "the REPL lists each customer's credit type and cut-off day" do
    Features.store!(Features::OPTIONAL, check: false)
    save_rule
    customer("weekly", cutoff_day: 5)
    rows = Repl.evaluate("(customers)", branches: [ @store ])
    assert_equal [ :weekly, :friday ], rows.first.values_at(:"credit-type", :"cutoff-day")
    assert_equal [ nil, nil ], rows.last.values_at(:"credit-type", :"cutoff-day")
    assert_equal [ "Customer weekly" ], Repl.evaluate("(pluck :name (where :credit-type :weekly (customers)))", branches: [ @store ])
  end
end
