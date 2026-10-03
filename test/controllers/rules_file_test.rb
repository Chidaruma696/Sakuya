require "test_helper"

class RulesFileTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  def upload(text)
    file = Rack::Test::UploadedFile.new(StringIO.new(text.dup), "text/plain", original_filename: "rules.lisp")
    post import_rules_path, params: { file: file }
  end

  test "downloads the current rules as a .lisp and uploads them again as new versions" do
    get rules_file_path
    assert_match "There are no custom rules yet", response.body
    Rule.create!(hook: "shift", code: "(allow)", user: users(:admin))
    Rule.create!(hook: "price", code: "(if (> (discount) 10)\n  (reject \"too much\")\n  (allow))", version: 0, user: users(:admin))
    get export_rules_path
    assert_equal "text/plain", response.media_type
    text = response.body
    assert_match ";;; hook: shift (contract 1)\n(allow)\n", text
    assert_match ";;; hook: price (contract 0)\n(if (> (discount) 10)\n  (reject \"too much\")\n  (allow))\n", text

    upload(text)
    assert_match "nothing changed", flash[:notice]
    assert_equal 2, Rule.count
    upload(text.sub("(allow)\n", "(to-review \"all\")\n").sub("> (discount) 10", "> (discount) 20"))
    assert_match "Imported: Cash closing in Lisp, Price in Lisp.", flash[:notice]
    assert_equal "(to-review \"all\")", Rule.current("shift").code
    assert_equal 0, Rule.current("price").version, "keeps the contract version it brings"
  end

  test "if one rule cannot be read none is imported" do
    upload(";;; hook: shift (contract 1)\n(allow)\n;;; hook: price (contract 1)\n(allow\n")
    assert_match "Nothing was imported: price:", flash[:alert]
    assert_equal 0, Rule.count
    upload(";;; hook: nothing (contract 1)\n(allow)\n")
    assert_match "unknown hook nothing", flash[:alert]
    upload("(allow)")
    assert_match "the file has no rules", flash[:alert]
  end
end
