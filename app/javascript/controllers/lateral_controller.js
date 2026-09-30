import { Controller } from "@hotwired/stimulus"

// En pantalla angosta la cinta se vuelve una barra lateral: este controlador la abre y la cierra
// (botón de menú, fondo oscuro, Escape).
export default class extends Controller {
  static targets = [ "panel", "fondo" ]

  connect() { this.tecla = e => { if (e.key === "Escape") this.cerrar() }; document.addEventListener("keydown", this.tecla) }
  disconnect() { document.removeEventListener("keydown", this.tecla) }

  abrir() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.fondoTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  cerrar() {
    this.panelTarget.classList.add("-translate-x-full")
    this.fondoTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  alternar() { this.panelTarget.classList.contains("-translate-x-full") ? this.abrir() : this.cerrar() }
}
