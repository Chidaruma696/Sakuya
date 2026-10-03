require "test_helper"

# Deferred authorisation: whatever was done with nobody to authorise it is reviewed at the end of the day.
class ReviewsTest < ActionDispatch::IntegrationTest
  setup do
    @store = branches(:store)
    post login_path, params: { user: "cashier", password: "secret12" }
    post till_open_path, params: { float: "500.00" }
    post till_withdraw_path, params: { amount: "150", reason: "paid the gas man, nobody was around" }
    @review = Review.last
  end

  test "the cashier does not see the inbox; the supervisor sees it on the home page and flags it with a charge" do
    get reviews_path
    assert_response :forbidden
    delete logout_path
    post login_path, params: { user: "supervisor", password: "secret12" }
    get root_path
    assert_select "div", /1.*awaits review/
    get reviews_path
    assert_select "td", /Withdrawal of \$150\.00/
    assert_select "td", /paid the gas man/
    post resolve_review_path(@review), params: { status: "flagged", note: "no receipt", charge: "150" }
    assert_redirected_to reviews_path
    @review.reload
    assert_equal "flagged", @review.status
    assert_equal users(:supervisor), @review.reviewed_by
    charge = @review.charge
    assert_equal users(:cashier), charge.user
    assert_equal @store, charge.branch
    assert_equal 15_000, charge.amount_cents
    assert_match "no receipt", charge.detail
    get charges_path
    assert_select "td", /Cashier/
    assert_select "a", "review"
    get root_path
    assert_select "div", { text: /awaits review/, count: 0 }
  end

  test "approving closes the review without a charge and it cannot be resolved twice" do
    post login_path, params: { user: "supervisor", password: "secret12" }
    post resolve_review_path(@review), params: { status: "approved", note: "ok, they called ahead" }
    assert_equal "approved", @review.reload.status
    assert_nil @review.charge
    post resolve_review_path(@review), params: { status: "flagged", charge: "150" }
    assert_match "the review is already approved", flash[:alert]
    assert_equal 0, Charge.count
  end

  test "waste without the permission is not done and the attempt goes to review, with a link to the kardex" do
    post login_path, params: { user: "cashier", password: "secret12" }
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 4, user: users(:admin))
    post movements_inventory_path, params: { product_id: products(:ketchup).id, kind: "waste", quantity: "2", reason: "they broke" }
    assert_equal "inflow", Movement.last.kind, "the waste was not recorded"
    assert_equal [ products(:ketchup), 8_400, true ], [ Review.last.reviewable, Review.last.value_cents, Review.last.stopped ]
    assert_equal 2, Review.pending.count
    delete logout_path
    post login_path, params: { user: "admin", password: "secret12" }
    get reviews_path(branch_id: "all")
    assert_select "a[href=?]", kardex_inventory_path(product_id: products(:ketchup).id, branch_id: @store.id), /Movement stopped/
  end
end
