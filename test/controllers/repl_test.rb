require "test_helper"

class ReplControllerTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  test "evaluates, renders a list of maps as a table and remembers the latest questions" do
    get repl_path
    assert_select "textarea#text", "(sales)"
    assert_select "a[href=?]", repl_path
    post repl_evaluate_path, params: { text: "(products)" }
    assert_response :ok
    assert_select "#result th", ":code"
    assert_select "#result td", "KETC"
    post repl_evaluate_path, params: { text: "(+ 1 2.5)" }
    assert_select "#result pre", "3.5"
    post repl_evaluate_path, params: { text: "(count-by :unit (products))" }
    assert_select "#result td", "kg"
    post repl_evaluate_path, params: { text: "(sales" }
    assert_response :unprocessable_entity
    assert_select "#error", /missing 1 closing parenthesis/
    get repl_path
    assert_select "ul a", "(count-by :unit (products))"
    assert_select "ul a", "(products)"
  end

  test "every question goes into the log, with who asked and whether it ran" do
    post repl_evaluate_path, params: { text: "(count (products))" }
    post repl_evaluate_path, params: { text: "(products" }
    assert_equal [ [ "(products", false ], [ "(count (products))", true ] ], ReplQuery.order(id: :desc).pluck(:text, :ok)
    assert_equal users(:admin), ReplQuery.last.user
    get repl_log_path
    assert_select "td code", "(count (products))"
    assert_select "td", "failed"
    assert_raises(ActiveRecord::ReadOnlyRecord) { ReplQuery.last.destroy }
  end

  test "without rules.edit there is no way in" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get repl_path
    assert_response :forbidden
    post repl_evaluate_path, params: { text: "(products)" }
    assert_response :forbidden
  end
end
