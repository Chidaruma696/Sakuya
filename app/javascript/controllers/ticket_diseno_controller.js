import { Controller } from "@hotwired/stimulus"

// Diseño del ticket: lo que se escribe a la izquierda se ve al momento en la vista previa de la
// derecha (el ticket real dentro de un iframe, con sus mismos estilos).
export default class extends Controller {
  static targets = ["marco", "logo", "logoMini", "logoNada", "zoom"]

  get doc() { return this.marcoTarget.contentDocument }

  // Zoom de la vista previa: el papel se ve al tamaño que se quiera; al abrir, ajustado al ancho.
  // Imprime la muestra tal cual se ve: sirve para probar la impresora y el ancho del papel.
  imprimir() { this.marcoTarget.contentWindow?.print() }

  zoomMas() { this.ponerZoom((this.factor || 1) + 0.25) }
  zoomMenos() { this.ponerZoom((this.factor || 1) - 0.25) }
  zoomAjustar() {
    const papel = this.nodo("papel")
    if (!papel) return
    const disponible = this.marcoTarget.clientWidth - 24
    this.ponerZoom(Math.floor((disponible / papel.offsetWidth) * 20) / 20)
  }
  ponerZoom(factor) {
    this.factor = Math.min(Math.max(factor, 0.5), 4)
    const papel = this.nodo("papel")
    if (papel) papel.style.zoom = this.factor
    if (this.hasZoomTarget) this.zoomTarget.textContent = `${Math.round(this.factor * 100)} %`
  }

  nodo(clave) { return this.doc?.querySelector(`[data-ticket="${clave}"]`) }

  texto(e) {
    const n = this.nodo(e.target.dataset.clave)
    if (!n) return
    const v = e.target.value.trim()
    n.textContent = v || n.dataset.vacio || ""
    n.classList.toggle("oculto", !v && !n.dataset.vacio)
  }

  mostrar(e) {
    this.nodo(e.target.dataset.clave)?.classList.toggle("oculto", !e.target.checked)
  }

  ancho(e) {
    const mm = e.target.value === "58" ? 48 : 72
    const papel = this.nodo("papel")
    if (papel) papel.style.width = `${mm}mm`
    this.zoomAjustar()
  }

  logo(e) {
    const archivo = e.target.files[0]
    if (!archivo) return
    if (archivo.size > 300 * 1024) { alert(T.ticket.logo_grande); e.target.value = ""; return }
    const lector = new FileReader()
    lector.onload = () => this.ponerLogo(lector.result)
    lector.readAsDataURL(archivo)
  }

  quitarLogo() { this.ponerLogo("") }

  ponerLogo(dataUrl) {
    this.logoTarget.value = dataUrl
    this.logoMiniTarget.src = dataUrl || "data:,"
    this.logoMiniTarget.classList.toggle("hidden", !dataUrl)
    this.logoNadaTarget.classList.toggle("hidden", !!dataUrl)
    const n = this.nodo("logo")
    if (n) { n.querySelector("img").src = dataUrl || "data:,"; n.classList.toggle("oculto", !dataUrl) }
  }
}
