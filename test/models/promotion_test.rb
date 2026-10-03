require "test_helper"

class PromotionTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    @ketchup = products(:ketchup) # 42.00
  end

  test "picks the cheapest current one for product, branch and quantity" do
    Promotion.create!(name: "Special", product: @ketchup, kind: "price", price_cents: 3_900)
    Promotion.create!(name: "Wholesale", product: @ketchup, kind: "by_quantity", minimum_quantity: 6, price_cents: 3_500)
    Promotion.create!(name: "10 %", product: @ketchup, kind: "percentage", percentage: 10, branch: branches(:head_office))
    Promotion.create!(name: "Expired", product: @ketchup, kind: "price", price_cents: 100, to: Date.yesterday)
    Promotion.create!(name: "Switched off", product: @ketchup, kind: "price", price_cents: 100, active: false)
    assert_equal 3_900, Promotion.best(@ketchup, @store, 1, 4_200).first
    assert_equal 3_500, Promotion.best(@ketchup, @store, 6, 4_200).first
    assert_equal 3_780, Promotion.best(@ketchup, branches(:head_office), 1, 4_200).first
    assert_nil Promotion.best(products(:chicken), @store, 1, 12_900)
    assert_nil Promotion.best(@ketchup, @store, 1, 3_000), "a promotion never raises the price"
  end

  test "validates according to the kind and the date range" do
    assert_not Promotion.new(name: "x", product: @ketchup, kind: "percentage").valid?
    assert_not Promotion.new(name: "x", product: @ketchup, kind: "by_quantity", price_cents: 1).valid?
    assert_not Promotion.new(name: "x", product: @ketchup, kind: "price", price_cents: 1, from: Date.current, to: Date.yesterday).valid?
    assert Promotion.new(name: "x", product: @ketchup, kind: "price", price_cents: 1).valid?
  end
end
