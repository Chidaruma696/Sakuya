# What the Home dashboard needs to render, shared with its editor (which uses it as a preview):
# the date range, the branches and each panel's data.
module Dashboardable
  extend ActiveSupport::Concern

  private

  def range
    @from = (Date.parse(params[:from]) rescue Date.current)
    @to = (Date.parse(params[:to]) rescue Date.current)
    @from, @to = @to, @from if @from > @to
    @all = current_branch.head_office? && params[:branch_id] == "all"
    @branch = if current_branch.head_office? && params[:branch_id].present? && !@all
      Branch.find(params[:branch_id])
    else
      current_branch
    end
  end

  def branches
    @all ? Branch.all : [ @branch ]
  end

  def range_sales
    Sale.where(branch: branches, business_date: @from..@to)
  end

  # Builds the dashboard with a program (the one in force if none is given) and loads the panel data. With
  # `sample`, everything comes from made-up test data (only for the editor preview).
  def build_dashboard(code: Rule.current("dashboard")&.code, sample: false)
    return build_sample(code) if sample
    data = Dashboard::Input.new(branches: branches, from: @from, to: @to, can_review: can?("reviews.resolve"))
    @pieces, @dashboard_error = Dashboard.build(data, code: code)
    day = @from.beginning_of_day..@to.end_of_day
    @top = SaleLine.where(sale: data.range_sales).joins(:product).group("products.name", "products.unit")
                     .order(Arel.sql("SUM(amount_cents) DESC")).limit(50).pluck("products.name", "products.unit", Arel.sql("SUM(quantity)"), Arel.sql("SUM(amount_cents)"))
    @shifts = Shift.where(branch: branches, status: "closed", closed_at: day).includes(:branch, :user).order(closed_at: :desc)
    @stock_counts = StockCount.where(branch: branches, status: "closed", closed_at: day).includes(:branch, :responsible)
    @count_due = branches.select { |s| StockCount.overdue?(s) }
  end

  ShiftRow = Struct.new(:folio, :branch, :user, :expected_cents, :difference_cents)
  StockCountRow = Struct.new(:folio, :branch, :responsible, :shortage_cents, :surplus_cents)

  # The sample lists use the catalog's products, so it looks like the actual business.
  def build_sample(code)
    @sample = true
    @pieces, @dashboard_error = Dashboard.build(Dashboard::Sample.new(from: @from, to: @to), code: code)
    products = Product.active.order(:name).limit(8).to_a
    @top = products.each_with_index.map do |p, i|
      quantity = BigDecimal((8 - i) * 6 + 3)
      [ p.name, p.unit, quantity, (quantity * p.price_cents).round.to_i ]
    end.sort_by { |f| -f[3] }
    @shifts = [ ShiftRow.new("C-00041", @branch, current_user, 1_245_000, -2_000), ShiftRow.new("C-00040", @branch, current_user, 980_050, 0) ]
    @stock_counts = [ StockCountRow.new("K-00007", @branch, current_user, 12_900, 4_200) ]
    @count_due = []
  end
end
