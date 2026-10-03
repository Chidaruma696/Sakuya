# Exportar e importar todas las reglas del negocio en un archivo, en Ajustes › Opciones avanzadas.
class ArchivoReglasController < ApplicationController
  before_action { autorizar!("reglas.editar") }

  def show
    @vigentes = Regla::GANCHOS.filter_map { |g| Regla.vigente(g) }
  end

  def exportar
    texto = ArchivoReglas.exportar(negocio: Ajuste["negocio.nombre"].presence || sucursal_actual.nombre)
    send_data texto, filename: "sakuya-reglas-#{Date.current}.lisp", type: "text/plain; charset=utf-8"
  end

  def importar
    archivo = params[:archivo]
    return redirect_to(archivo_reglas_path, alert: t("reglas.archivo.sin_archivo")) unless archivo.respond_to?(:read)
    tocados = ArchivoReglas.importar!(archivo.read.force_encoding("UTF-8"), usuario: usuario_actual)
    aviso = tocados.any? ? t("reglas.archivo.importadas", ganchos: tocados.map { |g| t("ajustes.secciones.#{g == "tablero" ? g : "regla_#{g}"}") }.join(", ")) : t("reglas.archivo.sin_cambios")
    redirect_to archivo_reglas_path, notice: aviso
  rescue Lisp::Error => e
    redirect_to archivo_reglas_path, alert: t("reglas.archivo.no_se_importo", error: e.message)
  end
end
