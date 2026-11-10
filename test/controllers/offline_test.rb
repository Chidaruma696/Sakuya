require "test_helper"

class OfflineTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { user: "cashier", password: "secret12" }
    @store = branches(:store)
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
  end

  def upload(key, lines, sold_at: 10.minutes.ago, payments: [ { payment_method: "cash", amount_cents: 100_000 } ])
    post till_checkout_path, params: { key: key, lines: lines.to_json, payments: payments.to_json, sold_at: sold_at&.iso8601 }, headers: { "Accept" => "application/json" }
  end

  test "the catalogue brings what the till needs to sell offline" do
    ProductBarcode.create!(product: products(:ketchup), code: "7501234567890")
    get till_catalog_path
    ketchup = response.parsed_body["products"].find { |p| p["key"] == "KETC" }
    assert_equal [ products(:ketchup).id, 4_200 ], ketchup.values_at("product_id", "price_cents")
    assert_includes ketchup["codes"], "7501234567890"
    assert ketchup.key?("plu")
    get till_token_path
    assert response.parsed_body["token"].present?
  end

  test "what is sold offline is recorded even if a rule would have stopped it, and it is reported; the same key does not duplicate" do
    upload("off-1", [ { product_id: products(:ketchup).id, quantity: 1, price_cents: 3_000 } ])
    assert_response :ok
    sale = Sale.find_by!(key: "off-1")
    assert sale.offline
    assert_in_delta 10.minutes.ago, sale.sold_at, 5
    assert_match "Sale made offline that would otherwise have been stopped", Review.last.reason
    assert_equal sale.lines.first, Review.last.reviewable
    upload("off-1", [ { product_id: products(:ketchup).id, quantity: 1, price_cents: 3_000 } ])
    assert_equal 1, Sale.where(key: "off-1").count
  end

  test "offline, held stock is sold and reported; on account is not; and the time has to add up" do
    Features.store!(Features::OPTIONAL, check: false)
    lupita = Customer.create!(name: "Lupita's Diner")
    Order.create!(customer: lupita, branch: @store, user: users(:cashier), lines_attributes: [ { product_id: products(:ketchup).id, quantity: 5 } ])
    upload("off-2", [ { product_id: products(:ketchup).id, quantity: 1 } ])
    assert_response :ok
    assert_match "held for orders", Review.last.reason
    upload("off-3", [ { product_id: products(:ketchup).id, quantity: 1 } ], payments: [ { payment_method: "credit", amount_cents: 4_200 } ])
    assert_match "needs a connection", response.parsed_body["error"]
    upload("off-4", [ { product_id: products(:ketchup).id, quantity: 1 } ], sold_at: 8.days.ago)
    assert_match "does not add up", response.parsed_body["error"]
    upload("off-5", [ { product_id: products(:ketchup).id, quantity: 1 } ], sold_at: 1.day.from_now)
    assert_match "does not add up", response.parsed_body["error"]
  end

  test "an offline sale is recorded under whoever sold it, whoever uploads it; the uploader is kept when it is someone else" do
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 10, user: users(:admin))
    ketchup = [ { product_id: products(:ketchup).id, quantity: 1 } ]
    seller = ->(key) { Sale.find_by!(key: key).then { |s| [ s.user, s.uploaded_by ] } }
    post till_checkout_path, params: { key: "own", lines: ketchup.to_json, payments: [ { payment_method: "cash", amount_cents: 4_200 } ].to_json, sold_at: 5.minutes.ago.iso8601, sold_by: users(:cashier).id }
    assert_equal [ users(:cashier), nil ], seller.("own"), "uploaded by the same cashier: nothing else to say"

    delete logout_path
    post login_path, params: { user: "supervisor", password: "secret12" } # the supervisor signs in on that till
    upload = ->(key, sold_by, **extra) { post till_checkout_path, params: { key: key, lines: [ { product_id: products(:ketchup).id, quantity: 1, **extra } ].to_json, payments: [ { payment_method: "cash", amount_cents: 4_200 } ].to_json, sold_at: 5.minutes.ago.iso8601, sold_by: sold_by } }
    upload.("theirs", users(:cashier).id, price_cents: 3_000)
    assert_response :ok
    assert_equal [ users(:cashier), users(:supervisor) ], seller.("theirs")
    review = Review.last
    assert_equal users(:cashier), review.user, "what it leaves in Review is under the seller's name"
    assert_match "would otherwise have been stopped", review.reason, "and it is judged with the seller's permissions, not the uploader's"
    get till_sales_path
    assert_select "td", /Cashier\s+\(uploaded by Supervisor\)/
    assert_equal "Supervisor", Repl.evaluate('(get (first (where :folio "' + Sale.find_by!(key: "theirs").folio + '" (sales))) :uploaded-by)', branches: [ @store ])

    users(:cashier).update!(active: false)
    upload.("gone", users(:cashier).id)
    assert_equal [ users(:cashier), users(:supervisor) ], seller.("gone"), "a cashier switched off since then still sold it"
    upload.("far", users(:admin).id)
    assert_equal [ users(:supervisor), nil ], seller.("far"), "a seller from another branch is not believed"
    upload.("nobody", "")
    assert_equal [ users(:supervisor), nil ], seller.("nobody"), "a sale queued before this existed belongs to whoever uploads it"
    upload.("unknown", "999999")
    assert_equal [ users(:supervisor), nil ], seller.("unknown")
    post till_checkout_path, params: { key: "online", lines: ketchup.to_json, payments: [ { payment_method: "cash", amount_cents: 4_200 } ].to_json, sold_by: users(:cashier).id }
    assert_equal [ users(:supervisor), nil ], seller.("online"), "online, the sale is always of whoever is signed in"
  end

  test "online the rule keeps stopping as always" do
    upload("on-1", [ { product_id: products(:ketchup).id, quantity: 1, price_cents: 3_000 } ], sold_at: nil)
    assert_response :unprocessable_entity
    assert_match "It cannot be charged like this", response.parsed_body["error"]
  end
end
