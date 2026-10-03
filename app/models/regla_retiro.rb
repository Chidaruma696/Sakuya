# El gancho de los retiros: antes de sacar efectivo de la gaveta, una regla en el Lisp de Sakuya
# mira cuánto y para qué, y decide. Que haya motivo y que no se saque más de lo que hay lo pone
# el núcleo, antes de preguntar.
#
# Contrato v1. Recibe, en pesos: (amount) lo que sale, (cash) lo que hay en la gaveta antes del
# retiro, (withdrawn) lo ya retirado en el corte, (cash-limit) el tope de efectivo de la sucursal;
# además (reason) el motivo escrito y (authorized), verdadero si quien retira tiene
# caja.retirar. Devuelve (allow), (to-review motivo) o (reject motivo).
module ReglaRetiro
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; Taking cash out of the drawer. (amount) is what comes out; (cash) is what the drawer has now.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Without permission to withdraw it stops and the attempt is reported.
    (if (authorized)
        (allow)
        (reject :needs-permission))
  LISP

  MOTIVOS = %i[needs-permission].freeze
  FUNCIONES = %w[amount cash withdrawn cash-limit reason authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((not (authorized)) (reject :needs-permission))
          ((> (amount) 5000) (to-review "Big withdrawal"))
          (else (allow)))
  LISP

  extend Gancho

  CASO = "reglas/caso_retiro".freeze # el caso de prueba del editor

  Datos = Data.define(:monto, :en_gaveta, :retirado, :limite, :motivo, :autorizado) do
    def pesos(centavos) = BigDecimal(centavos.to_i) / 100
  end

  def self.decidir(corte, monto_centavos:, motivo:, usuario:, codigo: Regla.vigente("retiro")&.codigo)
    decidir_con(codigo, datos(corte, monto_centavos, motivo, usuario.puede?("caja.retirar")))
  end

  def self.datos(corte, monto, motivo, autorizado)
    Datos.new(monto: monto.to_i, en_gaveta: corte.efectivo_esperado_centavos, retirado: corte.retiros_centavos,
              limite: corte.sucursal&.limite_efectivo_centavos.to_i, motivo: motivo.to_s, autorizado: autorizado)
  end

  # El caso de prueba del editor: cuánto sale, cuánto hay, para qué y si retira alguien con permiso.
  def self.caso(params, sucursal)
    corte = Corte.abierto_en(sucursal)
    en_gaveta = params[:en_gaveta].present? ? Dinero.centavos(params[:en_gaveta]) : (corte&.efectivo_esperado_centavos || 50_000)
    { monto: params[:monto].present? ? Dinero.centavos(params[:monto]) : 10_000, en_gaveta: en_gaveta,
      motivo: params[:motivo].presence || I18n.t("regla_retiro.caso.motivo_ejemplo"), autorizado: params[:autorizado] == "1",
      limite: sucursal.limite_efectivo_centavos.to_i }
  end

  def self.probar(codigo, caso)
    evaluar(codigo, Datos.new(monto: caso[:monto], en_gaveta: caso[:en_gaveta], retirado: 0, limite: caso[:limite], motivo: caso[:motivo], autorizado: caso[:autorizado]))
  end

  def self.textos = "regla_retiro"

  def self.interpolar(datos) = { monto: Dinero.pesos(datos.monto) }

  def self.funciones(datos)
    {
      "amount" => -> { datos.pesos(datos.monto) },
      "cash" => -> { datos.pesos(datos.en_gaveta) },
      "withdrawn" => -> { datos.pesos(datos.retirado) },
      "cash-limit" => -> { datos.pesos(datos.limite) },
      "reason" => -> { datos.motivo },
      "authorized" => -> { datos.autorizado }
    }
  end

  private_class_method :funciones, :interpolar, :textos, :datos
end
