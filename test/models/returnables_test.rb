require "test_helper"

class ReturnablesTest < ActiveSupport::TestCase
  # A crate up to ten out; a case and a bottle that are always let through.
  RULE = <<~LISP.freeze
    (returnable :crate "Crate" :value 85
      (if (> (owed-after) 10) (reject :too-many-out) (allow)))
    (returnable :case "Case" (allow))
    (returnable :bottle "Glass bottle" :value 6 (allow))
  LISP

  setup do
    Features.store!(Features::OPTIONAL, check: false)
    @store = branches(:store)
    @store.update!(cash_limit_cents: 100_000_000)
    @cashier = users(:cashier)
    @supervisor = users(:supervisor)
    @admin = users(:admin)
    @chicken = products(:chicken)
    @ketchup = products(:ketchup)
    Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: 500, user: @admin)
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 500, user: @admin)
    @lupita = Customer.create!(name: "Lupita's Diner")
    save_rule
  end

  def save_rule(code = RULE) = Rule.create!(hook: "returnable", code: code, user: @admin)

  def sell(customer: @lupita, user: @cashier, lines: [ { product_id: @ketchup.id, quantity: 1 } ], **extra)
    Till.checkout!(branch: @store, user: user, key: SecureRandom.uuid, customer: customer, lines: lines,
                   payments: [ { payment_method: "cash", amount_cents: 10_000_000 } ], **extra)
  end

  def crates(out: 0, back: 0) = [ { kind: "crate", out: out, back: back } ]
  def move(quantity, kind: "crate", customer: @lupita) = Returnables.move!(customer, kind, quantity, quantity.positive? ? "out" : "back", user: @cashier, branch: @store)
  def account(customer = @lupita) = customer.returnable_account

  def release(product, kind, from, per = nil)
    product.returnables.build(kind: kind, from_quantity: from, per_quantity: per)
    product.update!(returnable: true)
  end

  test "the account knows the pieces owed, in favor and the age of the oldest, settling the oldest first" do
    assert_equal [ 0, 0, -1, 0 ], [ account.owed("crate"), account.in_favor("crate"), account.oldest_days("crate"), account.owed_all ]
    travel_to(4.days.ago) { move(10) }
    travel_to(2.days.ago) { move(5) }
    move(-12)
    assert_equal [ 3, 0, 2 ], [ account.owed("crate"), account.in_favor("crate"), account.oldest_days("crate") ], "the twelve settle the ten and two of the five"
    move(24, kind: "bottle")
    assert_equal 27, account.owed_all
    assert_equal({ @lupita.id => { "crate" => 3, "bottle" => 24 } }, ReturnableAccount.all_counts)

    move(-5)
    assert_equal [ 0, 2, -1 ], [ account.owed("crate"), account.in_favor("crate"), account.oldest_days("crate") ], "two in their favor"
    move(3)
    assert_equal [ 1, 0, 0 ], [ account.owed("crate"), account.in_favor("crate"), account.oldest_days("crate") ], "the favor is used up first"
    assert_raises(ActiveRecord::ReadOnlyRecord) { ReturnableMovement.last.update!(quantity: 9) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { ReturnableMovement.last.destroy }
  end

  test "kinds are read from the rule without running it, and a bad declaration is refused by name" do
    assert_equal 1, ReturnableRule::VERSION
    assert_equal({ "crate" => "Crate", "case" => "Case", "bottle" => "Glass bottle" }, ReturnableRule.names)
    assert_equal [ 8_500, nil, 600 ], ReturnableRule.kinds.values.map(&:value_cents)
    assert_equal({}, ReturnableRule.kinds(ReturnableRule::DEFAULT), "out of the box nothing is declared")
    assert_equal %w[crate bottle], ReturnableRule.kinds(ReturnableRule::EXAMPLE).keys
    {
      '(returnable :crate "Crate" (allow)) (returnable :crate "Again" (allow))' => "declared twice",
      '(returnable :crate "Crate")' => "needs a key, a name and a rule",
      "(returnable :crate (allow))" => "needs a key, a name and a rule",
      '(returnable :crate "Crate" :value 85)' => "needs a key, a name and a rule",
      '(returnable :crate "Crate" :deposit 5 (allow))' => "option :deposit",
      '(returnable :crate "Crate" :value "a lot" (allow))' => "what one piece is worth"
    }.each do |code, message|
      assert_match message, assert_raises(Lisp::Error, code) { ReturnableRule.read(code) }.message
      assert_equal({}, ReturnableRule.kinds(code), "a rule that cannot be read declares nothing")
    end
  end

  test "the rule reads the count, and the example decides on a made-up case" do
    move(4)
    move(24, kind: "bottle")
    @lupita.update_column(:credit_type, "weekly")
    reads = '(returnable :crate "Crate" (if (and (= (owed) 4) (= (in-favor) 0) (= (leaving) 3) (= (returning) 2) (= (owed-after) 5) (= (oldest-days) 0) ' \
            '(= (owed-all) 28) (= (credit-type) :weekly) (= (customer) "Lupita\'s Diner") (not (authorized))) (allow) (reject "no")))'
    data = ReturnableRule.data(@lupita, kind: "crate", leaving: 3, returning: 2, authorized: false)
    assert ReturnableRule.decide(data, code: reads).allows?

    made_up = { customer: nil, kind: "crate", owed: 9, leaving: 2, returning: 0, oldest_days: 3, authorized: false }
    stopped = ReturnableRule.dry_run(ReturnableRule::EXAMPLE, made_up)
    assert stopped.rejects?
    assert_match "too many", stopped.reason
    assert ReturnableRule.dry_run(ReturnableRule::EXAMPLE, made_up.merge(leaving: 1)).allows?
    old = ReturnableRule.dry_run(ReturnableRule::EXAMPLE, made_up.merge(kind: "bottle", owed: 5, oldest_days: 31))
    assert_match "has not brought back", old.reason
    assert_equal 0, ReturnableMovement.where(kind: "bottle", quantity: 5).count, "trying records nothing"

    cash_only = '(returnable :crate "Crate" (if (= (credit-type) :cash) (reject "cash customers take no crates") (allow)))'
    @lupita.update_column(:credit_type, "cash")
    assert_equal "cash customers take no crates", ReturnableRule.decide(ReturnableRule.data(@lupita, kind: "crate", leaving: 1, returning: 0, authorized: false), code: cash_only).reason
  end

  test "a returnable product says what it releases, and each ticket line is counted on its own" do
    @chicken.returnable = true
    assert_not @chicken.valid?, "marked as returnable with no release"
    assert_match "must say what it releases", @chicken.errors.full_messages.to_sentence
    release(@chicken, "crate", 15)
    release(@ketchup, "case", 8, 8)
    release(@ketchup, "bottle", 1, 1)
    assert_not @chicken.returnables.build(kind: "barrel", from_quantity: 1).valid?, "a kind the rule does not declare"
    assert_not @chicken.returnables.build(kind: "crate", from_quantity: 20).valid?, "the same kind twice"
    assert_not ProductReturnable.new(product: @ketchup, kind: "crate", from_quantity: 0).valid?
    [ @chicken, @ketchup ].each { |product| product.returnables.reset }

    assert_equal({ "crate" => 2 }, Returnables.released([ [ @chicken, 18 ], [ @chicken, BigDecimal("22.5") ] ]), "one crate per weighing")
    assert_equal({ "crate" => 1 }, Returnables.released([ [ @chicken, 30 ] ]), "thirty kilos in one weighing is one crate")
    assert_equal({}, Returnables.released([ [ @chicken, 10 ] ]), "below the quantity")
    assert_equal({ "case" => 2, "bottle" => 16 }, Returnables.released([ [ @ketchup, 16 ] ]))
    assert_equal({ "bottle" => 5 }, Returnables.released([ [ @ketchup, 5 ] ]), "five pieces: five bottles and no case")

    save_rule('(returnable :crate "Crate" (allow))')
    assert_equal({}, Returnables.released([ [ @ketchup.reload, 16 ] ]), "a release of a kind that is no longer declared counts nothing")
    @ketchup.update!(returnable: false)
    save_rule
    assert_equal({}, Returnables.released([ [ @ketchup, 16 ] ]), "a product no longer marked releases nothing")
  end

  test "within the rule pieces leave; bringing back makes room; only coming back is never judged" do
    sell(returnables: crates(out: 4))
    sell(returnables: crates(out: 5))
    assert_equal 9, account.owed("crate")
    sell(returnables: crates(out: 1))
    sale = sell(returnables: crates(out: 6, back: 6))
    assert_equal 10, account.owed("crate")
    assert_equal [ [ "crate", 6, "out" ], [ "crate", -6, "back" ] ], sale.returnable_movements.order(:id).pluck(:kind, :quantity, :reason)

    save_rule('(returnable :crate "Crate" (reject "never"))')
    sell(returnables: crates(back: 2))
    assert_equal 8, account.owed("crate")
    assert_equal 0, Review.count, "nothing here needed a second look"
  end

  test "breaking the rule stops the sale and reports it; someone with the permission goes through for review" do
    move(10)
    stock = StockLevel.quantity_for(@store, @ketchup)
    stopped = assert_raises(Till::Stopped) { sell(returnables: crates(out: 2)) }
    assert_match "Crate", stopped.message
    assert_match "too many", stopped.message
    assert_equal [ 0, 10, stock ], [ Sale.count, account.owed("crate"), StockLevel.quantity_for(@store, @ketchup) ], "nothing sold, no pieces, no stock moved"
    report = Review.last
    assert report.stopped?
    assert_equal shifts(:store_open), report.reviewable
    assert_match "2 × Crate leaving with Lupita's Diner", report.reason
    assert_equal 17_000, report.value_cents

    sale = sell(user: @supervisor, returnables: crates(out: 2))
    assert_equal 12, account.owed("crate")
    review = Review.last
    assert_equal [ sale, false ], [ review.reviewable, review.stopped? ]
    assert_match "too many", review.reason
  end

  test "pieces need a customer, a declared kind and whole numbers; an offline sale carries none" do
    release(@chicken, "crate", 15)
    weighing = [ { product_id: @chicken.id, quantity: 18 } ]
    assert_match "choose the customer", assert_raises(Till::Error) { sell(customer: nil, returnables: crates(out: 1)) }.message
    assert_match "choose the customer", assert_raises(Till::Error) { sell(customer: nil, lines: weighing) }.message
    assert_match "does not declare :barrel", assert_raises(Till::Error) { sell(returnables: [ { kind: "barrel", out: 1 } ]) }.message
    assert_match "whole numbers", assert_raises(Till::Error) { sell(returnables: [ { kind: "crate", out: "1.5" } ]) }.message
    assert_match "whole numbers", assert_raises(Till::Error) { sell(returnables: [ { kind: "crate", back: "-1" } ]) }.message
    assert_equal [ 0, 0 ], [ Sale.count, Review.count ], "refused with a message, nothing reported"

    offline = sell(customer: nil, lines: weighing, sold_at: 1.hour.ago)
    assert offline.offline?
    assert_equal 0, ReturnableMovement.count
    sell(customer: nil)
    Features.store!(Features::OPTIONAL - %w[returnables], check: false)
    sell(customer: nil, lines: weighing)
    sell(returnables: crates(out: 50))
    assert_equal 0, ReturnableMovement.count, "with the feature off the till counts nothing"
  end

  test "the till counts what the products release; fewer pieces than they call for is left for review" do
    release(@chicken, "crate", 15)
    weighings = [ { product_id: @chicken.id, quantity: 18 }, { product_id: @chicken.id, quantity: 20 } ]
    sell(lines: weighings, returnables: crates(out: 2))
    assert_equal [ 2, 0 ], [ account.owed("crate"), Review.count ]

    sale = sell(lines: weighings, returnables: crates(out: 1))
    assert_equal 3, account.owed("crate")
    assert_equal sale, Review.last.reviewable
    assert_match "Crate: 1 left where the products call for 2", Review.last.reason
    assert_equal 8_500, Review.last.value_cents

    sell(lines: weighings)
    assert_equal 3, account.owed("crate"), "a till that typed nothing lets none out"
    assert_match "0 left where the products call for 2", Review.last.reason
  end

  test "bringing back more than owed is stopped without a report; with the permission it stays in their favor, to review, and is used up first" do
    move(3)
    over = assert_raises(Till::MoreThanOwed) { sell(returnables: crates(back: 4)) }
    assert_equal [ [ { kind: "crate", name: "Crate", owed: 3, back: 4 } ], false ], [ over.over, over.can_accept ]
    assert_match "they owe 3 and 4 are coming back", over.message
    assert_raises(Till::MoreThanOwed) { sell(returnables: crates(back: 4), accept_in_favor: true) }
    assert_raises(Till::MoreThanOwed) { sell(user: @supervisor, returnables: crates(back: 4), accept_in_favor: true) }
    assert assert_raises(Till::MoreThanOwed) { sell(user: @admin, returnables: crates(back: 4)) }.can_accept
    assert_equal [ 0, 0, 3 ], [ Sale.count, Review.count, account.owed("crate") ]

    sale = sell(user: @admin, returnables: crates(back: 4), accept_in_favor: true)
    assert_equal [ 0, 1 ], [ account.owed("crate"), account.in_favor("crate") ]
    assert_equal sale, Review.last.reviewable
    assert_match "1 × Crate more than they owed", Review.last.reason

    reads = '(returnable :crate "Crate" (if (and (= (owed) 0) (= (in-favor) 1) (= (owed-after) 2)) (allow) (reject "no")))'
    save_rule(reads)
    sell(returnables: crates(out: 3))
    assert_equal [ 2, 0 ], [ account.owed("crate"), account.in_favor("crate") ]
  end

  test "a kind whose rule fails is refused, the others decide, and the failure is reported once on the shift" do
    save_rule('(returnable :crate "Crate" (no-such-function)) (returnable :bottle "Glass bottle" (allow))')
    sell(returnables: [ { kind: "bottle", out: 3 } ])
    assert_equal [ 3, 0 ], [ account.owed("bottle"), Review.count ]
    assert_raises(Till::Stopped) { sell(returnables: crates(out: 1)) }
    2.times { sell(user: @supervisor, returnables: crates(out: 1)) }
    failures = Review.where(reviewable: shifts(:store_open), stopped: false)
    assert_equal 1, failures.count
    assert_match "The returnables rule failed", failures.first.reason
  end

  test "pieces come back without a sale, up to what is owed; beyond it only with the permission" do
    move(8)
    movement = Returnables.receive!(customer: @lupita, kind: "crate", quantity: "5", user: @cashier, branch: @store, key: "r1")
    assert_equal [ 3, -5, "back", @cashier ], [ account.owed("crate"), movement.quantity, movement.reason, movement.user ]
    assert_equal movement, Returnables.receive!(customer: @lupita, kind: "crate", quantity: "5", user: @cashier, branch: @store, key: "r1"), "the same form twice"
    assert_equal 3, account.owed("crate")

    over = assert_raises(Returnables::MoreThanOwed) { Returnables.receive!(customer: @lupita, kind: "crate", quantity: 4, user: @cashier, branch: @store) }
    assert_equal [ { kind: "crate", name: "Crate", owed: 3, back: 4 } ], over.over
    assert_raises(Returnables::MoreThanOwed) { Returnables.receive!(customer: @lupita, kind: "crate", quantity: 4, user: @supervisor, branch: @store, accept_in_favor: true) }
    assert_raises(Returnables::MoreThanOwed) { Returnables.receive!(customer: @lupita, kind: "crate", quantity: 4, user: @admin, branch: @store) }
    assert_match "whole numbers", assert_raises(Returnables::Error) { Returnables.receive!(customer: @lupita, kind: "crate", quantity: 0, user: @cashier, branch: @store) }.message
    assert_equal [ 3, 0 ], [ account.owed("crate"), Review.count ]

    accepted = Returnables.receive!(customer: @lupita, kind: "crate", quantity: 4, user: @admin, branch: @store, accept_in_favor: true)
    assert_equal [ 0, 1 ], [ account.owed("crate"), account.in_favor("crate") ]
    assert_equal accepted, Review.last.reviewable
    assert_match "4 × Crate from Lupita's Diner, more than they owed", Review.last.description
  end

  test "pieces that will not come back are written off, charged at the declared value and left for review" do
    move(5)
    move(10, kind: "case")
    assert_match "reason", assert_raises(Returnables::Error) { Returnables.write_off!(customer: @lupita, kind: "crate", quantity: 2, reason: " ", user: @supervisor, branch: @store) }.message
    assert_match "only what they owe", assert_raises(Returnables::Error) { Returnables.write_off!(customer: @lupita, kind: "crate", quantity: 6, reason: "broken", user: @supervisor, branch: @store) }.message

    movement = Returnables.write_off!(customer: @lupita, kind: "crate", quantity: 2, reason: "run over by the truck", user: @supervisor, branch: @store)
    assert_equal [ 3, 17_000 ], [ account.owed("crate"), @lupita.balance_cents ]
    charge = @lupita.credit_movements.last
    assert_equal [ "returnable", 17_000, movement, "2 × Crate written off" ], [ charge.kind, charge.amount_cents, charge.reference, charge.reason ]
    review = Review.last
    assert_equal [ movement, 17_000 ], [ review.reviewable, review.value_cents ]
    assert_match "run over by the truck. $170.00 charged", review.reason
    assert_equal "2 × Crate written off for Lupita's Diner", review.description
    assert_equal 1, @lupita.account.open_charge_count, "it is a debt like any other"

    Returnables.write_off!(customer: @lupita, kind: "case", quantity: 1, reason: "lost", user: @supervisor, branch: @store)
    assert_equal [ 9, 17_000 ], [ account.owed("case"), @lupita.balance_cents ]
    assert_match "Nothing was charged", Review.last.reason
  end

  test "loose entries record pieces already out or in the customer's favor, with a note, and are left for review" do
    assert_match "note", assert_raises(Returnables::Error) { Returnables.enter!(customer: @lupita, kind: "crate", quantity: 12, direction: "out", note: "", user: @admin, branch: @store) }.message
    assert_raises(Returnables::Error) { Returnables.enter!(customer: @lupita, kind: "crate", quantity: 12, direction: "sideways", note: "x", user: @admin, branch: @store) }
    assert_match "does not declare", assert_raises(Returnables::Error) { Returnables.enter!(customer: @lupita, kind: "barrel", quantity: 1, direction: "out", note: "x", user: @admin, branch: @store) }.message

    out = Returnables.enter!(customer: @lupita, kind: "crate", quantity: 12, direction: "out", note: "what they held when we started", user: @admin, branch: @store)
    assert_equal [ 12, 0, "entry" ], [ account.owed("crate"), account.oldest_days("crate"), out.reason ]
    assert_equal out, Review.last.reviewable
    assert_match "already out with Lupita's Diner: what they held", Review.last.reason
    assert_equal 102_000, Review.last.value_cents

    ana = Customer.create!(name: "Ana")
    Returnables.enter!(customer: ana, kind: "bottle", quantity: 2, direction: "in_favor", note: "left two on Friday", user: @admin, branch: @store)
    assert_equal [ 0, 2 ], [ account(ana).owed("bottle"), account(ana).in_favor("bottle") ]
    assert_equal "Loose entry of 2 × Glass bottle for Ana", Review.last.description
  end

  test "a kind the rule stops declaring stays in the count: it can come back or be written off, not leave" do
    move(5)
    release(@chicken, "crate", 15)
    assert_nil ReturnableRule.warning(RULE)
    dropped = '(returnable :bottle "Glass bottle" (allow))'
    assert_match "1 customer still has a count of kinds this rule does not declare — :crate, 5 pieces", ReturnableRule.warning(dropped)
    assert_match "1 product releases a kind this rule does not declare", ReturnableRule.warning(dropped)
    save_rule(dropped)

    assert_match "does not declare :crate", assert_raises(Till::Error) { sell(returnables: crates(out: 1)) }.message
    sell(lines: [ { product_id: @chicken.id, quantity: 18 } ])
    assert_equal 5, account.owed("crate"), "the product's release of the dropped kind counts nothing"
    Returnables.receive!(customer: @lupita, kind: "crate", quantity: 2, user: @cashier, branch: @store)
    Returnables.write_off!(customer: @lupita, kind: "crate", quantity: 1, reason: "broken", user: @supervisor, branch: @store)
    assert_equal [ 2, 0 ], [ account.owed("crate"), @lupita.balance_cents ], "no declared value, nothing charged"
    assert_equal "crate", Returnables.name("crate")
    assert_raises(Returnables::Error) { Returnables.receive!(customer: Customer.create!(name: "Ana"), kind: "crate", quantity: 1, user: @admin, branch: @store, accept_in_favor: true) }
  end

  test "the ticket says what left, what came back and what the customer owes afterwards, on screen and in ESC/POS" do
    move(4)
    sale = sell(returnables: crates(out: 5, back: 2) + [ { kind: "bottle", out: 0, back: 0 } ])
    assert_equal [ [ "Crate", 5, 2, 7 ] ], Returnables.ticket_rows(sale)
    move(3)
    assert_equal [ [ "Crate", 5, 2, 7 ] ], Returnables.ticket_rows(sale), "a reprint still says what they owed then"
    assert_includes EscPos.ticket(sale), "Crate: 5 out, 2 back".b
    assert_equal [], Returnables.ticket_rows(sell(customer: nil))
    assert_equal [], Returnables.ticket_rows(Sale.new)
  end

  test "the REPL lists the pieces each customer owes" do
    move(3)
    ana = Customer.create!(name: "Ana")
    move(7, customer: ana)
    move(-2, kind: "bottle", customer: ana)
    rows = Repl.evaluate("(sort-by-desc :owed (where :kind :crate (returnables)))", branches: [ @store ])
    assert_equal [ [ "Ana", 7 ], [ "Lupita's Diner", 3 ] ], rows.map { |r| [ r[:customer], r[:owed] ] }
    bottles = Repl.evaluate("(where :kind :bottle (returnables))", branches: [ @store ])
    assert_equal [ { customer: "Ana", kind: :bottle, name: "Glass bottle", owed: 0, "in-favor": 2, "oldest-days": -1 } ], bottles
    Features.store!(Features::OPTIONAL - %w[returnables], check: false)
    assert_equal [], Repl.evaluate("(returnables)", branches: [ @store ])
  end
end
