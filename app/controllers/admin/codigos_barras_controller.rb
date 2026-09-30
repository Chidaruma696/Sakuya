module Admin
  class CodigosBarrasController < BaseController
    before_action { autorizar!("admin.catalogo") }

    # Desde la ficha del producto en Admin.
    def create
      producto = Producto.find(params[:producto_id])
      codigo = producto.codigos_barras.build(codigo: params[:codigo])
      if codigo.save
        respond_to do |format|
          format.html { redirect_to edit_admin_producto_path(producto), notice: t("admin.avisos.codigo_agregado", codigo: codigo.codigo) }
          format.json { render json: { id: codigo.id, codigo: codigo.codigo } }
        end
      else
        respond_to do |format|
          format.html { redirect_to edit_admin_producto_path(producto), alert: codigo.errors.full_messages.join(", ") }
          format.json { render json: { error: codigo.errors.full_messages.join(", ") }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      producto = Producto.find(params[:producto_id])
      producto.codigos_barras.find(params[:id]).destroy!
      respond_to do |format|
        format.html { redirect_to edit_admin_producto_path(producto), notice: t("admin.avisos.codigo_quitado") }
        format.json { head :no_content }
      end
    end
  end
end
