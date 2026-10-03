require "csv"

# The front page is the dashboard. Whoever cannot view reports sees a welcome page with what they can do.
class HomeController < ApplicationController
  include Dashboardable

  before_action :range, if: -> { can?("reports.view") }
  before_action(only: :sales) { authorize!("reports.view") }

  def index
    @pending_review = Review.pending.where(branch: current_branch.head_office? ? Branch.all : current_branch).count if can?("reviews.resolve")
    return render :welcome unless can?("reports.view")

    build_dashboard
  end

  def sales
    @rows = SaleLine.where(sale: range_sales).joins(:product).group("products.key", "products.name", "products.unit")
                       .order("products.name").pluck("products.key", "products.name", "products.unit", Arel.sql("SUM(quantity)"), Arel.sql("SUM(amount_cents)"), Arel.sql("COUNT(*)"))
    respond_to do |format|
      format.html
      format.csv do
        csv = CSV.generate(col_sep: ";") do |c|
          c << %w[key product unit quantity amount lines].map { |k| t("home.csv.#{k}") }
          @rows.each { |f| c << [ f[0], f[1], f[2], BigDecimal(f[3].to_s).round(3).to_s("F"), (f[4].to_i / 100.0).round(2), f[5] ] }
        end
        send_data csv, filename: "sales-#{@from}-#{@to}.csv", type: "text/csv"
      end
    end
  end
end
