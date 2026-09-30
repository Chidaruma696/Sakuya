# Dibuja un EAN-13 como SVG, sin gemas: tablas L/G/R del estándar y guardas 101 / 01010 / 101.
module BarcodeHelper
  L = %w[0001101 0011001 0010011 0111101 0100011 0110001 0101111 0111011 0110111 0001011].freeze
  G = %w[0100111 0110011 0011011 0100001 0011101 0111001 0000101 0010001 0001001 0010111].freeze
  R = %w[1110010 1100110 1101100 1000010 1011100 1001110 1010000 1000100 1001000 1110100].freeze
  PARIDAD = %w[LLLLLL LLGLGG LLGGLG LLGGGL LGLLGG LGGLLG LGGGLL LGLGLG LGLGGL LGGLGL].freeze

  # Los 95 módulos (0/1) de un EAN-13 válido.
  def ean13_modulos(codigo)
    raise ArgumentError, "EAN-13 inválido: #{codigo}" unless Barcode.valido?(codigo)
    d = codigo.chars.map(&:to_i)
    izquierda = PARIDAD[d[0]].chars.each_with_index.map { |p, i| (p == "L" ? L : G)[d[i + 1]] }.join
    derecha = d[7, 6].map { |n| R[n] }.join
    "101#{izquierda}01010#{derecha}101"
  end

  def ean13_svg(codigo, alto: 40, modulo: 2, texto: true)
    bits = ean13_modulos(codigo)
    margen = 9 * modulo
    ancho = bits.length * modulo + margen * 2
    alto_total = texto ? alto + 12 : alto
    barras = bits.chars.each_with_index.filter_map do |b, i|
      next unless b == "1"
      x = margen + i * modulo
      guarda = i < 3 || (45..49).cover?(i) || i > 91
      %(<rect x="#{x}" y="0" width="#{modulo}" height="#{guarda || !texto ? alto + 6 : alto}" fill="#000"/>)
    end.join
    etiqueta = texto ? %(<text x="#{ancho / 2}" y="#{alto + 11}" font-family="monospace" font-size="10" text-anchor="middle">#{codigo}</text>) : ""
    tag.svg(viewBox: "0 0 #{ancho} #{alto_total}", width: ancho, height: alto_total, xmlns: "http://www.w3.org/2000/svg") { (barras + etiqueta).html_safe }
  end
end
