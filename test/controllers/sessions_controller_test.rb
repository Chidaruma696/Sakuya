require "test_helper"

class AboutTest < ActionDispatch::IntegrationTest
  test "the ribbon logo opens the About box with version, build and session" do
    post login_path, params: { user: "admin", password: "secret12" }
    get root_path
    assert_select "button[title='About Sakuya'] img[alt=Sakuya]"
    # On a narrow screen the ribbon lives in a sidebar with the same tabs and buttons
    assert_select "aside[data-sidebar-target=panel]" do
      assert_select "a", /Receive/
      assert_select "a", /Counts/
    end
    assert_select "dialog[data-dialog-target=dialog]" do
      assert_select "dd", /#{Regexp.escape(Sakuya::VERSION)}/
      assert_select "dd", /Rails #{Regexp.escape(Rails.version)}/
      assert_select "dd", /Administrator/
      assert_select "a[href='https://github.com/Chidaruma696/Sakuya']"
    end
    get login_path
    assert_response :redirect, "when logged in it does not go back to the login"
  end
end

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "without a session it sends you to log in" do
    get root_path
    assert_redirected_to login_path
  end

  test "logs in with correct user and password" do
    post login_path, params: { user: "Cashier", password: "secret12" }
    assert_redirected_to root_path
    follow_redirect!
    assert_select "header", /Store 1/
    assert_select "li", /Sell at the register/
  end

  test "rejects a wrong password and inactive users" do
    post login_path, params: { user: "cashier", password: "bad" }
    assert_response :unprocessable_entity
    post login_path, params: { user: "inactive", password: "secret12" }
    assert_response :unprocessable_entity
  end

  test "logging out ends the session" do
    post login_path, params: { user: "admin", password: "secret12" }
    delete logout_path
    get root_path
    assert_redirected_to login_path
  end
end
