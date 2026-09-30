import { Controller } from "@hotwired/stimulus"

// Renglones de recepción o factura: el lector escanea (o se teclea nombre/clave/PLU) y el producto
// cae en un renglón nuevo, o se elige a mano. La primera fila es el molde.
export default class extends Controller {
  static targets = ["cuerpo", "fila", "escaner", "aviso"]
  static values = { url: String }

  agregar(producto) {
    const modelo = this.filaTargets[0]
    const vacia = this.filaTargets.find(f => !f.querySelector("select").value)
    const fila = vacia || modelo.cloneNode(true)
    if (!vacia) {
      const n = Date.now()
      fila.querySelectorAll("select, input").forEach(el => {
        el.name = el.name.replace(/\[\d+\]/, `[${n}]`)
        el.id = el.id.replace(/_\d+_/, `_${n}_`)
        if (el.tagName === "INPUT") el.value = ""
        else el.selectedIndex = 0
      })
      this.cuerpoTarget.appendChild(fila)
    }
    if (producto) {
      fila.querySelector("select").value = producto.id
      const cantidad = fila.querySelector("[data-campo=cantidad]")
      if (producto.cantidad) cantidad.value = producto.cantidad
      cantidad.focus(); cantidad.select()
    } else {
      fila.querySelector("select").focus()
    }
  }

  nuevo() { this.agregar(null) }

  quitar(event) {
    if (this.filaTargets.length > 1) event.target.closest("tr").remove()
    else this.filaTargets[0].querySelectorAll("input").forEach(i => i.value = "")
  }

  async escanear(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    const q = this.escanerTarget.value.trim()
    if (!q) return
    const r = await fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
    const lista = r.ok ? await r.json() : []
    this.escanerTarget.value = ""
    if (lista.length === 1) {
      this.avisar("")
      this.agregar(lista[0])
    } else if (lista.length === 0) {
      this.avisar(window.T?.no_encontrado || "?")
    } else {
      this.avisar(lista.map(p => p.nombre).join(" · "))
      this.agregar(null)
    }
  }

  avisar(texto) { if (this.hasAvisoTarget) this.avisoTarget.textContent = texto }
}
