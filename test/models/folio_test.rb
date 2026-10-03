require "test_helper"

class FoliosByBranchTest < ActiveSupport::TestCase
  test "each branch keeps its own numbering: two stores can both have their K-00001" do
    a = StockCount.open!(branch: branches(:head_office), user: users(:admin), responsible: users(:admin))
    b = StockCount.open!(branch: branches(:store), user: users(:supervisor), responsible: users(:cashier))
    assert_equal a.folio, b.folio
    assert_equal "K-00001", b.folio
    assert_raises(ActiveRecord::RecordInvalid) { StockCount.create!(branch: branches(:store), user: users(:supervisor), responsible: users(:cashier), folio: "K-00001") }
  end
end

class FolioTest < ActiveSupport::TestCase
  test "numbers by branch and prefix, starting at 1 with five digits" do
    assert_equal "B-00001", Folio.next_number!(branches(:head_office), "sale")
    assert_equal "B-00002", Folio.next_number!(branches(:head_office), "sale")
    assert_equal "B-00001", Folio.next_number!(branches(:store), "sale")
    assert_equal "TG-00001", Folio.next_number!(branches(:head_office), "stock_transfer")
  end

  test "never repeats a folio even when many are requested in a row" do
    folios = 50.times.map { Folio.next_number!(branches(:store), "sale") }
    assert_equal folios.uniq.size, folios.size
    assert_equal "B-00050", folios.last
  end

  test "the business picks the prefix and changing it does not restart the count; with no prefix only the number comes out" do
    Folio.next_number!(branches(:head_office), "sale")
    Setting.store!("folios.sale" => "nv")
    assert_equal "NV-00002", Folio.next_number!(branches(:head_office), "sale"), "it is stored in uppercase and the count goes on"
    Setting.store!("folios.sale" => "")
    assert_equal "00003", Folio.next_number!(branches(:head_office), "sale")
    assert_raises(ArgumentError) { Setting.store!("folios.sale" => "B-1") }
    assert_raises(ArgumentError) { Setting.store!("folios.sale" => "TOOLONG") }
  end

  test "the branch code can go in front, and the setup wizard builds the settings from the choices" do
    Setting.store!("folios.branch" => "1")
    assert_equal "MTZ-B-00001", Folio.next_number!(branches(:head_office), "sale")
    assert_equal({ "folios.mode" => "per_document", "folios.branch" => "0", "folios.sale" => "NV" }, Setup.folio_settings("per_document", "own", "nv"))
    assert_equal "", Setup.folio_settings("single", "none", nil)["folios.single"]
    assert_equal({ "folios.mode" => "single", "folios.branch" => "1", "folios.single" => "" }, Setup.folio_settings("single", "branch", "B"))
  end

  test "with single numbering every document shares the count, per branch" do
    Setting.store!("folios.mode" => "single", "folios.single" => "F")
    assert_equal "F-00001", Folio.next_number!(branches(:head_office), "sale")
    assert_equal "F-00002", Folio.next_number!(branches(:head_office), "shift")
    assert_equal "F-00003", Folio.next_number!(branches(:head_office), "receipt")
    assert_equal "F-00001", Folio.next_number!(branches(:store), "sale")
    assert_raises(ArgumentError) { Setting.store!("folios.mode" => "odd") }
    Setting.store!("folios.mode" => "per_document")
    assert_equal "B-00001", Folio.next_number!(branches(:head_office), "sale"), "when switching back, each document picks up its own count"
  end
end
