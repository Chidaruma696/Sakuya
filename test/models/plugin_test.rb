require "test_helper"

class PluginTest < ActiveSupport::TestCase
  def install(text = Plugin::EXAMPLE) = Plugin.install!(text, user: users(:admin))

  test "reads the header, functions, reports and translations of the example" do
    parsed = Plugin.read(Plugin::EXAMPLE)
    assert_equal "fonda", parsed.identifier
    assert_equal "Fonda", parsed.data["name"]
    assert_equal 1, parsed.functions.size
    assert_equal [ "Sales of the week", "(sum-of :total (sales (days-ago 7) (today)))" ], [ parsed.reports.first.title, parsed.reports.first.code ]
    assert_equal({ "till.checkout" => "Encaisser", "ribbon.tabs.till" => "Caisse" }, parsed.translations.first.texts)
  end

  test "rejects what a plugin cannot bring" do
    assert_match "must start with (plugin", assert_raises(Lisp::Error) { Plugin.read("(define (x) 1)") }.message
    assert_match "will not do", assert_raises(Lisp::Error) { Plugin.read('(plugin "Bad Name")') }.message
    assert_match "only declares", assert_raises(Lisp::Error) { Plugin.read(%((plugin "one") (+ 1 2))) }.message
    assert_match "the plugin prefix: one/", assert_raises(Lisp::Error) { Plugin.read(%((plugin "one") (define (sales) 0))) }.message
    assert_match "(report", assert_raises(Lisp::Error) { Plugin.read(%((plugin "one") (report 1 2))) }.message
    assert_match "key", assert_raises(Lisp::Error) { Plugin.read(%((plugin "one") (translation "fr" "Français" ("only")))) }.message
    assert_match "missing 1 closing parenthesis", assert_raises(Lisp::Error) { Plugin.read('(plugin "one"') }.message
  end

  test "its functions work in rules and the REPL only when switched on, and the built-in rules do not depend on them" do
    plugin = install(%((plugin "fonda") (define (fonda/double x) (* 2 x)) (define fonda/cap 300)))
    assert_not plugin.active, "arrives off"
    assert_raises(Lisp::Error) { Repl.evaluate("(fonda/double 2)", branches: [ branches(:store) ]) }
    plugin.update!(active: true)
    assert_equal 4, Repl.evaluate("(fonda/double 2)", branches: [ branches(:store) ])
    data = ShiftRule::Input.new(Shift.new(float_cents: 50_000), 0, authorized: false)
    assert ShiftRule.evaluate("(if (> (fonda/double (abs (difference))) fonda/cap) (to-review \"x\") (allow))", data).review?
    plugin.update!(code: %((plugin "fonda") (define (fonda/double x) (/ x 0))))
    d = ShiftRule.decide(shifts(:store_open), counted_cents: 50_000, user: users(:cashier), code: "(if (fonda/double 1) (allow) (allow))")
    assert d.allows?, "the built-in rule decided without the plugin"
    assert_match "cannot divide by zero", d.error
  end

  test "uploading the same identifier updates it and keeps whether it was switched on" do
    install.update!(active: true)
    plugin = install(Plugin::EXAMPLE.sub(%((version "1.0")), %((version "1.1"))))
    assert_equal [ 1, "1.1", true ], [ Plugin.count, plugin.version, plugin.active ]
  end
end
