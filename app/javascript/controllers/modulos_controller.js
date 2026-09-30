import { Controller } from "@hotwired/stimulus"

// Interruptores de módulos: encender uno marca lo que necesita (y, si necesita "alguno de", el
// primero cuando no hay ninguno); apagar uno desmarca a los que lo necesitan y a los que se quedan
// sin ninguna base. Así lo que llega al servidor ya es coherente y nadie se queda a medias.
export default class extends Controller {
  static targets = ["caja"]

  cambiar(event) {
    const caja = event.target
    const lista = (el, campo) => (el.dataset[campo] || "").split(" ").filter(Boolean)
    if (caja.checked) {
      lista(caja, "necesita").forEach((m) => this.marcar(m, true))
      const alguno = lista(caja, "alguno")
      if (alguno.length && !alguno.some((m) => this.caja(m)?.checked)) this.marcar(alguno[0], true)
    } else {
      lista(caja, "dependientes").forEach((m) => this.marcar(m, false))
      this.cajaTargets.forEach((otra) => {
        const alguno = lista(otra, "alguno")
        if (otra.checked && alguno.includes(caja.dataset.modulo) && !alguno.some((m) => this.caja(m)?.checked)) this.marcar(otra.dataset.modulo, false)
      })
    }
  }

  caja(modulo) { return this.cajaTargets.find((c) => c.dataset.modulo === modulo) }

  marcar(modulo, valor) {
    const caja = this.caja(modulo)
    if (caja && caja.checked !== valor) {
      caja.checked = valor
      caja.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }
}
