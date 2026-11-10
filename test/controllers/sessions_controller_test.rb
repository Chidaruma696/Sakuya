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

  test "after too many wrong passwords that user waits, from that address; others do not, and a right one clears the count" do
    SessionsController::ATTEMPTS.clear
    (SessionsController::MAX_ATTEMPTS - 1).times do
      post login_path, params: { user: "cashier", password: "bad" }
      assert_response :unprocessable_entity
    end
    post login_path, params: { user: "cashier", password: "secret12" }
    assert_redirected_to root_path, "one short of the limit, the right password still gets in and starts the count over"
    delete logout_path
    SessionsController::MAX_ATTEMPTS.times { post login_path, params: { user: " Cashier ", password: "bad" } }
    post login_path, params: { user: "cashier", password: "secret12" }
    assert_response :too_many_requests
    assert_match "Too many attempts", response.body
    get root_path
    assert_redirected_to login_path, "and nobody got in"
    post login_path, params: { user: "supervisor", password: "secret12" }
    assert_redirected_to root_path, "another user is not held back"
    delete logout_path
    travel SessionsController::LOCKED_FOR + 1.second do
      post login_path, params: { user: "cashier", password: "secret12" }
      assert_redirected_to root_path, "after the wait it works again"
    end
  ensure
    SessionsController::ATTEMPTS.clear
  end

  test "changing the password or switching the user off ends the sessions they left open" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get inventory_path
    assert_response :ok
    users(:cashier).update!(password: "another12")
    get inventory_path
    assert_redirected_to login_path
    post login_path, params: { user: "cashier", password: "another12" }
    get inventory_path
    assert_response :ok
    users(:cashier).update!(active: false)
    get inventory_path
    assert_redirected_to login_path
  end

  test "an administrator changing their own password stays in; a session left unused runs out" do
    post login_path, params: { user: "admin", password: "secret12" }
    patch admin_user_path(users(:admin)), params: { user: { name: "Administrator", user: "admin", password: "another12" } }
    assert_redirected_to admin_users_path
    get admin_users_path
    assert_response :ok, "the one who changed it is still signed in"
    travel ApplicationController::SESSION_DAYS.days - 1.hour do
      get admin_users_path
      assert_response :ok, "used within the window, the session is pushed back"
    end
    travel 2 * ApplicationController::SESSION_DAYS.days do
      get admin_users_path
      assert_redirected_to login_path
    end
  end
end
