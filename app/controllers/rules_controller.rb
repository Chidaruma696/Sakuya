# The editor for the rules that decide (closing the till, the price…), under Settings › Advanced
# options. Same as the dashboard one: trying does not save; saving records a new version only
# if the rule decides something with the test scenario; restoring records an old one again. Each
# hook provides its test scenario (see `scenario` and `dry_run` in its module).
class RulesController < ApplicationController
  HOOKS = { "shift" => ShiftRule, "price" => PriceRule, "withdrawal" => WithdrawalRule, "movement" => MovementRule, "invoice" => InvoiceRule, "receipt" => ReceiptRule, "sale" => SaleRule, "credit" => CreditRule }.freeze

  before_action { authorize!("rules.edit") }
  before_action :load_record

  def edit
    @code = Rule.current(@hook)&.code.presence || @rule_module::DEFAULT
  end

  # "Try" and "Save" post to the same URL, as in the dashboard; trying carries dry_run=1.
  def save
    @code = params[:code].to_s
    result = dry_run(@code)
    @decisions = effective(result.is_a?(Array) ? result : [ [ nil, result, @scenario[:authorized] ] ]) if result
    return render(:edit, status: @program_error ? :unprocessable_entity : :ok) if params[:dry_run].present? || @program_error
    Rule.create!(hook: @hook, code: @code, user: current_user)
    redirect_to rule_edit_path(@hook), notice: t("rules.notices.saved")
  rescue ActiveRecord::RecordInvalid => e
    @program_error = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end

  def restore
    old = Rule.for_hook(@hook).find(params[:id])
    Rule.create!(hook: @hook, code: old.code, version: old.version, user: current_user)
    redirect_to rule_edit_path(@hook), notice: t("rules.notices.restored", date: l(old.created_at, format: :short))
  end

  private

  def load_record
    @hook = params[:hook]
    @rule_module = HOOKS.fetch(@hook)
    @scenario = @rule_module.scenario(params, current_branch)
    @versions = Rule.for_hook(@hook).includes(:user).limit(15)
  end

  # What would really happen: the core never blocks someone who has the permission, so for that
  # person a stop means a review. Returns [label, decision, whether the permission changed it].
  def effective(list)
    list.map do |label, decision, authorized|
      by_permission = decision.rejects? && authorized
      [ label, by_permission ? decision.with(verdict: :review) : decision, by_permission ]
    end
  end

  def dry_run(code)
    @rule_module.dry_run(code, @scenario)
  rescue Lisp::Error => e
    @program_error = e.message
    nil
  end
end
