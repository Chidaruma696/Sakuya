require "test_helper"

class ReglaCorteTest < ActiveSupport::TestCase
  setup do
    @corte = cortes(:tienda_abierto) # fondo de $500 y nada más: se esperan $500
  end

  def decidir(contado, codigo = nil, usuario: usuarios(:cajera))
    ReglaCorte.decidir(@corte, contado_centavos: contado, usuario: usuario, codigo: codigo)
  end

  test "la de fábrica frena: sin tope o dentro del tope pasa, fuera se rechaza aunque cierre la supervisora" do
    assert decidir(10_000).permite?, "sin tope todo pasa"
    Ajuste.guardar!("caja.tope_diferencia" => "50")
    assert decidir(45_000).permite?, "faltan $50 justos"
    d = decidir(44_999)
    assert d.rechaza?
    assert_equal "la diferencia (−$50.01) pasa del tope ($50.00)", d.motivo
    assert decidir(44_999, usuario: usuarios(:supervisora)).rechaza?, "el permiso lo mira el núcleo, no la regla"
  end

  test "una regla propia lee el conteo en pesos y decide" do
    codigo = <<~LISP
      (cond ((> (difference) 0) (to-review "sobra dinero"))
            ((< (difference) -100) (reject "falta demasiado"))
            (else (allow)))
    LISP
    assert decidir(50_000, codigo).permite?
    assert_equal [ :review, "sobra dinero" ], decidir(50_001, codigo).then { |d| [ d.veredicto, d.motivo ] }
    assert decidir(40_000, codigo).permite?, "faltan $100 justos"
    assert_equal [ :reject, "falta demasiado" ], decidir(39_999, codigo).then { |d| [ d.veredicto, d.motivo ] }
    lee = "(if (and (= (expected) 500) (= (float) 500) (= (counted) 480.50) (= (tickets) 0) (not (authorized))) (allow) (reject \"no\"))"
    assert decidir(48_050, lee).permite?, decidir(48_050, lee).inspect
  end

  test "si la regla truena o no decide, decide la de fábrica y el error viaja en la decisión" do
    Ajuste.guardar!("caja.tope_diferencia" => "50")
    d = decidir(40_000, "(allow")
    assert d.rechaza?, "decidió la de fábrica"
    assert d.error.present?
    d = decidir(50_000, "(+ 1 2)")
    assert d.permite?
    assert_match "terminó en 3", d.error
    assert_match ":over-limit", decidir(50_000, "(reject :no-existe)").error
    assert decidir(50_000, "(define (f) (f)) (f)").error.present?, "la recursión sin fin se corta"
  end

  test "sin regla guardada usa la de fábrica; con regla, la vigente" do
    assert decidir(10_000).permite?
    Regla.create!(gancho: "corte", codigo: "(reject \"nunca\")", usuario: usuarios(:admin))
    assert ReglaCorte.decidir(@corte, contado_centavos: 50_000, usuario: usuarios(:cajera)).rechaza?
  end
end
