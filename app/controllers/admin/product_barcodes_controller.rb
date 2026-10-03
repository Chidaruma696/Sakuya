module Admin
  class ProductBarcodesController < BaseController
    before_action { authorize!("admin.catalog") }

    # From the product page in Admin.
    def create
      product = Product.find(params[:product_id])
      code = product.product_barcodes.build(code: params[:code])
      if code.save
        respond_to do |format|
          format.html { redirect_to edit_admin_product_path(product), notice: t("admin.notices.code_added", code: code.code) }
          format.json { render json: { id: code.id, code: code.code } }
        end
      else
        respond_to do |format|
          format.html { redirect_to edit_admin_product_path(product), alert: code.errors.full_messages.join(", ") }
          format.json { render json: { error: code.errors.full_messages.join(", ") }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      product = Product.find(params[:product_id])
      product.product_barcodes.find(params[:id]).destroy!
      respond_to do |format|
        format.html { redirect_to edit_admin_product_path(product), notice: t("admin.notices.code_removed") }
        format.json { head :no_content }
      end
    end
  end
end
