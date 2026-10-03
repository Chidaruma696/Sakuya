require "test_helper"

class BranchTest < ActiveSupport::TestCase
  test "there is one head office and the rest are stores" do
    assert_equal branches(:head_office), Branch.head_office
    assert_not branches(:store).head_office?
    assert_not Branch.new(code: "X", name: "X", kind: "storage").valid?
  end
end
