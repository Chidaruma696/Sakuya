# Lo que se sabe de la cuenta de un cliente, para la regla de crédito y para su estado de cuenta.
# Los abonos matan los cargos más viejos primero; lo que sobra de un abono queda a favor.
class CuentaCliente
  attr_reader :cliente

  def initialize(cliente, hoy: Date.current)
    @cliente = cliente
    @hoy = hoy
  end

  def movimientos = @movimientos ||= cliente.movimientos_credito.en_orden.to_a
  def saldo_centavos = movimientos.sum(&:monto_centavos)

  # Lo que se debe de cargos con más de `dias` días.
  def vencido_centavos(dias) = cargos_vivos.select { |fecha, _| (@hoy - fecha).to_i > dias }.sum { |_, resta| resta }

  # Días desde el último abono; nil si nunca abonó.
  def dias_sin_abonar
    ultimo = movimientos.select { |m| m.tipo == "abono" }.map(&:fecha).max
    ultimo && (@hoy - ultimo).to_i
  end

  # [[fecha, lo que queda]] de cada cargo sin cubrir.
  def cargos_vivos
    @cargos_vivos ||= begin
      cargos = []
      a_favor = 0
      movimientos.each do |m|
        if m.monto_centavos.positive?
          usa = [ a_favor, m.monto_centavos ].min
          a_favor -= usa
          cargos << [ m.fecha, m.monto_centavos - usa ] if m.monto_centavos > usa
        else
          resta = -m.monto_centavos
          cargos.each do |c|
            break if resta.zero?
            aplica = [ c[1], resta ].min
            c[1] -= aplica
            resta -= aplica
          end
          a_favor += resta
        end
      end
      cargos.select { |c| c[1].positive? }
    end
  end
end
