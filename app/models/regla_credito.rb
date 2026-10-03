# El gancho del crédito: cuando una venta va total o parcialmente a cuenta de un cliente, una
# regla en el Lisp de Sakuya mira su cuenta y decide. De fábrica no se fía a nadie.
#
# Contrato v1. Recibe, en pesos: (amount) lo que va a cuenta, (total) el total de la venta,
# (balance) lo que debe antes de esta venta, (limit) su límite de crédito, (overdue N) lo que debe
# de hace más de N días; además (days-since-payment) los días desde su último abono (-1 si nunca),
# (customer) su nombre y (authorized), verdadero si quien cobra tiene clientes.forzar_credito.
# Devuelve (allow), (to-review motivo) o (reject motivo).
module ReglaCredito
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; Selling on account to a customer.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the box this business gives no credit: write your own rule to allow it.
    (reject :no-credit)
  LISP

  MOTIVOS = %i[no-credit over-limit].freeze
  FUNCIONES = %w[amount total balance limit overdue days-since-payment customer authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((> (overdue 30) 0) (reject "Owes from more than 30 days ago"))
          ((> (+ (balance) (amount)) (limit)) (reject :over-limit))
          (else (allow)))
  LISP

  extend Gancho

  CASO = "reglas/caso_credito".freeze # el caso de prueba del editor

  # `vencido` es una función: días → centavos debidos de hace más de esos días.
  Datos = Data.define(:cliente, :monto, :total, :saldo, :limite, :vencido, :dias_sin_abonar, :autorizado)

  def self.decidir(datos, codigo: Regla.vigente("credito")&.codigo)
    decidir_con(codigo, datos)
  end

  def self.datos(cliente, monto:, total:, autorizado:)
    cuenta = cliente.cuenta
    Datos.new(cliente: cliente.nombre, monto: monto, total: total, saldo: cuenta.saldo_centavos, limite: cliente.limite_credito_centavos,
              vencido: ->(dias) { cuenta.vencido_centavos(dias) }, dias_sin_abonar: cuenta.dias_sin_abonar, autorizado: autorizado)
  end

  # El caso de prueba del editor: un cliente de verdad (con su cuenta y su límite) o uno inventado
  # con saldo y límite; más lo que va a cuenta y si cobra alguien con permiso.
  def self.caso(params, _sucursal)
    cliente = Cliente.activos.find_by(id: params[:cliente_id]) if params[:cliente_id].present?
    { cliente: cliente, monto: params[:monto].present? ? Dinero.centavos(params[:monto]) : 50_000,
      saldo: params[:saldo].present? ? Dinero.centavos(params[:saldo]) : 0, limite: params[:limite].present? ? Dinero.centavos(params[:limite]) : 200_000,
      autorizado: params[:autorizado] == "1" }
  end

  def self.probar(codigo, caso)
    datos = if caso[:cliente]
      datos(caso[:cliente], monto: caso[:monto], total: caso[:monto], autorizado: caso[:autorizado])
    else
      Datos.new(cliente: "", monto: caso[:monto], total: caso[:monto], saldo: caso[:saldo], limite: caso[:limite], vencido: ->(_) { 0 },
                dias_sin_abonar: nil, autorizado: caso[:autorizado])
    end
    evaluar(codigo, datos)
  end

  def self.textos = "regla_credito"

  def self.interpolar(datos)
    { cliente: datos.cliente, saldo: Dinero.pesos(datos.saldo), limite: Dinero.pesos(datos.limite) }
  end

  def self.funciones(datos)
    pesos = ->(c) { BigDecimal(c.to_i) / 100 }
    {
      "amount" => -> { pesos.(datos.monto) },
      "total" => -> { pesos.(datos.total) },
      "balance" => -> { pesos.(datos.saldo) },
      "limit" => -> { pesos.(datos.limite) },
      "overdue" => ->(dias) { pesos.(datos.vencido.(Lisp::Base.numero!(dias, "overdue").to_i)) },
      "days-since-payment" => -> { datos.dias_sin_abonar || -1 },
      "customer" => -> { datos.cliente },
      "authorized" => -> { datos.autorizado }
    }
  end

  private_class_method :funciones, :interpolar, :textos
end
