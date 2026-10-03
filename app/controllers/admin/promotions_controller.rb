module Admin
  class PromotionsController < BaseController
    before_action { authorize!("admin.catalog") }
    before_action :load_record, only: %i[edit update destroy]

    def index
      @promotions = Promotion.includes(:product, :branch).order(active: :desc, created_at: :desc)
    end

    def new
      @promotion = Promotion.new(kind: "price", active: true)
    end

    def create
      @promotion = Promotion.new(allowed)
      save(@promotion, admin_promotions_path, t("admin.notices.created", what: t("admin.models.promotion")))
    end

    def edit
    end

    def update
      @promotion.assign_attributes(allowed)
      save(@promotion, admin_promotions_path, t("admin.notices.saved", what: t("admin.models.promotion")))
    end

    def destroy
      @promotion.destroy!
      redirect_to admin_promotions_path, notice: t("admin.notices.deleted", what: t("admin.models.promotion"))
    rescue ActiveRecord::RecordNotDestroyed
      redirect_to admin_promotions_path, alert: t("admin.notices.already_used", what: t("admin.models.promotion"))
    end

    private

    def load_record
      @promotion = Promotion.find(params[:id])
    end

    def allowed
      p = params.require(:promotion).permit(:name, :product_id, :branch_id, :kind, :price, :percentage, :minimum_quantity, :from, :to, :active)
      p[:price_cents] = Money.cents(p.delete(:price)) if p.key?(:price)
      p[:branch_id] = nil if p[:branch_id].blank?
      p[:minimum_quantity] = 0 if p[:minimum_quantity].blank?
      p
    end
  end
end
