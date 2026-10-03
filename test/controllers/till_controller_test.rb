require "test_helper"

class TillControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { user: "cashier", password: "secret12" }
    @store = branches(:store)
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:cashier))
    @weighed = { product_id: products(:chicken).id, quantity: "2.000" }
    Inventory.move!(branch: @store, product: products(:chicken), kind: "inflow", quantity: 2, user: users(:cashier))
  end

  test "the cashier lowers a price without permission: it is not charged and the attempt is reported; the supervisor does charge it and it goes to review" do
    discount = { lines: [ { product_id: products(:ketchup).id, quantity: 2, price_cents: 3_000 } ].to_json,
               payments: [ { payment_method: "cash", amount_cents: 6_000 } ].to_json }
    post till_checkout_path, params: discount.merge(key: "discount"), headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match "It cannot be charged like this", response.parsed_body["error"]
    assert_nil Sale.find_by(key: "discount")
    r = Review.last
    assert r.stopped?
    assert_equal 2_400, r.value_cents, "2 × (42.00 − 30.00)"
    assert_match "Attempt stopped in session", r.description
    get reviews_path
    assert_response :forbidden, "the cashier does not review"
    delete logout_path
    post login_path, params: { user: "supervisor", password: "secret12" }
    post till_checkout_path, params: discount.merge(key: "discount2"), headers: { "Accept" => "application/json" }
    assert_response :ok
    sale = Sale.find_by!(key: "discount2")
    assert_equal users(:supervisor), sale.lines.first.authorized_by
    assert_equal sale.lines.first, Review.last.reviewable
    delete logout_path
    post login_path, params: { user: "admin", password: "secret12" }
    get reviews_path(branch_id: "all")
    assert_select "td", /Price lowered on B-/
    assert_select "td", /Attempt stopped/
  end

  test "selling: scan, check out via JSON, print the ticket and it shows up in sales" do
    get till_path
    assert_select "input[data-pos-target=code]"
    get till_scan_path(code: "CHKN"), headers: { "Accept" => "application/json" }
    assert_equal products(:chicken).id, response.parsed_body["product_id"]
    assert_equal "kg", response.parsed_body["unit"]
    get till_scan_path(code: "KETC"), headers: { "Accept" => "application/json" }
    assert_equal "piece", response.parsed_body["unit"]
    get till_scan_path(code: "nothing"), headers: { "Accept" => "application/json" }
    assert_response :not_found

    post till_checkout_path, params: { key: "abc", lines: [ @weighed, { product_id: products(:ketchup).id, quantity: 1 } ].to_json,
                                     payments: [ { payment_method: "cash", amount_cents: 50_000 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :ok
    sale = Sale.last
    assert_equal 30_000, sale.total_cents
    assert_equal till_ticket_path(sale, print: 1), response.parsed_body["url"]
    get till_ticket_path(sale)
    assert_select "svg"
    assert_match "TOTAL", response.body
    get till_sales_path
    assert_select "td", /#{sale.folio}/
  end

  test "without an open till nothing is charged; the shift is opened, the cashier without permission cannot withdraw (it is reported), the supervisor can, and it is closed" do
    shifts(:store_open).update!(status: "closed")
    post till_checkout_path, params: { key: "x", lines: [ { product_id: products(:ketchup).id, quantity: 1 } ].to_json, payments: [ { payment_method: "cash", amount_cents: 5_000 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match "no register open", response.parsed_body["error"]
    post till_open_path, params: { float: "500.00" }
    assert_redirected_to till_path
    shift = Shift.opened_at(@store)
    assert_equal 50_000, shift.float_cents
    get till_shift_path
    assert_match "the withdrawal is stopped", response.body
    post till_withdraw_path, params: { amount: "100", reason: "to the safe" }
    assert_match "It cannot be withdrawn like this", flash[:alert]
    assert_equal 0, shift.withdrawals.count, "the cashier does not have till.withdraw: it is stopped"
    report = Review.last
    assert report.stopped?
    assert_equal [ shift, 10_000 ], [ report.reviewable, report.value_cents ]
    assert_match "Withdrawal of $100.00 stopped (to the safe)", report.reason
    post till_withdraw_path, params: { amount: "100", reason: "to the safe" }
    assert_equal 1, Review.count, "the same attempt is not reported twice"
    post login_path, params: { user: "supervisor", password: "secret12" }
    2.times { post till_withdraw_path, params: { amount: "100", reason: "to the safe" } }
    assert_equal 20_000, shift.withdrawals.sum(:amount_cents)
    assert_equal [ users(:supervisor) ], shift.withdrawals.map(&:authorized_by).uniq
    assert_equal 1, Review.count, "with permission, by default, there is nothing to review"
    post till_close_path, params: { counted: "300.00" }
    assert_redirected_to till_summary_path(shift)
    assert_equal 0, shift.reload.difference_cents
    follow_redirect!
    assert_select "div.center", /#{shift.folio}/
    assert_match "Cash drops", response.body
    assert_match "to the safe", response.body
    assert_match "1 pending review", response.body
    get till_shift_path
    assert_select "td", /#{shift.folio}/
    assert_select "a[href=?]", till_summary_path(shift)
  end

  test "closing by counting bills; with a cap, a large difference stops the cashier, gets reported and only the supervisor can close" do
    shift = shifts(:store_open)
    get till_shift_path
    assert_select "input[name='denomination[50000]']"
    assert_select "[data-drawer-target=reason]", { count: 0 }, "without a cap there is no reason to ask for"
    Setting.store!("till.difference_cap" => "50")
    get till_shift_path
    assert_select "[data-drawer-target=reason]"
    assert_match "It cannot be closed like this", response.body
    post till_close_path, params: { denomination: { "20000" => "1", "10000" => "2" }, reason: "a bill was missing" }
    assert_match "exceeds the limit ($50.00). It cannot be closed like this", flash[:alert], "the cashier does not have till.difference: not even with a reason"
    assert shift.reload.open?
    report = Review.last
    assert_equal [ shift, users(:cashier), 10_000 ], [ report.reviewable, report.user, report.value_cents ]
    assert_match "counted $400.00", report.reason
    assert_match "Attempt stopped in session", report.description
    assert report.stopped?
    post till_close_path, params: { counted: "400.00" }
    assert_equal 1, Review.count, "counting the same again does not repeat the report"
    post login_path, params: { user: "supervisor", password: "secret12" }
    post till_close_path, params: { denomination: { "20000" => "1", "10000" => "2" } }
    assert_match "write the reason", flash[:alert]
    post till_close_path, params: { denomination: { "20000" => "1", "10000" => "2" }, reason: "a bill was missing" }
    assert_redirected_to till_summary_path(shift)
    assert_match "goes to review", flash[:notice]
    assert_equal 40_000, shift.reload.counted_cents
    assert_equal(-10_000, shift.difference_cents)
    assert_equal({ "20000" => 1, "10000" => 2 }, shift.breakdown)
    r = Review.last
    assert_equal shift, r.reviewable
    assert_equal 10_000, r.value_cents
    assert_match shift.folio, r.description
    get till_shift_path
    assert_select "td[title='1 × $200.00, 2 × $100.00']"
  end

  test "closing with the typed total and a difference within the cap asks for nothing" do
    Setting.store!("till.difference_cap" => "50")
    post till_close_path, params: { counted: "480.00" }
    assert_redirected_to till_summary_path(shifts(:store_open))
    assert_no_match "review", flash[:notice]
    assert_equal(-2_000, shifts(:store_open).reload.difference_cents)
    assert_equal 0, Review.count
  end

  test "the shift rule rejects: the cashier cannot close, the supervisor can and it goes to review" do
    shift = shifts(:store_open)
    Rule.create!(hook: "shift", code: '(if (< (difference) 0) (reject "missing money") (allow))', user: users(:admin))
    get till_shift_path
    assert_match "its own closing rule", response.body, "with a custom rule the reason field is always shown"
    post till_close_path, params: { counted: "490.00", reason: "oh well" }
    assert_match "missing money. It cannot be closed like this", flash[:alert]
    assert shift.reload.open?
    post login_path, params: { user: "supervisor", password: "secret12" }
    post till_close_path, params: { counted: "490.00" }
    assert_match "missing money: write the reason", flash[:alert]
    post till_close_path, params: { counted: "490.00", reason: "counted twice" }
    assert_redirected_to till_summary_path(shift)
    assert_equal "counted twice", Review.last.reason
  end

  test "if the shift rule crashes the built-in one decides and the failure goes to review" do
    Rule.create!(hook: "shift", code: "(not-found)", user: users(:admin))
    post till_close_path, params: { counted: "500.00" }
    assert_redirected_to till_summary_path(shifts(:store_open))
    assert_match "goes to review", flash[:notice]
    assert_match "The cash count rule failed", Review.last.reason
    Setting.store!("till.difference_cap" => "50")
    post till_open_path, params: { float: "500" }
    post till_close_path, params: { counted: "100.00" }
    assert_match "It cannot be closed like this", flash[:alert], "the built-in one stops it"
    assert_match(/Closing attempt stopped.*\nThe cash count rule failed/m, Review.last.reason)
  end

  test "with the customers feature the till asks for the customer and what goes on account" do
    get till_path
    assert_select "[data-pos-target=credit]", 0
    Features.store!(Features::OPTIONAL, check: false)
    customer = Customer.create!(name: "Lupita's Diner")
    Rule.create!(hook: "credit", code: "(allow)", user: users(:admin))
    get till_path
    assert_select "select[data-pos-target=customer] option", /Lupita's Diner/
    assert_select "[data-pos-target=credit]"
    post till_checkout_path, params: { key: "credit", customer_id: customer.id, lines: [ { product_id: products(:ketchup).id, quantity: 1 } ].to_json,
                                     payments: [ { payment_method: "credit", amount_cents: 4_200 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :ok
    assert_equal 4_200, customer.balance_cents
  end

  test "the ticket downloads as ESC/POS for a thermal printer" do
    sale = Till.checkout!(branch: @store, user: users(:cashier), key: "t", lines: [ { product_id: products(:ketchup).id, quantity: 1 } ],
                         payments: [ { payment_method: "cash", amount_cents: 5_000 } ])
    get till_ticket_path(sale)
    assert_select "a[href=?]", till_escpos_path(sale, download: 1)
    get till_escpos_path(sale, download: 1)
    assert_equal "application/octet-stream", response.media_type
    assert_match "#{sale.folio}.bin", response.headers["Content-Disposition"]
    assert response.body.b.start_with?("\e@".b)
  end

  test "the ticket prints according to the branch printer: browser, network or cable" do
    sale = Till.checkout!(branch: @store, user: users(:cashier), key: "i", lines: [ { product_id: products(:ketchup).id, quantity: 1 } ],
                         payments: [ { payment_method: "cash", amount_cents: 5_000 } ])
    get till_ticket_path(sale, print: 1)
    assert_match "window.print()", response.body
    assert_select "#thermal", 0
    @store.update!(printer: "serial")
    get till_ticket_path(sale, print: 1)
    assert_select "#thermal"
    assert_match "navigator.serial", response.body
    server = TCPServer.new("127.0.0.1", 0)
    received = +"".b
    thread = Thread.new { c = server.accept; received << c.read; c.close }
    @store.update!(printer: "network", network_printer: "127.0.0.1:#{server.addr[1]}")
    post till_print_path(sale), headers: { "Accept" => "application/json" }
    thread.join(3)
    assert_response :ok
    assert received.start_with?("\e@".b)
    assert_includes received, sale.folio
    server.close
    post till_print_path(sale), headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match "does not answer", response.parsed_body["error"]
  end

  test "the shift summary also comes out as ESC/POS and on the network thermal printer" do
    shift = shifts(:store_open)
    Till.checkout!(branch: @store, user: users(:cashier), key: "r", lines: [ { product_id: products(:ketchup).id, quantity: 1 } ],
                 payments: [ { payment_method: "cash", amount_cents: 5_000 } ])
    shift.close!(counted_cents: 54_200, user: users(:cashier))
    get till_summary_path(shift)
    assert_select "a[href=?]", "#{till_summary_escpos_path(shift)}?download=1"
    get till_summary_escpos_path(shift)
    text = response.body.b.force_encoding("CP850").encode("UTF-8")
    assert_match(/Sales \(1\) +\$42\.00/, text)
    assert_match(/Difference +\$0\.00/, text)
    assert_match "Ketchup 1 kg", text
    @store.update!(printer: "network", network_printer: "127.0.0.1:1")
    get till_summary_path(shift)
    assert_select "#thermal"
    post till_summary_print_path(shift), headers: { "Accept" => "application/json" }
    assert_match "does not answer", response.parsed_body["error"]
  end

  test "refunds only with a ticket" do
    sale = Till.checkout!(branch: @store, user: users(:cashier), key: "v1", lines: [ @weighed ], payments: [ { payment_method: "cash", amount_cents: 30_000 } ])
    get till_refund_path(code: "0000000000000")
    assert_match "No receipt, no return", response.body
    get till_refund_path(code: sale.folio)
    assert_select "strong", sale.folio
    line = sale.lines.first
    post till_create_refund_path, params: { sale_id: sale.id, lines: { line.id => "2" }, reason: "" }
    assert_redirected_to till_refund_path(code: nil)
    post till_create_refund_path, params: { sale_id: sale.id, lines: { line.id => "2" }, reason: "bad smell" }
    assert_redirected_to till_sales_path
    assert_equal "refunded", sale.reload.status
  end
end
