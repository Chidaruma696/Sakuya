require "test_helper"

class AttributesI18nTest < ActiveSupport::TestCase
  test "form errors name the field in the user's language" do
    p = Product.new(key: "X", unit: "kg")
    I18n.with_locale(:en) { p.valid?; assert_includes p.errors.full_messages, "Name can't be blank" }
    I18n.with_locale(:de) { p.valid?; assert_includes p.errors.full_messages, "Name muss ausgefüllt werden" }
    I18n.with_locale(:es) { p.valid?; assert_includes p.errors.full_messages, "Nombre no puede estar en blanco" }
    s = Supplier.new
    I18n.with_locale(:en) { s.valid?; assert_includes s.errors.full_messages, "Name can't be blank" }
  end
end
