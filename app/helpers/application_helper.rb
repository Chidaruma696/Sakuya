module ApplicationHelper
  def format_money(cents)
    Money.format_money(cents)
  end

  def quantity(value, product)
    "#{number_with_precision(value, precision: product.decimals)} #{product.short_unit}"
  end

  # A Bootstrap Icons icon, with optional text after it: icon("printer", "Print").
  def icon(name, text = nil)
    i = tag.i(class: "bi bi-#{name}")
    text ? safe_join([ i, " ", text ]) : i
  end

  # A stable color per destination, so orders for two stores are not mixed up when filled at the same time.
  def color_destination(name)
    h = name.to_s.upcase.each_char.reduce(0) { |acc, c| (acc * 31 + c.ord) % 360 }
    "hsl(#{h}, 65%, 38%)"
  end
end
