module Admin
  class ProductsController < BaseController
    before_action { authorize!("admin.catalog") }
    before_action :load_record, only: %i[edit update]

    def index
      @products = Product.order(:name).includes(:product_barcodes)
      @products = @products.where("name LIKE :q OR key LIKE :q", q: "%#{params[:q]}%") if params[:q].present?
    end

    def new
      @product = Product.new(unit: "kg")
    end

    def create
      @product = Product.new(allowed)
      save(@product, -> { edit_admin_product_path(@product) }, t("admin.notices.created", what: t("admin.models.product")))
    end

    def edit
    end

    def update
      @product.assign_attributes(allowed)
      Product.transaction do
        params.fetch(:prices, {}).each { |branch_id, price| @product.set_price!(Branch.find(branch_id), price) } if @product.valid?
        save(@product, admin_products_path, t("admin.notices.saved", what: t("admin.models.product")))
      end
    end

    private

    def load_record
      @product = Product.find(params[:id])
    end

    def allowed
      p = params.require(:product).permit(:key, :name, :line, :unit, :price, :plu, :active)
      p[:key] = p[:key].to_s.strip.upcase if p.key?(:key)
      p[:plu] = nil if p.key?(:plu) && p[:plu].blank?
      p
    end
  end
end
