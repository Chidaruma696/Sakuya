require "test_helper"

# What every deciding hook promises, checked the same way for all of them: its built-in rule and
# its example decide, it knows every function it documents, and a rule that breaks never decides
# by itself.
class HooksContractTest < ActiveSupport::TestCase
  HOOKS = RulesController::HOOKS

  setup do
    @branch = branches(:store)
    Inventory.move!(branch: @branch, product: products(:ketchup), kind: "inflow", quantity: 10, user: users(:admin))
  end

  def scenario(mod) = mod.scenario(ActionController::Parameters.new, @branch)

  # One decision, whatever the hook returns for its test case (the price hook may return one per line).
  def decisions(mod, code)
    result = mod.dry_run(code, scenario(mod))
    result.is_a?(Array) ? result.map { |_, decision, _| decision } : [ result ]
  end

  test "every hook with an editor has a contract, and the other way round" do
    assert_equal Rule::HOOKS.sort, (HOOKS.keys + [ "dashboard" ]).sort
    HOOKS.each do |hook, mod|
      assert_equal mod.name, Rule::CONTRACTS.fetch(hook), hook
      assert_kind_of Integer, mod::VERSION, hook
      assert_equal mod::VERSION, Rule.contract(hook)
    end
  end

  test "the built-in rule and the example of every hook read and decide on its test case" do
    HOOKS.each do |hook, mod|
      [ mod::DEFAULT, mod::EXAMPLE ].each do |code|
        decisions(mod, code).each { |decision| assert_includes %i[allow review reject], decision.verdict, "#{hook}: #{code.lines.last}" }
      end
    end
  end

  test "every documented function exists in its hook, and nothing from another hook leaks in" do
    HOOKS.each do |hook, mod|
      names = mod::FUNCTIONS
      assert names.any?, hook
      assert_equal :allow, decisions(mod, "(list #{names.join(" ")}) (allow)").first.verdict, hook
      (HOOKS.values.flat_map { |m| m::FUNCTIONS }.uniq - names).each do |foreign|
        error = assert_raises(Lisp::Error, "#{hook} should not know #{foreign}") { decisions(mod, "#{foreign} (allow)") }
        assert_match "I don’t know “#{foreign}”", error.message
      end
    end
  end

  test "every keyword reason a hook knows is translated in every language, and unknown ones are refused" do
    HOOKS.each do |hook, mod|
      mod::REASONS.each do |reason|
        I18n.available_locales.each do |locale|
          text = I18n.with_locale(locale) { decisions(mod, "(reject :#{reason})").first.reason }
          assert text.present? && !text.include?("translation missing") && !text.include?("%{"), "#{hook} :#{reason} in #{locale}: #{text}"
        end
      end
      assert_match "reason", assert_raises(Lisp::Error, hook) { decisions(mod, "(reject :made-up-reason)") }.message
      assert_raises(Lisp::Error, hook) { decisions(mod, %((reject ""))) }
      assert_raises(Lisp::Error, hook) { decisions(mod, "(reject 5)") }
    end
  end

  test "a rule that does not end in a decision is an error in the editor, never a silent allow" do
    HOOKS.each do |hook, mod|
      [ "42", %("allow"), "(list 1 2)", "nil", "(define x 1)" ].each do |code|
        assert_match "the rule must end in (allow)", assert_raises(Lisp::Error, "#{hook}: #{code}") { decisions(mod, code) }.message
      end
      assert_raises(Lisp::ReadError, hook) { decisions(mod, "(allow") }
    end
  end

  test "when the business's rule breaks, the built-in one decides and carries the error" do
    broken = [ "(no-such-function)", "(allow", "42", "(define (f) (f)) (f)", "(take -1 (list 1))" ]
    samples = {
      ShiftRule => ->(code) { ShiftRule.decide(shifts(:store_open), counted_cents: 50_000, user: users(:cashier), code: code) },
      WithdrawalRule => ->(code) { WithdrawalRule.decide(shifts(:store_open), amount_cents: 1_000, reason: "x", user: users(:supervisor), code: code) },
      MovementRule => ->(code) { MovementRule.decide(branch: @branch, product: products(:ketchup), kind: "waste", quantity: 1, reason: "x", user: users(:supervisor), code: code) },
      PriceRule => ->(code) { PriceRule.decide(PriceRule::Input.new(product: products(:ketchup), quantity: 1, price: 4_200, catalog: 4_200, regular: 4_200, authorized: false), code: code) },
      SaleRule => ->(code) { SaleRule.decide(SaleRule.data([], [], total: 0, change: 0, authorized: false), code: code) },
      ReceiptRule => ->(code) { ReceiptRule.decide(ReceiptRule.data(branch: @branch, supplier: Supplier.new(name: "S"), lines: [], delivery_note: "", invoiced: false, authorized: false), code: code) },
      InvoiceRule => ->(code) { InvoiceRule.decide(InvoiceRule::Input.new(excess_items: 0, excess_value: 0, total: 100, receipts: 0, supplier: "S", lock: true, authorized: false, detail: ""), code: code) },
      CreditRule => ->(code) { CreditRule.decide(CreditRule.data(Customer.create!(name: "Ana"), amount: 100, total: 100, authorized: false), code: code) }
    }
    assert_equal HOOKS.values.sort_by(&:name), samples.keys.sort_by(&:name), "a new hook needs its sample here"
    samples.each do |mod, decide|
      built_in = decide.(nil)
      assert_nil built_in.error, mod.name
      broken.each do |code|
        decision = decide.(code)
        assert_equal built_in.verdict, decision.verdict, "#{mod}: #{code}"
        assert decision.error.present?, "#{mod}: #{code}"
      end
    end
  end

  test "the rules file carries every hook's rule out and back in unchanged" do
    HOOKS.each { |hook, mod| Rule.create!(hook: hook, code: mod::EXAMPLE, user: users(:admin)) }
    file = RulesFile.export(business: "Test")
    Rule.delete_all
    assert_equal HOOKS.keys.sort, RulesFile.import!(file, user: users(:admin)).sort
    HOOKS.each { |hook, mod| assert_equal mod::EXAMPLE.strip, Rule.current(hook).code, hook }
    assert_equal [], RulesFile.import!(file, user: users(:admin)), "importing the same again records nothing"
  end
end
