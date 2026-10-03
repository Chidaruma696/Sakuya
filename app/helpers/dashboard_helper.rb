module DashboardHelper
  # A dashboard figure with its format: money, number or percentage.
  def dashboard_figure(piece)
    value = piece.value
    return value if value.is_a?(String)
    case piece.format
    when :money then format_money((BigDecimal(value.to_s) * 100).round.to_i)
    when :percent then number_to_percentage(value, precision: 1, strip_insignificant_zeros: true)
    else number_with_delimiter(value.is_a?(Integer) ? value : BigDecimal(value.to_s).round(2).to_s("F"))
    end
  end
end
