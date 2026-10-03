module Admin
  class BranchesController < BaseController
    before_action { authorize!("admin.users") }
    before_action :load_record, only: %i[edit update]

    def index
      @branches = Branch.order(:name)
    end

    def new
      @branch = Branch.new(kind: "store", active: true)
    end

    def create
      @branch = Branch.new(allowed)
      save(@branch, admin_branches_path, t("admin.notices.created", what: t("admin.models.branch")))
    end

    def edit
    end

    def update
      @branch.assign_attributes(allowed)
      save(@branch, admin_branches_path, t("admin.notices.saved", what: t("admin.models.branch")))
    end

    private

    def load_record
      @branch = Branch.find(params[:id])
    end

    def allowed
      p = params.require(:branch).permit(:code, :name, :kind, :active, :cash_limit, :count_interval_days, :printer, :network_printer)
      p[:code] = p[:code].to_s.strip.upcase
      p[:cash_limit_cents] = Money.cents(p.delete(:cash_limit)) if p.key?(:cash_limit)
      p
    end
  end
end
