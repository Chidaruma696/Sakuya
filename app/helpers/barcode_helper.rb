# Draws an EAN-13 as SVG, without gems: the standard's L/G/R tables and 101 / 01010 / 101 guards.
module BarcodeHelper
  L = %w[0001101 0011001 0010011 0111101 0100011 0110001 0101111 0111011 0110111 0001011].freeze
  G = %w[0100111 0110011 0011011 0100001 0011101 0111001 0000101 0010001 0001001 0010111].freeze
  R = %w[1110010 1100110 1101100 1000010 1011100 1001110 1010000 1000100 1001000 1110100].freeze
  PARITY = %w[LLLLLL LLGLGG LLGGLG LLGGGL LGLLGG LGGLLG LGGGLL LGLGLG LGLGGL LGGLGL].freeze

  # The 95 modules (0/1) of a valid EAN-13.
  def ean13_modules(code)
    raise ArgumentError, "invalid EAN-13: #{code}" unless Barcode.valid?(code)
    d = code.chars.map(&:to_i)
    left = PARITY[d[0]].chars.each_with_index.map { |p, i| (p == "L" ? L : G)[d[i + 1]] }.join
    right = d[7, 6].map { |n| R[n] }.join
    "101#{left}01010#{right}101"
  end

  def ean13_svg(code, height: 40, module_width: 2, text: true)
    bits = ean13_modules(code)
    margin = 9 * module_width
    width = bits.length * module_width + margin * 2
    height_total = text ? height + 12 : height
    bar = bits.chars.each_with_index.filter_map do |b, i|
      next unless b == "1"
      x = margin + i * module_width
      guard = i < 3 || (45..49).cover?(i) || i > 91
      %(<rect x="#{x}" y="0" width="#{module_width}" height="#{guard || !text ? height + 6 : height}" fill="#000"/>)
    end.join
    label = text ? %(<text x="#{width / 2}" y="#{height + 11}" font-family="monospace" font-size="10" text-anchor="middle">#{code}</text>) : ""
    tag.svg(viewBox: "0 0 #{width} #{height_total}", width: width, height: height_total, xmlns: "http://www.w3.org/2000/svg") { (bar + label).html_safe }
  end
end
