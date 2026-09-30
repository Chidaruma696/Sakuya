import { Controller } from "@hotwired/stimulus"

// Botón "Instalar la app": solo aparece cuando el navegador ofrece instalar (beforeinstallprompt) y
// la app no está ya instalada; al pulsarlo se abre el diálogo nativo.
export default class extends Controller {
  static targets = ["boton"]

  connect() {
    this.alOfrecer = (e) => { e.preventDefault(); this.evento = e; this.mostrar(true) }
    this.alInstalar = () => { this.evento = null; this.mostrar(false) }
    window.addEventListener("beforeinstallprompt", this.alOfrecer)
    window.addEventListener("appinstalled", this.alInstalar)
    if (window.pwaEvento) { this.evento = window.pwaEvento; this.mostrar(true) }
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.alOfrecer)
    window.removeEventListener("appinstalled", this.alInstalar)
  }

  mostrar(si) { this.botonTargets.forEach((b) => b.classList.toggle("hidden", !si)) }

  async instalar() {
    if (!this.evento) return
    this.evento.prompt()
    const { outcome } = await this.evento.userChoice
    if (outcome === "accepted") this.mostrar(false)
  }
}
