# Tickets in ESC/POS, the language of thermal printers: the same ticket as on screen, but in bytes
# the printer understands without a driver. Text in the PC850 code page (accents, ñ, ¿, ¡);
# anything that does not fit in it comes out as a substitute. 32 columns on 58 mm paper, 48 on 80 mm.
module EscPos
  ESC = "\e".b
  GS = "\x1D".b

  class Document
    attr_reader :columns

    def initialize(columns:)
      @columns = columns
      @bytes = +"".b
      @bytes << ESC << "@" << ESC << "t" << 2.chr # reset and select PC850
    end

    def text(s)
      @bytes << encode(s) << "\n"
      self
    end

    def center = align(1)
    def left = align(0)

    def bold(on = true)
      @bytes << ESC << "E" << (on ? 1 : 0).chr
      self
    end

    # Double height and width, for the total.
    def large(on = true)
      @bytes << GS << "!" << (on ? 0x11 : 0).chr
      self
    end

    def line(character = "-") = text(character * columns)

    # Text on the left and figure on the right on the same line; if they do not fit, on two.
    def row(left, right, columns: self.columns)
      left = left.to_s
      right = right.to_s
      return text(left + (" " * (columns - left.length - right.length)) + right) if left.length + right.length < columns
      text(left)
      text(right.rjust(columns))
    end

    # EAN-13 barcode with the digits underneath.
    def ean13(code)
      digits = code.to_s.gsub(/\D/, "")
      return self unless digits.length == 13
      @bytes << GS << "h" << 60.chr << GS << "w" << 2.chr << GS << "H" << 2.chr << GS << "k" << 67.chr << 13.chr << digits << "\n"
      self
    end

    # The ticket logo (data URL from Settings › Ticket) as a black and white raster image, 30 mm wide
    # as on screen. If the image cannot be read, the ticket comes out without a logo.
    def image(data_url)
      raster = EscPos.raster(data_url) or return self
      bytes_per_row, height, dots = raster
      @bytes << GS << "v0" << 0.chr << [ bytes_per_row, height ].pack("v2") << dots
      self
    end

    # Feeds the paper and cuts (partially, so the ticket does not fall).
    def cut
      @bytes << ESC << "d" << 3.chr << GS << "V" << 66.chr << 0.chr
      self
    end

    def to_s = @bytes

    private

    def align(n)
      @bytes << ESC << "a" << n.chr
      self
    end

    def encode(s)
      s.to_s.gsub("€", "EUR").gsub(/[−–—]/, "-").encode("CP850", undef: :replace, invalid: :replace, replace: "?").b
    end
  end

  LOGO_DOTS = 240 # 30 mm at 8 dots per mm

  # [bytes per row, height, dots] of a data URL, or nil. Computed once per logo.
  def self.raster(data_url)
    return if data_url.blank?
    @rasters ||= {}
    key = Digest::SHA256.hexdigest(data_url)
    return @rasters[key] if @rasters.key?(key)
    @rasters.clear if @rasters.size > 8
    @rasters[key] = rasterize(Base64.decode64(data_url.split(",", 2).last.to_s))
  end

  def self.rasterize(binary)
    img = Vips::Image.new_from_buffer(binary, "")
    img = img.flatten(background: 255) if img.has_alpha?
    img = img.colourspace(:b_w)
    img = img.resize(LOGO_DOTS.to_f / img.width) if img.width > LOGO_DOTS
    width = img.width
    bytes_per_row = (width + 7) / 8
    pixels = img.cast(:uchar).write_to_memory.bytes
    dots = img.height.times.flat_map do |y|
      bytes_per_row.times.map do |b|
        8.times.sum { |i| x = b * 8 + i; x < width && pixels[y * width + x] < 128 ? (0x80 >> i) : 0 }
      end
    end
    [ bytes_per_row, img.height, dots.pack("C*") ]
  rescue Vips::Error
    nil
  end
  private_class_method :rasterize

  # A shift's day summary, like the sheet on screen: what went through the till, the count and the
  # best sellers.
  def self.summary(c)
    d = Document.new(columns: Setting.integer("ticket.width") == 58 ? 32 : 48)
    money = ->(cents) { Money.format_money(cents) }
    sales = c.paid_sales
    d.center.bold.text(I18n.t("till.summary").upcase).bold(false)
    d.text("#{c.branch} · #{I18n.t("till.shift")} #{c.folio}")
    d.text("#{I18n.l(c.opened_at, format: :short)} -> #{c.closed_at ? I18n.l(c.closed_at, format: :short) : I18n.t("statuses.open")}")
    d.text("#{I18n.t("till.cashier")}: #{c.user}")
    d.left.line
    d.row("#{I18n.t("till.sales")} (#{sales.count})", money.(sales.sum(:total_cents)))
    Payment.where(sale: sales).group(:payment_method).sum(:amount_cents).each { |payment_method, amount| d.row("  #{I18n.t("payment_methods.#{payment_method}")}", money.(amount)) }
    d.row(I18n.t("till.refunds"), "-#{money.(c.refunds_cents)}") if c.refunds_cents.positive?
    d.row(I18n.t("till.account_payments"), money.(c.account_payments.sum(:amount_cents))) if c.account_payments.any?
    d.row(I18n.t("till.withdrawals"), "-#{money.(c.withdrawals_cents)}") if c.withdrawals_cents.positive?
    d.line
    d.row(I18n.t("till.float"), money.(c.float_cents))
    d.row(I18n.t("till.expected"), money.(c.expected_cents || c.expected_cash_cents))
    if c.counted_cents
      d.row(I18n.t("till.counted"), money.(c.counted_cents))
      d.bold.row(I18n.t("till.difference"), money.(c.difference_cents)).bold(false)
    end
    top = SaleLine.where(sale: sales).joins(:product).group("products.name").order(Arel.sql("SUM(amount_cents) DESC")).limit(10).sum(:amount_cents)
    if top.any?
      d.line(".")
      d.bold.text(I18n.t("home.best_sellers")).bold(false)
      top.each { |name, amount| d.row(name, money.(amount)) }
    end
    d.cut.to_s
  end

  # A sale's ticket, with the same data and settings as the one on screen.
  def self.ticket(sale)
    a = Setting.to_h
    d = Document.new(columns: Setting.integer("ticket.width") == 58 ? 32 : 48)
    d.center.image(a["ticket.logo"])
    d.bold.text(a["business.name"].presence || sale.branch&.name).bold(false)
    [ a["ticket.tagline"], (sale.branch&.name if a["business.name"].present? && sale.branch&.name != a["business.name"]),
      a["business.address"], a["business.phone"], a["ticket.tax_id"] ].compact_blank.each { |l| d.text(l) }
    d.left.line
    d.row("#{I18n.t("common.date")}: #{I18n.l(sale.created_at, format: :short)}", "")
    d.bold.text("#{I18n.t("common.folio")}: #{sale.folio}").bold(false)
    d.text("#{I18n.t("till.served_by")}: #{sale.user&.name}") if a["ticket.show_cashier"] == "1"
    d.text("#{I18n.t("till.customer")}: #{sale.customer.name}") if sale.customer
    d.line
    sale.lines.includes(:product, :promotion).each do |l|
      name = l.product.name
      name += " (#{l.promotion.name})" if l.promotion
      name += " *" if l.price_cents < l.catalog_cents
      d.text(name)
      d.row("  #{ApplicationController.helpers.quantity(l.quantity, l.product)} x #{Money.format_money(l.price_cents)}", Money.format_money(l.amount_cents))
    end
    d.line
    d.bold.large.row(I18n.t("common.total").upcase, Money.format_money(sale.total_cents), columns: d.columns / 2).large(false).bold(false)
    sale.payments.each { |p| d.row(I18n.t("payment_methods.#{p.payment_method}"), Money.format_money(p.amount_cents)) }
    d.row(I18n.t("till.change"), Money.format_money(sale.change_cents))
    d.center.bold.text(I18n.t("sale_statuses.refunded").upcase).bold(false) if sale.status == "refunded"
    d.line(".")
    d.text(a["ticket.returns_legend"].presence || I18n.t("till.refunds_only_with_ticket"))
    d.ean13(sale.code) if a["ticket.show_code"] == "1"
    d.text(a["business.ticket_footer"]) if a["business.ticket_footer"].present?
    d.cut.to_s
  end
end
