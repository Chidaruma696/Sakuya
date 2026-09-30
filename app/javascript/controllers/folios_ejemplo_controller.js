import { Controller } from "@hotwired/stimulus"

// Paso de folios del primer arranque: enseña cómo quedaría el primer ticket con lo elegido.
export default class extends Controller {
  static targets = ["ejemplo", "propia"]

  connect() { this.pintar() }

  pintar() {
    const form = this.element.closest("form")
    const modo = form.querySelector("[name='instalacion[folios_modo]']:checked")?.value || "por_documento"
    const letra = form.querySelector("[name='instalacion[folios_letra]']:checked")?.value || "propia"
    const codigo = (form.querySelector("[name='instalacion[codigo]']")?.value || "MTZ").trim().toUpperCase()
    const propia = (form.querySelector("[name='instalacion[folios_venta]']")?.value || "").trim().toUpperCase()
    const partes = []
    if (letra === "sucursal") partes.push(codigo)
    if (letra === "propia" && propia) partes.push(propia)
    if (letra === "sucursal" && modo === "por_documento") partes.push("B")
    partes.push("00001")
    this.ejemploTarget.textContent = partes.join("-")
    this.propiaTarget.classList.toggle("invisible", letra !== "propia")
  }
}
