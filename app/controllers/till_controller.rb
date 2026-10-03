class TillController < ApplicationController
  tab :till

  before_action :load_shift

  # ---- selling
  # With ?order=ID, the ticket arrives prefilled with the order's lines and its customer.
  def index
    authorize!("till.sell")
    @key = SecureRandom.uuid
    return unless params[:order].present? && Features.active?("customers")
    @order = Order.still_open.where(branch: current_branch).includes(lines: :product).find_by(id: params[:order])
    return unless @order
    @pos_order = { id: @order.id, folio: @order.folio, customer_id: @order.customer_id,
                    lines: @order.lines.filter_map { |l| pos_data(l.product)&.merge(quantity: l.quantity.to_f) } }
  end

  # What was scanned or typed, for the ticket (JSON).
  def scan
    authorize!("till.sell")
    r = Scan.resolve(params[:code])
    return render json: { error: t("errors.till.not_found", code: params[:code]) }, status: :not_found unless r
    data = pos_data(r.product)
    return render json: { error: t("errors.till.no_price", product: r.product.name, branch: current_branch.name) }, status: :unprocessable_entity unless data
    render json: data
  end

  # The branch catalog, so the till can store it and keep selling offline: the same data a
  # scan returns, for every product with a price, with its barcodes.
  def catalog
    authorize!("till.sell")
    codes = ProductBarcode.pluck(:product_id, :code).group_by(&:first).transform_values { |cs| cs.map(&:last) }
    products = Product.active.order(:name).filter_map do |p|
      data = pos_data(p) or next
      data.merge(key: p.key, plu: p.plu, codes: codes.fetch(p.id, []))
    end
    render json: { branch_id: current_branch.id, generated: Time.current.iso8601, products: products }
  end

  # A fresh token to upload what was sold offline (the cached page carries a stale one).
  def token
    authorize!("till.sell")
    render json: { token: form_authenticity_token }
  end

  def checkout
    authorize!("till.sell")
    lines = JSON.parse(params[:lines].to_s).map { |l| l.symbolize_keys.slice(:product_id, :quantity, :price_cents) }
    payments = JSON.parse(params[:payments].to_s).map(&:symbolize_keys)
    sold_at = sold_offline
    authorizes = authorizer_or_review("till.lower_price")
    # Prices are judged by the price rule inside Till: what it stops is not charged, and what
    # asks for review is charged and left for review.
    customer = Customer.active.find_by(id: params[:customer_id]) if params[:customer_id].present? && Features.active?("customers")
    order = Order.still_open.where(branch: current_branch).find_by(id: params[:order_id]) if params[:order_id].present?
    sale = Till.checkout!(branch: current_branch, user: current_user, lines: lines, payments: payments, key: params[:key], authorizer: authorizes,
                         customer: customer, order: order, sold_at: sold_at)
    order&.deliver!(sale)
    render json: { url: till_ticket_path(sale, print: 1), folio: sale.folio, change: Money.format_money(sale.change_cents) }
  rescue Till::Error, JSON::ParserError, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def sales
    authorize!("till.sell")
    @sales = Sale.where(branch: current_branch).includes(:user, :payments, lines: :product).recent.limit(100)
  end

  def ticket
    authorize!("till.sell")
    @sale = Sale.where(branch: current_branch).includes(:payments, :user, lines: :product).find(params[:id])
    @thermal = { mode: current_branch.printer, escpos: till_escpos_path(@sale), print: till_print_path(@sale) }
    render layout: "ticket"
  end

  # The same ticket as ESC/POS bytes, for a thermal printer.
  def escpos
    authorize!("till.sell")
    sale = Sale.where(branch: current_branch).find(params[:id])
    send_data EscPos.ticket(sale), filename: "#{sale.folio}.bin", type: "application/octet-stream", disposition: params[:download] ? "attachment" : "inline"
  end

  # Prints the ticket on the branch's network thermal printer (JSON: ok or the error).
  def print
    authorize!("till.sell")
    print_on_network(EscPos.ticket(Sale.where(branch: current_branch).find(params[:id])))
  end

  # The shift summary as ESC/POS, and on the network thermal printer.
  def summary_escpos
    shift = shift_for_summary
    send_data EscPos.summary(shift), filename: "#{shift.folio}.bin", type: "application/octet-stream", disposition: params[:download] ? "attachment" : "inline"
  end

  def summary_print
    print_on_network(EscPos.summary(shift_for_summary))
  end

  # ---- shift
  def shift
    authorize!("till.open")
    @shifts = Shift.where(branch: current_branch).where(status: "closed").includes(:user).order(closed_at: :desc).limit(15)
  end

  def open
    authorize!("till.open")
    Shift.open!(branch: current_branch, user: current_user, float_cents: Money.cents(params[:float]))
    redirect_to till_path, notice: t("till.notices.open", float: Money.format_money(Money.cents(params[:float])))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to till_shift_path, alert: e.message
  end

  # Counted by bills and coins (denomination[cents] = how many) or the total is typed. The
  # difference is judged by the shift rule (ShiftRule): if it asks for review a reason is required, and
  # if it rejects the shift does not close and the attempt is reported, unless someone with
  # till.difference closes it (then it is left for review).
  def close
    authorize!("till.open")
    raise ArgumentError, t("errors.till.no_till_simple") unless @shift
    breakdown = params.fetch(:denomination, {}).to_unsafe_h.select { |_, c| c.to_i.positive? }
    counted = breakdown.any? ? Shift.add_up(breakdown) : Money.cents(params[:counted])
    difference = counted - @shift.expected_cash_cents
    decision = ShiftRule.decide(@shift, counted_cents: counted, user: current_user)
    if decision.rejects? && !can?("till.difference")
      report_closing_stopped(counted, difference, decision)
      raise ArgumentError, t("errors.shift.rejected", reason: decision.reason)
    end
    authorizes = decision.allows? ? current_user : nil
    raise ArgumentError, t("errors.shift.missing_reason", reason: decision.reason) if authorizes.nil? && params[:reason].blank?
    # If the business rule crashed, the default one decided, and the failure is recorded in the shift review.
    reason = [ params[:reason], (t("shift_rule.failure", error: decision.error) if decision.error) ].compact_blank.join("\n")
    authorizes = nil if decision.error
    @shift.close!(counted_cents: counted, user: current_user, breakdown: breakdown)
    review_if_needed(@shift, authorizes, reason: reason, value_cents: difference.abs)
    notice = t("till.notices.closed_shift", folio: @shift.folio, expected: Money.format_money(@shift.expected_cents), counted: Money.format_money(@shift.counted_cents), difference: Money.format_money(@shift.difference_cents))
    redirect_to till_summary_path(@shift), notice: notice + (authorizes ? "" : t("till.notices.remains_pending_review"))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to till_shift_path, alert: e.message
  end

  # A shift's daily summary: what went through the till and around it, on an 80 mm sheet to
  # print or share. It comes up by itself on closing and stays in the shift list.
  def summary
    raise NotAllowed, "till.open" unless can?("till.open") || can?("reports.view")
    @summary_shift = Shift.where(branch: current_branch).includes(:user, :closed_by, withdrawals: :user).find(params[:id])
    @thermal = { mode: current_branch.printer, escpos: till_summary_escpos_path(@summary_shift), print: till_summary_print_path(@summary_shift) }
    sales = @summary_shift.paid_sales
    @tickets = sales.count
    @total = sales.sum(:total_cents)
    @by_payment_method = Payment.where(sale: sales).group(:payment_method).sum(:amount_cents)
    @top = SaleLine.where(sale: sales).joins(:product).group("products.name", "products.unit")
                     .order(Arel.sql("SUM(amount_cents) DESC")).limit(10).pluck("products.name", "products.unit", Arel.sql("SUM(quantity)"), Arel.sql("SUM(amount_cents)"))
    window = @summary_shift.opened_at..(@summary_shift.closed_at || Time.current)
    @reviews = Review.where(branch: current_branch, created_at: window).includes(:user)
    @charges = Charge.where(branch: current_branch, created_at: window).includes(:user)
    @title = "#{t("till.summary")} #{@summary_shift.folio}"
    render layout: "ticket"
  end

  # The withdrawal is judged by the withdrawal rule (WithdrawalRule): what it stops does not leave and
  # is reported, unless someone with till.withdraw takes it out (then it leaves and is left for review).
  def withdraw
    raise ArgumentError, t("errors.till.no_till_simple") unless @shift
    amount = Money.cents(params[:amount])
    @shift.check_withdrawal!(amount, params[:reason])
    decision = WithdrawalRule.decide(@shift, amount_cents: amount, reason: params[:reason], user: current_user)
    with_permission = can?("till.withdraw")
    if decision.rejects? && !with_permission
      report = [ t("till.withdrawal_stopped", amount: Money.format_money(amount), reason: params[:reason], rule: decision.reason), (t("withdrawal_rule.failure", error: decision.error) if decision.error) ].compact.join("\n")
      Review.open!(@shift, user: current_user, branch: current_branch, reason: report, value_cents: amount, stopped: true)
      raise ArgumentError, t("errors.till.withdrawal_stopped", reason: decision.reason)
    end
    review = decision.allows? && !decision.error ? nil : [ params[:reason], (decision.reason unless decision.allows?), (t("withdrawal_rule.failure", error: decision.error) if decision.error) ].compact.join("\n")
    withdrawal = @shift.withdraw!(amount_cents: amount, reason: params[:reason], user: current_user, authorized_by: (current_user if with_permission))
    Review.open!(withdrawal, user: current_user, branch: current_branch, reason: review, value_cents: withdrawal.amount_cents) if review
    redirect_to till_shift_path, notice: t("till.notices.withdrawal", amount: Money.format_money(withdrawal.amount_cents)) + (review ? t("till.notices.remains_pending_review") : "")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to till_shift_path, alert: e.message
  end

  # ---- refunds: only with a ticket
  def refund
    authorize!("till.refund")
    return if params[:code].blank?
    @sale = Sale.where(branch: current_branch).then { |v| v.find_by(code: Barcode.variants(params[:code])) || v.find_by(folio: params[:code].to_s.strip.upcase) }
    flash.now[:alert] = t("errors.till.no_ticket_refund", code: params[:code]) unless @sale
  end

  def create_refund
    authorize!("till.refund")
    sale = Sale.where(branch: current_branch).find(params[:sale_id])
    lines = params.fetch(:lines, {}).to_unsafe_h.map { |id, qty| { sale_line_id: id, quantity: qty } }.reject { |l| l[:quantity].blank? || l[:quantity].to_d <= 0 }
    refund = Till.refund!(sale: sale, lines: lines, reason: params[:reason].to_s.strip, user: current_user)
    redirect_to till_sales_path, notice: t("till.notices.refund", folio: refund.folio, amount: Money.format_money(refund.total_cents), sale: sale.folio)
  rescue Till::Error, ActiveRecord::RecordInvalid => e
    redirect_to till_refund_path(code: params[:code]), alert: e.message
  end

  private

  # The time the till sold while offline; valid from the last 7 days up to now.
  def sold_offline
    return if params[:sold_at].blank?
    time = Time.zone.iso8601(params[:sold_at].to_s)
    raise Till::Error, t("errors.till.sold_at_odd") unless time.between?(7.days.ago, 5.minutes.from_now)
    time
  rescue ArgumentError
    raise Till::Error, t("errors.till.sold_at_odd")
  end

  def shift_for_summary
    raise NotAllowed, "till.open" unless can?("till.open") || can?("reports.view")
    Shift.where(branch: current_branch).find(params[:id])
  end

  def print_on_network(bytes)
    Printer.deliver!(current_branch.network_printer, bytes)
    render json: { ok: true, notice: t("till.printed") }
  rescue Printer::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # What the till screen needs from a product to build its line; nil if it has no price here.
  def pos_data(p)
    catalog = p.price_cents_for(current_branch)
    return unless catalog.positive?
    promos = Promotion.applicable_to(p, current_branch).select(&:current?).map do |pr|
      { kind: pr.kind, minimum_quantity: pr.minimum_quantity, price_cents: pr.price_cents, percentage: pr.percentage, name: pr.name }
    end
    { product_id: p.id, name: p.name, unit: p.unit, decimals: p.decimals, price_cents: catalog, promotions: promos }
  end

  # A stopped closing is not lost: it goes to Review under the name of whoever counted.
  def report_closing_stopped(counted, difference, decision)
    text = t("till.closing_stopped", counted: Money.format_money(counted), difference: Money.format_money(difference), reason: decision.reason)
    text += "\n#{t("shift_rule.failure", error: decision.error)}" if decision.error
    Review.open!(@shift, user: current_user, branch: current_branch, reason: text, value_cents: difference.abs, stopped: true)
  end

  def load_shift
    @shift = Shift.opened_at(current_branch)
  end
end
