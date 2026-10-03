require "test_helper"

class SetupTest < ActionDispatch::IntegrationTest
  test "with no active user everything sends to install, where the administrator is created and logged in" do
    User.update_all(active: false)
    get root_path
    assert_redirected_to install_path
    get login_path
    assert_redirected_to install_path

    get install_path
    assert_response :success
    assert_select "html[data-theme=light]", true, "starts in light mode"
    assert_select "section[data-steps-target=step]", 7, "goes step by step"
    assert_select "section:first-of-type a[href=?]", install_path(language: "de"), true, "the language is the first step"
    assert_select "input[name='setup[user]'][value=admin]"
    get install_path(language: "de")
    assert_select "html[lang=de]", true, "the language is changed from the screen"
    get install_path
    assert_select "html[lang=de]", true, "and it is remembered"

    post install_path, params: { setup: { business: "Aurora Store", business_type: "store", branch: "Plant", code: "pl1", name: "Rose Miller", user: "Rose", password: "secret123", language: "es", theme: "dark", text_size: "large", folios_mode: "single", folios_prefix: "branch" } }
    assert_redirected_to root_path
    rose = User.find_by!(user: "rose")
    assert_equal "Rose Miller", rose.name
    assert rose.can?("admin.users"), "the first user is an administrator"
    assert_equal "PL1", rose.branch.code
    assert_equal "PL1-00001", Folio.next_number!(rose.branch, "sale"), "single numbering with the branch code in front"
    assert rose.branch.head_office?
    assert_equal "Aurora Store", Setting["business.name"]
    assert_equal "es", rose.language
    assert_equal %w[dark large normal], [ rose.theme, rose.text_size, rose.density ], "the chosen appearance stays with the user"
    assert_equal %w[purchases stock_counts], Features.active, "the business type leaves only its own features on"

    follow_redirect!
    assert_response :success, "ends up logged in"
    assert_select "html[lang=es]"
  end

  test "once there are users the install screen no longer exists" do
    get install_path
    assert_redirected_to root_path
    post install_path, params: { setup: { name: "X", user: "x", password: "secret123" } }
    assert_redirected_to root_path
    assert_nil User.find_by(user: "x")
  end

  test "with bad data it says so and leaves nothing half done" do
    User.update_all(active: false)
    post install_path, params: { setup: { business: "X", business_type: "store", branch: "Plant", code: "PL1", name: "", user: "rose", password: "secret123" } }
    assert_response :unprocessable_entity
    assert_nil User.find_by(user: "rose")
    assert_nil Branch.find_by(code: "PL1"), "the whole transaction is rolled back"
  end
end
