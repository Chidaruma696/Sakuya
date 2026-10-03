require "test_helper"

class RoleTest < ActiveSupport::TestCase
  test "the full wildcard and the feature wildcard cover the keys" do
    assert roles(:administrator).allows?("admin.users")
    assert roles(:supervisor).allows?("till.lower_price")
    assert_not roles(:supervisor).allows?("admin.users")
    assert roles(:cashier).allows?("till.sell")
    assert_not roles(:cashier).allows?("till.lower_price")
  end

  test "a key that does not exist is never allowed, not even with a wildcard" do
    assert_not roles(:administrator).allows?("till.made_up")
  end

  test "rejects unknown permissions" do
    role = Role.new(name: "odd", permissions: [ "till.sell", "magic.*" ])
    assert_not role.valid?
    assert_match "magic.*", role.errors[:permissions].first
  end
end
