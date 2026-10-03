require "test_helper"

class EscPosTest < ActiveSupport::TestCase
  setup do
    store = branches(:store)
    products(:ketchup).update!(name: "Jalapeño ketchup 1 kg") # an accent to check that it survives PC850
    Inventory.move!(branch: store, product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
    @sale = Till.checkout!(branch: store, user: users(:cashier), key: "e", lines: [ { product_id: products(:ketchup).id, quantity: 2 } ],
                          payments: [ { payment_method: "cash", amount_cents: 10_000 } ])
  end

  def text(bytes) = bytes.dup.force_encoding("CP850").encode("UTF-8")

  test "the ticket resets, picks PC850, carries the lines, the total in large print, the code, and cuts" do
    b = EscPos.ticket(@sale)
    assert_equal Encoding::BINARY, b.encoding
    assert b.start_with?("\e@\et\x02".b), "resets and picks PC850"
    assert_includes b, "\x1D!\x11".b, "double-size total"
    assert_includes b, "\x1Dk\x43\x0D#{@sale.code}".b, "the ticket's EAN-13"
    assert b.end_with?("\ed\x03\x1DV\x42\x00".b), "feeds and cuts"
    t = text(b)
    assert_match "Jalapeño ketchup 1 kg", t, "accents arrive in PC850"
    assert_match(/  2 pc x \$42\.00 +\$84\.00\n/, t)
    assert_match @sale.folio, t
    assert t.lines.all? { |l| l.gsub(/[\x00-\x1F]./m, "").chomp.length <= 48 }, "nothing goes past 48 columns"
  end

  test "on 58 mm paper it uses 32 columns and no code if it was turned off" do
    Setting.store!("ticket.width" => "58", "ticket.show_code" => "0")
    t = text(EscPos.ticket(@sale))
    assert_includes t, "-" * 32 + "\n"
    assert_not_includes t, "-" * 33
    assert_not_includes EscPos.ticket(@sale), "\x1Dk".b
  end

  test "whatever does not fit in PC850 comes out as a substitute instead of breaking" do
    d = EscPos::Document.new(columns: 32).text("10 € 漢 −5")
    assert_match "10 EUR ? -5", text(d.to_s)
  end

  test "the logo comes out as a black and white raster image, and a broken one does not get in the way" do
    # 16 × 2 dots: the left half black, the right half white.
    img = Vips::Image.black(8, 2).join(Vips::Image.black(8, 2) + 255, :horizontal).cast(:uchar)
    Setting.store!("ticket.logo" => "data:image/png;base64,#{Base64.strict_encode64(img.write_to_buffer(".png"))}")
    b = EscPos.ticket(@sale)
    assert_includes b, "\x1Dv0\x00\x02\x00\x02\x00\xFF\x00\xFF\x00".b, "2 bytes per row, 2 rows, 8 black dots and 8 white"
    assert_nil EscPos.raster("data:image/png;base64,#{Base64.strict_encode64("not an image")}")
  end
end
