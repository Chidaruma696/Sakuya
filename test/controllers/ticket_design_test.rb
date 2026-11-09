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

  test "the blocks follow the saved layout, on screen and on the thermal printer" do
    assert_equal TicketLayout::BLOCKS.keys, TicketLayout.current.map(&:key), "out of the box, the ticket as it always was"
    layout = [ { k: "footer" }, { k: "name", a: "left", l: true }, { k: "tagline", off: true }, { k: "nothing" }, { k: "lines", a: "right", off: true },
               { k: "address", b: true, u: true }, { k: "phone", b: false } ].to_json
    patch settings_ticket_path, params: { setting: { "business.name" => "Rosie's Corner Shop", "ticket.tagline" => "Since 1990", "business.ticket_footer" => "Come back soon", "business.address" => "12 Main St", "business.phone" => "555 0101", "ticket.layout" => layout } }
    assert_redirected_to settings_section_path("business")
    blocks = TicketLayout.current
    assert_equal %w[footer name tagline lines address phone logo], blocks.first(7).map(&:key), "unknown blocks are dropped and the missing ones go at the end"
    assert_equal TicketLayout::BLOCKS.size, blocks.size
    assert_equal [ nil, false ], blocks[3].then { |b| [ b.align, b.off ] }, "what was sold can only be moved"

    Inventory.move!(branch: branches(:store), product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
    sale = Till.checkout!(branch: branches(:store), user: users(:supervisor), key: "tk2", lines: [ { product_id: products(:ketchup).id, quantity: 1 } ],
                         payments: [ { payment_method: "cash", amount_cents: 10_000 } ])
    post login_path, params: { user: "supervisor", password: "secret12" }
    get till_ticket_path(sale)
    assert_equal %w[footer name lines], css_select("[data-block]").first(3).map { |b| b["data-block"] }
    assert_select "[data-block=name].a-left.large", /Rosie's Corner Shop/
    assert_select "[data-block=tagline]", 0, "a hidden block is not on the real ticket"
    assert_select "[data-block=address].bold.underline", /12 Main St/
    assert_select "[data-block=phone].bold", 0, "the phone comes in bold, and it was switched off"
    assert_select "[data-block=name].bold", 1, "the name stays in bold"
    bytes = EscPos.ticket(sale)
    assert_operator bytes.index("Come back soon"), :<, bytes.index("Rosie's Corner Shop")
    assert_not_includes bytes, "Since 1990"
    assert_includes bytes, "\eE\x01\e-\x01" + "12 Main St\n" + "\e-\x00\eE\x00", "bold and underlined on the thermal printer too"

    post login_path, params: { user: "admin", password: "secret12" }
    get settings_section_path("business")
    assert_select "iframe[srcdoc*='block a-center off\" data-block=\"tagline\"']", true, "in the designer the hidden block is there, to bring it back"
    assert_select "#ticket_tools button[data-needs=align]", 3
    assert_select "input[name='setting[ticket.layout]'][value*='footer']"

    patch settings_ticket_path, params: { setting: { "ticket.layout" => "nonsense" } }
    assert_match "layout", flash[:alert]
    patch settings_ticket_path, params: { setting: { "ticket.layout" => TicketLayout.dump(TicketLayout.default) } }
    assert_nil Setting.find_by(key: "ticket.layout"), "the built-in layout is not stored"
  end

  test "the ticket's fixed words can be retyped and come out on screen and on the thermal printer" do
    assert_equal [ "Product", "TOTAL" ], TicketLayout.labels.values_at("product", "total")
    get settings_section_path("business")
    assert_select "input[name='setting[ticket.labels]']"
    assert_select "iframe[srcdoc*='data-label-key=\"product\" data-default=\"Product\"']"

    typed = { product: "  Item ", total: "TO PAY", folio: TicketLayout.default_label("folio"), change: "", nothing: "x" }.to_json
    patch settings_ticket_path, params: { setting: { "ticket.labels" => typed } }
    assert_redirected_to settings_section_path("business")
    assert_equal({ "product" => "Item", "total" => "TO PAY" }, JSON.parse(Setting["ticket.labels"]), "only what differs from the built-in word is kept")
    assert_equal [ "Item", "Quantity", "Change" ], TicketLayout.labels.values_at("product", "quantity", "change")

    Inventory.move!(branch: branches(:store), product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
    sale = Till.checkout!(branch: branches(:store), user: users(:supervisor), key: "tk3", lines: [ { product_id: products(:ketchup).id, quantity: 1 } ],
                         payments: [ { payment_method: "cash", amount_cents: 10_000 } ])
    post login_path, params: { user: "supervisor", password: "secret12" }
    get till_ticket_path(sale)
    assert_select "th [data-label-key=product]", "Item"
    assert_select "td [data-label-key=total]", "TO PAY"
    assert_includes EscPos.ticket(sale), "TO PAY"

    post login_path, params: { user: "admin", password: "secret12" }
    patch settings_ticket_path, params: { setting: { "ticket.labels" => "[1]" } }
    assert_match "layout", flash[:alert]
    patch settings_ticket_path, params: { setting: { "ticket.labels" => { product: "Product" }.to_json } }
    assert_nil Setting.find_by(key: "ticket.labels")
  end

  test "a logo that is not an image or is huge gets rejected" do
    patch settings_ticket_path, params: { setting: { "ticket.logo" => "data:text/plain;base64,aGVsbG8=" } }
    assert_match "logo", flash[:alert]
    patch settings_ticket_path, params: { setting: { "ticket.logo" => "data:image/png;base64," + ("A" * 500_000) } }
    assert_match "logo", flash[:alert]
    assert_equal "", Setting["ticket.logo"]
  end
end
