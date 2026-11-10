require "test_helper"

class MoneyTest < ActiveSupport::TestCase
  test "cents reads what a person types and rounds half up to whole cents" do
    { "129" => 12_900, "129.00" => 12_900, " 0.5 " => 50, "0.005" => 1, "0.004" => 0, "-3.10" => -310, "1e2" => 10_000,
      1 => 100, BigDecimal("2.345") => 235, "" => 0, nil => 0, "  " => 0 }.each do |typed, cents|
      assert_equal cents, Money.cents(typed), typed.inspect
    end
  end

  test "what is not an amount is refused with a message people can read" do
    [ "abc", "12,50", "1,000.00", "$5", "5 pesos", "1.2.3", "NaN", "Infinity", "-Infinity", "1e400", "9" * 15 ].each do |typed|
      error = assert_raises(Money::Invalid, typed) { Money.cents(typed) }
      assert_match "is not an amount", error.message
      assert_no_match(/BigDecimal/, error.message)
    end
    assert_kind_of ArgumentError, Money::Invalid.new, "screens that already rescue ArgumentError keep working"
    I18n.with_locale(:es) { assert_match "“12,50” no es una cantidad", assert_raises(Money::Invalid) { Money.cents("12,50") }.message }
  end

  test "amount multiplies quantity by price without floating point" do
    assert_equal 4_080, Money.amount("2.050", 1_990) # 4079.5: a float would say 4079.4999…
    assert_equal 1_454, Money.amount("0.570", 2_550)
    assert_equal 0, Money.amount("0.001", 49)
    assert_equal 1, Money.amount("0.001", 500)
  end

  test "format_money groups thousands, keeps two decimals and marks negatives" do
    assert_equal "$0.00", Money.format_money(0)
    assert_equal "$0.07", Money.format_money(7)
    assert_equal "$1,000,000.00", Money.format_money(100_000_000)
    assert_equal "−$1,234.56", Money.format_money(-123_456)
    Setting.store!("business.symbol" => "Q")
    assert_equal "Q12.00", Money.format_money(1_200)
  end
end
