import { Controller } from "@hotwired/stimulus"

// Toast de avisos: los verdes se van solos a los 6 s, los rojos se quedan hasta cerrarlos.
export default class extends Controller {
  static targets = ["aviso"]

  connect() {
    this.temporizadores = this.avisoTargets
      .filter(a => a.classList.contains("bg-green-50"))
      .map(a => setTimeout(() => this.quitar(a), 6000))
  }

  disconnect() { this.temporizadores?.forEach(clearTimeout) }

  cerrar(e) { this.quitar(e.currentTarget.closest("[data-aviso-target]")) }

  quitar(aviso) {
    if (!aviso) return
    aviso.style.transition = "opacity .3s"
    aviso.style.opacity = "0"
    setTimeout(() => aviso.remove(), 300)
  }
}
