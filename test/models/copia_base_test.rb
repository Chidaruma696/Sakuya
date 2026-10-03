require "test_helper"

class CopiaBaseTest < ActiveSupport::TestCase
  # Sin transacción: Rails metería en ella también la conexión al destino y nada se confirmaría.
  # Por eso la prueba no crea datos en el origen; copia los fixtures, que ya están confirmados.
  self.use_transactional_tests = false

  setup do
    @ruta = Rails.root.join("tmp", "copia_#{Process.pid}.sqlite3")
    FileUtils.rm_f(@ruta)
    entorno = { "DATABASE_URL" => "sqlite3:#{@ruta}", "RAILS_ENV" => "test", "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1" }
    assert system(entorno, "bin/rails", "db:schema:load", out: File::NULL, err: File::NULL), "no se cargó el esquema del destino"
  end

  teardown { FileUtils.rm_f(@ruta) }

  test "copia todo, en orden, y cuadra; un destino con datos no se toca" do
    lineas = []
    tablas = CopiaBase.copiar!("sqlite3:#{@ruta}", avisar: ->(l) { lineas << l })
    assert_operator tablas, :>, 30
    assert_includes lineas, "sucursales: #{Sucursal.count}"
    assert lineas.index { |l| l.start_with?("roles:") } < lineas.index { |l| l.start_with?("usuarios:") }, "primero de quien dependen"
    CopiaBase::Destino.establish_connection("sqlite3:#{@ruta}")
    assert_equal Producto.order(:id).pluck(:clave), CopiaBase::Destino.connection.select_values("SELECT clave FROM productos ORDER BY id")
    CopiaBase::Destino.remove_connection
    assert_match "ya tiene datos", assert_raises(CopiaBase::Error) { CopiaBase.copiar!("sqlite3:#{@ruta}") }.message
  end
end
