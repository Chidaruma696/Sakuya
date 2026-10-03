# The supplier invoice hook: before creating the debt, a rule in Sakuya's Lisp compares what was
# invoiced with what came in on the linked receipts, and decides.
#
# Contract v1. It gets (excess-items) how many products came in excess, (excess-value) what the
# excess is worth at the invoice price, in money, (total) the invoice total, (receipts) how many
# receipts are linked, (supplier) the supplier's name, (lock) whether the lock in Settings ›
# Purchases is on and (authorized), true if whoever enters the invoice has purchases.exceed.
# Returns (allow), (to-review reason) or (reject reason).
module InvoiceRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; A supplier invoice, compared with the receipts it is linked to.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; With the lock from Settings › Purchases, invoicing more than was received stops.
    (if (or (not (lock)) (= (excess-items) 0))
        (allow)
        (reject :over-received))
  LISP

  REASONS = %i[over-received].freeze
  FUNCTIONS = %w[excess-items excess-value total receipts supplier lock authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((= (excess-items) 0) (allow))
          ((<= (excess-value) 100) (to-review "Small excess"))
          (else (reject :over-received)))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_invoice".freeze # the editor's test case

  Input = Data.define(:excess_items, :excess_value, :total, :receipts, :supplier, :lock, :authorized, :detail)

  def self.decide(data, code: Rule.current("invoice")&.code)
    decide_with(code, data)
  end

  def self.lock? = Setting["purchases.lock_received"] == "1"

  # The editor's test case: how many products in excess, what they are worth, the total and whether
  # someone with permission enters the invoice. The lock is the one in Settings › Purchases.
  def self.scenario(params, _branch)
    folio = params[:invoice].to_s.strip.presence
    { excess_items: params[:excess_items].presence&.to_i || 1, excess_value: params[:excess_value].present? ? Money.cents(params[:excess_value]) : 15_000,
      total: params[:total].present? ? Money.cents(params[:total]) : 450_000, authorized: params[:authorized] == "1",
      invoice_folio: folio, invoice: (SupplierInvoice.where(folio: folio).order(id: :desc).first if folio) }
  end

  # With a real invoice, compares it with its linked receipts, as when it is recorded.
  def self.dry_run(code, scenario)
    raise Lisp::Error, I18n.t("invoice_rule.invoice_not_found", folio: scenario[:invoice_folio]) if scenario[:invoice_folio] && !scenario[:invoice]
    return evaluate(code, data_for(scenario[:invoice], scenario[:authorized])) if scenario[:invoice]
    evaluate(code, Input.new(excess_items: scenario[:excess_items], excess_value: scenario[:excess_value], total: scenario[:total], receipts: 1,
                              supplier: "", lock: lock?, authorized: scenario[:authorized], detail: ""))
  end

  def self.data_for(invoice, authorized)
    lines = invoice.lines.map { |l| { product_id: l.product_id, quantity: l.quantity } }
    excess = Purchases.excess(lines, invoice.receipts.to_a)
    value = excess.sum { |e| Money.amount(-e.difference, invoice.lines.select { |l| l.product_id == e.product.id }.map(&:price_cents).max.to_i) }
    Input.new(excess_items: excess.size, excess_value: value, total: invoice.amount_cents, receipts: invoice.receipts.size,
              supplier: invoice.supplier.name, lock: lock?, authorized: authorized, detail: excess.map { |e| e.product.name }.join(", "))
  end

  def self.texts = "invoice_rule"

  def self.interpolate(data) = { detail: data.detail }

  def self.functions(data)
    {
      "excess-items" => -> { data.excess_items },
      "excess-value" => -> { BigDecimal(data.excess_value) / 100 },
      "total" => -> { BigDecimal(data.total) / 100 },
      "receipts" => -> { data.receipts },
      "supplier" => -> { data.supplier },
      "lock" => -> { data.lock },
      "authorized" => -> { data.authorized }
    }
  end

  private_class_method :functions, :interpolate, :texts, :data_for
end
