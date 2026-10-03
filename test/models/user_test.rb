require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "can? depends on the role and on being active" do
    assert users(:cashier).can?("till.sell")
    assert_not users(:cashier).can?("till.lower_price")
    assert_not users(:inactive).can?("till.sell")
  end

  test "the user name is lowercase with no spaces" do
    u = User.new(name: "X", user: "With Spaces", password: "12345678", role: roles(:cashier), branch: branches(:store))
    assert_not u.valid?
    assert u.errors[:user].any?
  end
end
