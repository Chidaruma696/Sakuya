# The Purchases operations, each one in a transaction with the supplier locked: receive, invoice,
# link, pay, void and cancel. The rules live here; the controllers only call them.
module Purchases
  class Error < ArgumentError; end

  # --- receipt: an inventory inflow with a supplier. `key` is the browser's idempotency key: if it
  # arrives twice, the same receipt is returned.
  def self.receive!(branch:, supplier:, user:, lines:, delivery_note: nil, invoice: nil, notes: nil, date: Date.current, key: nil)
    Receipt.transaction do
      if key.present? && (existing = Receipt.find_by(branch: branch, key: key))
        return existing
      end
      raise Error, I18n.t("errors.purchases.invoice_of_other") if invoice && invoice.supplier_id != supplier.id
      raise Error, I18n.t("errors.purchases.invoice_cancelled") if invoice&.cancelled?
      clean = lines.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:product_id].blank? || BigDecimal(l[:quantity].to_s.presence || "0") <= 0 }
      raise Error, I18n.t("errors.purchases.no_rows") if clean.empty?
      receipt = Receipt.create!(branch: branch, supplier: supplier, user: user, invoice: invoice, delivery_note: delivery_note.presence,
                                    notes: notes.presence, date: date, key: key.presence)
      clean.each do |l|
        product = Product.active.find(l[:product_id])
        line = receipt.lines.create!(product: product, quantity: l[:quantity], boxes: l[:boxes].to_i)
        Inventory.move!(branch: branch, product: product, kind: "inflow", quantity: line.quantity, user: user, reference: receipt,
                          reason: I18n.t("purchases.notices.inflow_reason", folio: receipt.folio, supplier: supplier.name), date: date)
      end
      receipt
    end
  end

  # Cancelling a receipt: the stock goes back out (if the goods are still there).
  def self.cancel_receipt!(receipt, reason:, user:)
    raise Error, I18n.t("errors.reason_required") if reason.blank?
    raise Error, I18n.t("errors.purchases.receipt_cancelled") unless receipt.registered?
    Receipt.transaction do
      receipt.lines.includes(:product).each do |l|
        Inventory.move!(branch: receipt.branch, product: l.product, kind: "adjustment_outflow", quantity: l.quantity, user: user,
                          reference: receipt, reason: I18n.t("purchases.notices.cancellation_reason", folio: receipt.folio, reason: reason))
      end
      receipt.update!(status: "cancelled", cancellation_reason: reason, invoice: nil)
    end
    receipt
  end

  # --- invoice: creates the debt. With lines the amount is derived; without lines the typed one is accepted.
  def self.invoice!(supplier:, branch:, user:, folio:, date:, lines: [], amount_cents: 0, due: nil, concept: nil)
    raise Error, I18n.t("errors.purchases.folio_required") if folio.blank?
    clean = lines.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:product_id].blank? || BigDecimal(l[:quantity].to_s.presence || "0") <= 0 }
    SupplierInvoice.transaction do
      supplier.lock!
      raise Error, I18n.t("errors.purchases.folio_repeated", folio: folio) if supplier.invoices.exists?(folio: folio.strip)
      due ||= (supplier.credit_days.positive? ? date + supplier.credit_days.days : nil)
      invoice = supplier.invoices.new(branch: branch, user: user, folio: folio.strip, date: date, due: due, concept: concept.presence, amount_cents: 1)
      clean.each do |l|
        invoice.lines.build(product: Product.find(l[:product_id]), quantity: l[:quantity], boxes: l[:boxes].to_i, price_cents: Money.cents(l[:price]))
      end
      invoice.amount_cents = clean.any? ? invoice.lines.sum { |x| Money.amount(x.quantity, x.price_cents) } : amount_cents.to_i
      raise Error, I18n.t("errors.purchases.zero_amount") unless invoice.amount_cents.positive?
      invoice.save!
      post!(supplier, kind: "charge", amount: invoice.amount_cents, delta: invoice.amount_cents, branch: branch, user: user,
               invoice: invoice, date: date, concept: I18n.t("purchases.notices.charge_invoice", folio: invoice.folio))
      invoice
    end
  end

  # Cancelling an invoice: only with no payments in force; the debt is reversed with an adjustment and the receipts are left unlinked.
  def self.cancel_invoice!(invoice, reason:, user:)
    raise Error, I18n.t("errors.reason_required") if reason.blank?
    raise Error, I18n.t("errors.purchases.invoice_already_cancelled") if invoice.cancelled?
    raise Error, I18n.t("errors.purchases.invoice_with_payments") if invoice.payments.in_force.exists?
    SupplierInvoice.transaction do
      invoice.supplier.lock!
      invoice.update!(status: "cancelled", cancellation_reason: reason)
      invoice.receipts.update_all(supplier_invoice_id: nil, updated_at: Time.current)
      post!(invoice.supplier, kind: "adjustment", amount: invoice.amount_cents, delta: -invoice.amount_cents, branch: invoice.branch, user: user,
               invoice: invoice, concept: I18n.t("purchases.notices.cancellation_invoice", folio: invoice.folio, reason: reason))
    end
    invoice
  end

  def self.link!(receipt, invoice)
    raise Error, I18n.t("errors.purchases.receipt_cancelled") unless receipt.registered?
    if invoice
      raise Error, I18n.t("errors.purchases.invoice_of_other") if invoice.supplier_id != receipt.supplier_id
      raise Error, I18n.t("errors.purchases.invoice_cancelled") if invoice.cancelled?
    end
    receipt.update!(invoice: invoice)
  end

  # --- payment: a single path. Cash comes out of the open drawer; linked to an invoice it cannot exceed what is left.
  def self.pay!(supplier:, branch:, user:, amount_cents:, payment_method: "cash", invoice: nil, reference: nil)
    amount = amount_cents.to_i
    raise Error, I18n.t("errors.purchases.zero_amount") unless amount.positive?
    raise Error, I18n.t("errors.till.unknown_payment_method", payment_method: payment_method) unless Payment::PAYMENT_METHODS.include?(payment_method)
    SupplierPayment.transaction do
      supplier.lock!
      if invoice
        raise Error, I18n.t("errors.purchases.invoice_of_other") if invoice.supplier_id != supplier.id
        raise Error, I18n.t("errors.purchases.invoice_cancelled") if invoice.cancelled?
        raise Error, I18n.t("errors.purchases.payment_exceeds", remaining: Money.format_money(invoice.remaining_cents)) if amount > invoice.remaining_cents
      elsif amount > supplier.balance_cents
        raise Error, I18n.t("errors.purchases.advance_exceeds", balance: Money.format_money(supplier.balance_cents))
      end
      shift = withdrawal = nil
      if payment_method == "cash"
        shift = Shift.opened_at(branch) or raise Error, I18n.t("errors.till.no_till_in", branch: branch.name)
        withdrawal = shift.withdraw!(amount_cents: amount, reason: I18n.t("purchases.notices.withdrawal_payment", supplier: supplier.name, folio: invoice&.folio), user: user, authorized_by: user)
      end
      payment = supplier.payments.create!(invoice: invoice, branch: branch, shift: shift, withdrawal: withdrawal, user: user, amount_cents: amount, payment_method: payment_method, reference: reference.presence)
      post!(supplier, kind: "payment", amount: amount, delta: -amount, branch: branch, user: user, invoice: invoice, payment: payment,
               concept: I18n.t("purchases.notices.supplier_payment", folio: invoice&.folio || "—", payment_method: I18n.t("payment_methods.#{payment_method}")))
      payment
    end
  end

  # Voiding a payment offsets it; the cash only goes back to the drawer if the shift is still open.
  def self.void_payment!(payment, reason:, user:)
    raise Error, I18n.t("errors.reason_required") if reason.blank?
    raise Error, I18n.t("errors.purchases.payment_already_voided") unless payment.current?
    SupplierPayment.transaction do
      payment.supplier.lock!
      withdrawal = payment.withdrawal
      raise Error, I18n.t("errors.purchases.closed_shift") if withdrawal && !Shift.still_open.exists?(id: payment.shift_id)
      payment.update!(status: "voided", void_reason: reason, voided_by: user, withdrawal: nil)
      withdrawal&.destroy!
      post!(payment.supplier, kind: "adjustment", amount: payment.amount_cents, delta: payment.amount_cents, branch: payment.branch, user: user,
               invoice: payment.invoice, payment: payment, concept: I18n.t("purchases.notices.void_payment", reason: reason))
    end
    payment
  end

  # --- invoiced vs received comparison, per product. A report, not a lock.
  Compared = Struct.new(:product, :invoiced, :received, keyword_init: true) do
    def difference = received - invoiced
    def status
      return "matches" if difference.abs <= BigDecimal("0.005")
      return "not_received" if received.zero?
      return "no_invoice" if invoiced.zero?
      difference.negative? ? "shortage" : "surplus"
    end
  end

  # Lines that invoice more than the receipts about to be linked brought in (before saving).
  # lines: [{ product_id:, quantity:, price: }]; returns Compared only for what goes over.
  def self.excess(lines, receipts)
    invoiced = lines.group_by { |l| l[:product_id].to_i }.transform_values { |ls| ls.sum { |l| BigDecimal(l[:quantity].to_s) } }
    received = ReceiptLine.where(receipt: receipts).group(:product_id).sum(:quantity)
    invoiced.filter_map do |product_id, qty|
      got = received[product_id] || 0
      Compared.new(product: Product.find(product_id), invoiced: qty, received: got) if qty - got > BigDecimal("0.005")
    end
  end

  def self.comparison(invoice)
    invoiced = invoice.lines.includes(:product).group_by(&:product).transform_values { |ls| ls.sum(&:quantity) }
    received = ReceiptLine.joins(:receipt).where(receipts: { supplier_invoice_id: invoice.id, status: "registered" }).includes(:product)
                             .group_by(&:product).transform_values { |ls| ls.sum(&:quantity) }
    (invoiced.keys | received.keys).sort_by(&:name).map { |p| Compared.new(product: p, invoiced: invoiced[p] || 0, received: received[p] || 0) }
  end

  def self.post!(supplier, kind:, amount:, delta:, branch:, user:, concept:, invoice: nil, payment: nil, date: Date.current)
    balance = supplier.movements.sum(:delta_cents) + delta
    supplier.movements.create!(kind: kind, amount_cents: amount, delta_cents: delta, balance_cents: balance, branch: branch, user: user,
                                  invoice: invoice, payment: payment, date: date, concept: concept)
  end
  private_class_method :post!
end
