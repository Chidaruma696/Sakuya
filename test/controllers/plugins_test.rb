require "test_helper"

class PluginsTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  def upload(text)
    post plugins_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new(text.dup), "text/plain", original_filename: "p.lisp") }
  end

  test "it is uploaded, shows what it brings, is switched on, switched off and removed" do
    get plugins_path
    assert_match "No plugins installed yet", response.body
    upload(Plugin::EXAMPLE)
    assert_match "It arrives off", flash[:notice]
    get plugins_path
    assert_select "#plugin_fonda", /1 function.*1 report.*1 language/m
    plugin = Plugin.last
    post toggle_plugin_path(plugin)
    assert plugin.reload.active
    post toggle_plugin_path(plugin)
    assert_not plugin.reload.active
    delete plugin_path(plugin)
    assert_equal 0, Plugin.count
    upload("(define (x) 1)")
    assert_match "Not installed", flash[:alert]
  end

  test "the reports of a plugin that is on show up as buttons in the REPL" do
    Plugin.install!(%((plugin "fonda") (report "How many products" (count (products)))), user: users(:admin))
    get repl_path
    assert_select "#reports", 0, "switched off it adds nothing"
    Plugin.last.update!(active: true)
    get repl_path
    assert_select "#reports button", "How many products"
    post repl_evaluate_path, params: { text: "(count (products))" }
    assert_select "#result pre", Product.count.to_s
  end

  test "a plugin brings a language: it is chosen in For you, what it does not translate falls back to English and switching it off goes back to the built-in ones" do
    plugin = Plugin.install!(Plugin::EXAMPLE, user: users(:admin))
    get settings_section_path("for_you")
    assert_no_match "Français", response.body
    plugin.update!(active: true)
    get settings_section_path("for_you")
    assert_match "Français", response.body
    patch settings_preferences_path, params: { user: { language: "fr" } }
    assert_equal "fr", users(:admin).reload.language
    users(:admin).update!(branch: branches(:store))
    get till_path
    assert_select "nav a", "Caisse"
    assert_select "button", "Encaisser"
    assert_select "button", "Clear ticket", "what the plugin does not translate falls back to English"
    assert_match '"pos":', response.body, "the JavaScript texts arrive complete"
    plugin.update!(active: false)
    get till_path
    assert_response :ok
    assert_select "html[lang=fr]", 0, "the user had French; without the plugin it falls back to a built-in language"
    assert_select "nav a", { text: "Caisse", count: 0 }
  end

  test "a translation with keys that do not exist is not installed" do
    text = %((plugin "bad") (translation "fr" "Français" ("till.does_not_exist" "x")))
    assert_match "these text keys do not exist: till.does_not_exist", assert_raises(Lisp::Error) { Plugin.read(text) }.message
    html = %((plugin "bad") (translation "es" "Español" ("till.exceeds_limit_html" "<script>")))
    assert_match "carry HTML", assert_raises(Lisp::Error) { Plugin.read(html) }.message
  end

  test "a plugin can change a text of a language that already exists" do
    Plugin.install!(%((plugin "shifts") (translation "en" "English" ("till.checkout" "Charge now"))), user: users(:admin)).update!(active: true)
    post login_path, params: { user: "cashier", password: "secret12" }
    get till_path
    assert_select "button", "Charge now"
  end

  test "without rules.edit you cannot get in" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get plugins_path
    assert_response :forbidden
  end
end
