module TableroHelper
  # Una cifra del tablero con su formato: dinero, número o porcentaje.
  def cifra_tablero(pieza)
    valor = pieza.valor
    return valor if valor.is_a?(String)
    case pieza.formato
    when :money then pesos((BigDecimal(valor.to_s) * 100).round.to_i)
    when :percent then number_to_percentage(valor, precision: 1, strip_insignificant_zeros: true)
    else number_with_delimiter(valor.is_a?(Integer) ? valor : BigDecimal(valor.to_s).round(2).to_s("F"))
    end
  end
end
