require "test_helper"

class ShiftRuleTest < ActiveSupport::TestCase
  setup do
    @shift = shifts(:store_open) # $500 float and nothing else: $500 expected
  end

  def decide(counted, code = nil, user: users(:cashier))
    ShiftRule.decide(@shift, counted_cents: counted, user: user, code: code)
  end

  test "the default rule stops: with no limit or within the limit it passes, beyond it is rejected even if the supervisor closes" do
    assert decide(10_000).allows?, "with no limit everything passes"
    Setting.store!("till.difference_cap" => "50")
    assert decide(45_000).allows?, "exactly $50 missing"
    d = decide(44_999)
    assert d.rejects?
    assert_equal "the difference (−$50.01) exceeds the limit ($50.00)", d.reason
    assert decide(44_999, user: users(:supervisor)).rejects?, "the permission is checked by the core, not by the rule"
  end

  test "a custom rule reads the count in dollars and decides" do
    code = <<~LISP
      (cond ((> (difference) 0) (to-review "extra money"))
            ((< (difference) -100) (reject "too much missing"))
            (else (allow)))
    LISP
    assert decide(50_000, code).allows?
    assert_equal [ :review, "extra money" ], decide(50_001, code).then { |d| [ d.verdict, d.reason ] }
    assert decide(40_000, code).allows?, "exactly $100 missing"
    assert_equal [ :reject, "too much missing" ], decide(39_999, code).then { |d| [ d.verdict, d.reason ] }
    reads = "(if (and (= (expected) 500) (= (float) 500) (= (counted) 480.50) (= (tickets) 0) (not (authorized))) (allow) (reject \"no\"))"
    assert decide(48_050, reads).allows?, decide(48_050, reads).inspect
  end

  test "if the rule blows up or does not decide, the default one decides and the error travels in the decision" do
    Setting.store!("till.difference_cap" => "50")
    d = decide(40_000, "(allow")
    assert d.rejects?, "the default rule decided"
    assert d.error.present?
    d = decide(50_000, "(+ 1 2)")
    assert d.allows?
    assert_match "it ended in 3", d.error
    assert_match ":over-limit", decide(50_000, "(reject :does-not-exist)").error
    assert decide(50_000, "(define (f) (f)) (f)").error.present?, "endless recursion is cut off"
  end

  test "with no saved rule it uses the default one; with a rule, the current one" do
    assert decide(10_000).allows?
    Rule.create!(hook: "shift", code: "(reject \"never\")", user: users(:admin))
    assert ShiftRule.decide(@shift, counted_cents: 50_000, user: users(:cashier)).rejects?
  end
end
