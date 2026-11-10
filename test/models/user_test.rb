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

  test "the last active user who can manage users cannot be switched off or demoted" do
    admin = users(:admin)
    assert_not admin.update(active: false)
    assert_match "last active user who can manage users", admin.errors.full_messages.to_sentence
    assert_not admin.reload.update(role: roles(:cashier))
    assert admin.reload.update(name: "Boss", branch: branches(:store)), "anything else can change"

    second = User.create!(name: "Second", user: "second", password: "secret12", role: roles(:administrator), branch: branches(:head_office))
    assert admin.update(active: false), "with another administrator around, it can"
    assert_not second.update(active: false), "and now the other one is the last"
    assert admin.update(active: true)
    assert second.update(role: roles(:cashier))
    assert User.active.exists?, "the first-run setup never opens again"
  end

  test "users who do not manage users are switched off and moved freely" do
    assert users(:cashier).update(active: false)
    assert users(:supervisor).update(role: roles(:cashier))
    assert users(:inactive).update(active: true)
  end
end
