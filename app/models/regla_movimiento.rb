# El gancho de los movimientos a mano del inventario (entradas sueltas, ajustes y mermas): antes
# de mover existencias, una regla en el Lisp de Sakuya mira qué, cuánto y por qué, y decide. Que
# haya motivo y existencias para sacar lo pone el núcleo.
#
# Contrato v1. Recibe (kind): :in, :adjust-in, :adjust-out o :waste; (quantity), (stock) lo que
# hay antes de moverlo, (product) la clave, (value) lo que vale a precio de catálogo, en pesos;
# además (reason) el motivo escrito y (authorized), verdadero si quien lo hace tiene
# inventario.ajustar. Devuelve (allow), (to-review motivo) o (reject motivo).
module ReglaMovimiento
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; Moving stock by hand: loose entries, adjustments and waste.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Without permission to adjust it stops and the attempt is reported.
    (if (authorized)
        (allow)
        (reject :needs-permission))
  LISP

  TIPOS = { "entrada" => :in, "ajuste_entrada" => :"adjust-in", "ajuste_salida" => :"adjust-out", "merma" => :waste }.freeze
  MOTIVOS = %i[needs-permission].freeze
  FUNCIONES = %w[kind quantity stock product value reason authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((not (authorized)) (reject :needs-permission))
          ((and (= (kind) :waste) (> (value) 500)) (to-review "Big waste"))
          (else (allow)))
  LISP

  extend Gancho

  CASO = "reglas/caso_movimiento".freeze # el caso de prueba del editor

  Datos = Data.define(:tipo, :producto, :cantidad, :existencia, :valor, :motivo, :autorizado)

  def self.decidir(sucursal:, producto:, tipo:, cantidad:, motivo:, usuario:, codigo: Regla.vigente("movimiento")&.codigo)
    decidir_con(codigo, datos(sucursal, producto, tipo, cantidad, motivo, usuario.puede?("inventario.ajustar")))
  end

  def self.datos(sucursal, producto, tipo, cantidad, motivo, autorizado)
    cantidad = BigDecimal(cantidad.to_s).round(3)
    Datos.new(tipo: tipo, producto: producto, cantidad: cantidad, existencia: Existencia.find_by(sucursal: sucursal, producto: producto)&.cantidad || BigDecimal("0"),
              valor: Revision.valor(cantidad, producto, sucursal), motivo: motivo.to_s, autorizado: autorizado)
  end

  # El caso de prueba del editor: un producto, qué movimiento, cuánto, por qué y si lo hace alguien
  # con permiso. Las existencias y el valor salen de la sucursal.
  def self.caso(params, sucursal)
    producto = Producto.activos.find_by(clave: params[:producto].to_s.upcase) || Producto.activos.order(:nombre).first
    tipo = params[:tipo].presence_in(TIPOS.keys) || "merma"
    cantidad = (BigDecimal(params[:cantidad].presence || "1") rescue BigDecimal("1"))
    { producto: producto, tipo: tipo, cantidad: cantidad, motivo: params[:motivo].presence || I18n.t("regla_movimiento.caso.motivo_ejemplo"),
      autorizado: params[:autorizado] == "1", sucursal: sucursal }
  end

  def self.probar(codigo, caso)
    raise Lisp::Error, I18n.t("regla_precio.sin_productos") unless caso[:producto]
    evaluar(codigo, datos(caso[:sucursal], caso[:producto], caso[:tipo], caso[:cantidad], caso[:motivo], caso[:autorizado]))
  end

  def self.textos = "regla_movimiento"

  def self.interpolar(_datos) = {}

  def self.funciones(datos)
    {
      "kind" => -> { TIPOS.fetch(datos.tipo) },
      "quantity" => -> { datos.cantidad },
      "stock" => -> { datos.existencia },
      "product" => -> { datos.producto.clave },
      "value" => -> { BigDecimal(datos.valor) / 100 },
      "reason" => -> { datos.motivo },
      "authorized" => -> { datos.autorizado }
    }
  end

  private_class_method :funciones, :interpolar, :textos, :datos
end
