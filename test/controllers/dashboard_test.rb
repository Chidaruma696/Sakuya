require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  test "home draws the saved program, and the editor tests, saves and restores" do
    get root_path
    assert_select ".stat-label", 8
    assert_select "a[href=?]", dashboard_edit_path

    get dashboard_edit_path
    assert_response :ok
    assert_select "textarea#code", /\(tile :sales\)/

    post dashboard_save_path, params: { dry_run: "1", code: %((dashboard (tile "Just this" 7))) }
    assert_response :ok
    assert_select ".stat-label", /Just this/
    assert_equal 0, Rule.count, "testing does not save"

    post dashboard_save_path, params: { code: "(dashboard (tile :sales" }
    assert_response :unprocessable_entity
    assert_select "p", /missing 2 closing parentheses/
    assert_equal 0, Rule.count

    post dashboard_save_path, params: { code: %((dashboard (tile "Just this" 7))) }
    assert_redirected_to root_path
    get root_path
    assert_select ".stat-label", 1
    assert_select ".stat-label", /Just this/

    first = Rule.first
    post dashboard_save_path, params: { code: "(dashboard (tile :tickets))" }
    post dashboard_restore_path(first)
    assert_redirected_to dashboard_edit_path
    assert_equal first.code, Rule.current("dashboard").code
    assert_equal 3, Rule.count, "restoring records another version, it does not delete"
  end

  test "testing from the modal returns only the preview, or the error" do
    post dashboard_save_path, params: { dry_run: "1", code: %((dashboard (tile "In the modal" 3))) }, xhr: true
    assert_response :ok
    assert_no_match "<html", response.body
    assert_select ".stat-label", /In the modal/
    post dashboard_save_path, params: { dry_run: "1", code: "(dashboard (tile :sales" }, xhr: true
    assert_response :unprocessable_entity
    assert_match "missing 2 closing parentheses", response.body
    assert_select ".stat-label", 0
    assert_equal 0, Rule.count
    get dashboard_edit_path
    assert_select "dialog[data-preview-target=dialog]"
    assert_select "button[data-action='preview#dryRun']"
  end

  test "with sample data the preview comes out full, warns that it is made up and saves nothing" do
    post dashboard_save_path, params: { dry_run: "1", sample: "1", code: %((dashboard (tile :sales) (tile "Chicken" (sold "CHKN")) (panel :top-products) (panel :closed-cash-counts))) }, xhr: true
    assert_response :ok
    assert_match "Made-up sample data", response.body
    assert_select ".stat-value", /\$18,450\.50/
    assert_select "td", /Chicken breast/
    assert_select "td", /C-00041/
    post dashboard_save_path, params: { dry_run: "1", sample: "1", code: %((dashboard (tile "x" (sold "NONE")))) }, xhr: true
    assert_response :unprocessable_entity
    assert_match "there is no product with code NONE", response.body
    assert_equal 0, Rule.count
    assert_equal 0, Sale.count, "the sample does not touch the database"
    get dashboard_edit_path
    assert_select "input[type=checkbox][name=sample]"
  end

  test "a program that crashes on Home does not bring the page down: the default one shows with a warning" do
    Rule.create!(hook: "dashboard", code: "(dashboard (tile :nothing))", user: users(:admin))
    get root_path
    assert_response :ok
    assert_select ".stat-label", 8
    assert_select "div", /has an error/
  end

  test "the editor lives in Settings, under the advanced options" do
    get settings_path
    assert_select "nav li", /Advanced/
    assert_select "nav a[href=?]", dashboard_edit_path
    get dashboard_edit_path
    assert_select "nav a[href=?][class*=font-semibold]", dashboard_edit_path
    assert_match %r{/settings/advanced/dashboard}, dashboard_edit_path
  end

  test "without rules.edit you cannot get into the editor or see the button" do
    delete logout_path
    post login_path, params: { user: "supervisor", password: "secret12" }
    get root_path
    assert_select "a[href=?]", dashboard_edit_path, count: 0
    get settings_path
    assert_select "nav li", { text: /Advanced/, count: 0 }
    get dashboard_edit_path
    assert_response :forbidden
    post dashboard_save_path, params: { code: "(dashboard)" }
    assert_response :forbidden
  end

  # Tests run without CSRF protection; this one turns it on to test what the browser does:
  # the form carries a token bound to its URL and the modal also sends the page's token.
  test "testing and saving pass CSRF protection, from the modal and without JavaScript" do
    ActionController::Base.allow_forgery_protection = true
    get dashboard_edit_path
    form_token = css_select("form#form_dashboard input[name=authenticity_token]").first["value"]
    token_page = css_select("meta[name=csrf-token]").first["content"]

    post dashboard_save_path, params: { authenticity_token: form_token, dry_run: "1", code: "(dashboard (tile :tickets))" },
                               headers: { "X-CSRF-Token" => token_page }, xhr: true
    assert_response :ok
    post dashboard_save_path, params: { authenticity_token: form_token, dry_run: "1", code: "(dashboard (tile :tickets))" }
    assert_response :ok
    assert_equal 0, Rule.count
    post dashboard_save_path, params: { authenticity_token: form_token, code: "(dashboard (tile :tickets))" }
    assert_redirected_to root_path
    assert_equal 1, Rule.count
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
