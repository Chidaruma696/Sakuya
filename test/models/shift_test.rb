require "test_helper"

class ShiftTest < ActiveSupport::TestCase
  setup do
    @shift = shifts(:store_open) # 500.00 float, no sales
  end

  test "denominations come from Settings in cents, largest first and without repeats" do
    assert_equal 100_000, Shift.denominations.first
    assert_equal 50, Shift.denominations.last
    Setting.store!("till.denominations" => "20, 100, 20, 0.50")
    assert_equal [ 10_000, 2_000, 50 ], Shift.denominations
    assert_raises(ArgumentError) { Setting.store!("till.denominations" => "100;50") }
  end

  test "closing by counting bills: the total comes from the breakdown and is saved" do
    @shift.close!(user: users(:cashier), breakdown: { "50000" => "1", "10000" => "0", "999" => "5", "2000" => "2" })
    assert_equal 54_000, @shift.counted_cents, "1 × 500 + 2 × 20; 999 is not a denomination and is ignored"
    assert_equal 4_000, @shift.difference_cents
    assert_equal({ "50000" => 1, "2000" => 2 }, @shift.reload.breakdown)
    assert_equal "1 × $500.00, 2 × $20.00", @shift.breakdown_text
  end

  test "without a breakdown it closes with the typed total and no breakdown is saved" do
    @shift.close!(counted_cents: 49_000, user: users(:cashier), breakdown: {})
    assert_equal(-1_000, @shift.difference_cents)
    assert_nil @shift.reload.breakdown
    assert_equal "", @shift.breakdown_text
  end

  test "the difference limit is 0 by default (no limit)" do
    assert_equal 0, Shift.difference_cap_cents
    Setting.store!("till.difference_cap" => "50")
    assert_equal 5_000, Shift.difference_cap_cents
  end
end
