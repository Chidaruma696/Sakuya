require "test_helper"

class TicketDesignTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  test "the designer shows the preview and what is saved comes out on the real ticket" do
    get settings_section_path("business")
    assert_response :success
    assert_select "iframe[srcdoc*='B-00042']", true, "the preview carries the sample sale"

    logo = "data:image/png;base64," + Base64.strict_encode64("\x89PNG\r\n\x1a\n").to_s
    patch settings_ticket_path, params: { setting: { "business.name" => "Rosie's Corner Shop", "ticket.tagline" => "Since 1990", "ticket.tax_id" => "XAXX010101000",
                                                    "ticket.logo" => logo, "ticket.show_cashier" => "0", "ticket.width" => "58", "business.ticket_footer" => "Come back soon" } }
    assert_redirected_to settings_section_path("business")
    assert_equal 48, Setting.ticket_width_mm

    Inventory.move!(branch: branches(:store), product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
    sale = Till.checkout!(branch: branches(:store), user: users(:supervisor), key: "tk1", lines: [ { product_id: products(:ketchup).id, quantity: 1 } ],
                         payments: [ { payment_method: "cash", amount_cents: 10_000 } ])
    post login_path, params: { user: "supervisor", password: "secret12" }
    get till_ticket_path(sale)
    assert_response :success
    assert_select ".ticket[style*='width: 48mm']"
    assert_select "[data-ticket='business.name']", "Rosie's Corner Shop"
    assert_select "[data-ticket='ticket.tagline']", "Since 1990"
    assert_select "[data-ticket='ticket.tax_id']", "XAXX010101000"
    assert_select "[data-ticket='ticket.show_cashier'].hidden"
    assert_select "[data-ticket='logo'] img[src^='data:image/png']"
    assert_select "[data-ticket='business.ticket_footer']", "Come back soon"
  end

  test "a logo that is not an image or is huge gets rejected" do
    patch settings_ticket_path, params: { setting: { "ticket.logo" => "data:text/plain;base64,aGVsbG8=" } }
    assert_match "logo", flash[:alert]
    patch settings_ticket_path, params: { setting: { "ticket.logo" => "data:image/png;base64," + ("A" * 500_000) } }
    assert_match "logo", flash[:alert]
    assert_equal "", Setting["ticket.logo"]
  end
end
