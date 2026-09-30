require "test_helper"

class AtributosI18nTest < ActiveSupport::TestCase
  test "los errores de formulario nombran el campo en el idioma del usuario" do
    p = Producto.new(clave: "X", unidad: "kg")
    I18n.with_locale(:en) { p.valid?; assert_includes p.errors.full_messages, "Name can't be blank" }
    I18n.with_locale(:de) { p.valid?; assert_includes p.errors.full_messages, "Name muss ausgefüllt werden" }
    I18n.with_locale(:es) { p.valid?; assert_includes p.errors.full_messages, "Nombre no puede estar en blanco" }
    c = Proveedor.new
    I18n.with_locale(:en) { c.valid?; assert_includes c.errors.full_messages, "Name can't be blank" }
  end
end
