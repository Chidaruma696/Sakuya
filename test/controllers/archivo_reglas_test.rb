require "test_helper"

class ArchivoReglasTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  def subir(texto)
    archivo = Rack::Test::UploadedFile.new(StringIO.new(texto), "text/plain", original_filename: "reglas.lisp")
    post importar_reglas_path, params: { archivo: archivo }
  end

  test "baja las reglas vigentes en un .lisp y las vuelve a subir como versiones nuevas" do
    get archivo_reglas_path
    assert_match "Todavía no hay reglas propias", response.body
    Regla.create!(gancho: "corte", codigo: "(allow)", usuario: usuarios(:admin))
    Regla.create!(gancho: "precio", codigo: "(if (> (discount) 10)\n  (reject \"mucho\")\n  (allow))", version: 0, usuario: usuarios(:admin))
    get exportar_reglas_path
    assert_equal "text/plain", response.media_type
    texto = response.body
    assert_match ";;; hook: corte (contract 1)\n(allow)\n", texto
    assert_match ";;; hook: precio (contract 0)\n(if (> (discount) 10)\n  (reject \"mucho\")\n  (allow))\n", texto

    subir(texto)
    assert_match "no cambió nada", flash[:notice]
    assert_equal 2, Regla.count
    subir(texto.sub("(allow)\n", "(to-review \"todo\")\n").sub("> (discount) 10", "> (discount) 20"))
    assert_match "Importadas: Cierre de caja en Lisp, Precio en Lisp.", flash[:notice]
    assert_equal "(to-review \"todo\")", Regla.vigente("corte").codigo
    assert_equal 0, Regla.vigente("precio").version, "conserva la versión de contrato que trae"
  end

  test "si una regla no se lee no se importa ninguna" do
    subir(";;; hook: corte (contract 1)\n(allow)\n;;; hook: precio (contract 1)\n(allow\n")
    assert_match "No se importó nada: precio:", flash[:alert]
    assert_equal 0, Regla.count
    subir(";;; hook: nada (contract 1)\n(allow)\n")
    assert_match "no conozco el gancho nada", flash[:alert]
    subir("(allow)")
    assert_match "no trae ninguna regla", flash[:alert]
  end
end
