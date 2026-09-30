import { Controller } from "@hotwired/stimulus"

// Renglones de un formulario: clona la primera fila con un índice nuevo y quita filas.
export default class extends Controller {
  static targets = ["cuerpo", "fila"]

  agregar() {
    const modelo = this.filaTargets[0]
    const n = Date.now()
    const copia = modelo.cloneNode(true)
    copia.querySelectorAll("select, input").forEach(el => {
      el.name = el.name.replace(/\[\d+\]/, `[${n}]`)
      el.id = el.id.replace(/_\d+_/, `_${n}_`)
      if (el.tagName === "INPUT") el.value = ""
      else el.selectedIndex = 0
    })
    this.cuerpoTarget.appendChild(copia)
    copia.querySelector("select").focus()
  }

  quitar(event) {
    if (this.filaTargets.length > 1) event.target.closest("tr").remove()
  }
}
