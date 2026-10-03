require "test_helper"

class SettingsTest < ActionDispatch::IntegrationTest
  test "everyone saves their language, theme, density and text size, and the system shows in their language" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get settings_path
    assert_response :ok
    assert_select "h1", "Settings"
    assert_select "h2", { text: "System", count: 0 }, "the cashier does not administer"
    patch settings_preferences_path, params: { user: { language: "es", theme: "dark", density: "compact", text_size: "large" } }
    assert_redirected_to settings_path
    u = users(:cashier).reload
    assert_equal %w[es dark compact large], [ u.language, u.theme, u.density, u.text_size ]
    follow_redirect!
    assert_select "html[lang=es][data-theme=dark][data-density=compact][data-text-size=large]"
    assert_select "h1", "Ajustes"
    patch settings_preferences_path, params: { user: { language: "de" } }
    follow_redirect!
    assert_select "h1", "Einstellungen"
    patch settings_preferences_path, params: { user: { language: "xx" } }
    assert_match "Sprache", flash[:alert]
    patch settings_system_path, params: { setting: { "business.name" => "X" } }
    assert_response :forbidden
  end

  test "the administrator changes system settings and it shows on the ticket and the price floor" do
    post login_path, params: { user: "admin", password: "secret12" }
    patch settings_system_path, params: { setting: { "business.name" => "Aurora Store", "business.ticket_footer" => "Come back soon", "till.price_floor" => "80", "till.denominations" => "100, 50, 20", "till.difference_cap" => "25" } }
    assert_redirected_to settings_section_path("features")
    assert_equal "Aurora Store", Setting["business.name"]
    assert_equal [ 10_000, 5_000, 2_000 ], Shift.denominations
    assert_equal 2_500, Shift.difference_cap_cents
    patch settings_system_path, params: { setting: { "till.denominations" => "hundred" }, back: "till" }
    assert_match "comma-separated", flash[:alert]
    assert_equal 2_500, Setting.integer("till.difference_cap") * 100
    patch settings_system_path, params: { setting: { "till.difference_cap" => "" } }
    assert_equal 0, Setting.integer("till.difference_cap"), "blank goes back to the default"
    patch settings_system_path, params: { setting: { "till.difference_cap" => "abc" } }
    assert_match "must be a whole number", flash[:alert]
    patch settings_system_path, params: { setting: { "till.difference_cap" => "25" } }

    # Price floor at 80 %: a markdown to 70 % no longer goes through, not even with permission.
    Inventory.move!(branch: branches(:store), product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
    e = assert_raises(Till::Error) do
      Till.checkout!(branch: branches(:store), user: users(:supervisor), key: "p1", lines: [ { product_id: products(:ketchup).id, quantity: 1, price_cents: 2_940 } ],
                   payments: [ { payment_method: "cash", amount_cents: 5_000 } ], authorizer: users(:supervisor))
    end
    assert_match "80 %", e.message
  end
end

class CurrencyTest < ActionDispatch::IntegrationTest
  test "the business sets the currency symbol and it shows on the server, the till and the ticket" do
    assert_equal "$1,234.50", Money.format_money(123_450)
    post login_path, params: { user: "admin", password: "secret12" }
    patch settings_system_path, params: { setting: { "business.currency" => "GTQ", "business.symbol" => "Q" } }
    Current.reset # in tests each request brings its own Current, and the test's own is restored when it ends
    assert_equal "Q1,234.50", Money.format_money(123_450)
    assert_equal "−Q0.50", Money.format_money(-50)
    get till_path
    assert_match 'window.CURRENCY = {"symbol":"Q","code":"GTQ"}', response.body
    get settings_section_path("business")
    assert_select "iframe[srcdoc*='Q214.50']"
    patch settings_system_path, params: { setting: { "business.currency" => "", "business.symbol" => "" } }
    Current.reset
    assert_equal "$1.00", Money.format_money(100), "blank goes back to the peso"
  end
end
