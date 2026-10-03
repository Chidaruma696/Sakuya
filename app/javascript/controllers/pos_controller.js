import { Controller } from "@hotwired/stimulus"

// El ticket en pantalla: escanea, arma líneas, calcula para mostrar y manda todo al servidor,
// que es quien de verdad cobra y recalcula.
export default class extends Controller {
  static targets = ["codigo", "cuerpo", "total", "efectivo", "transferencia", "deposito", "cambio", "aviso",
                    "pendiente", "pendienteNombre", "pendienteCantidad", "botonCobrar", "cliente", "credito"]
  static values = { escanearUrl: String, cobrarUrl: String, clave: String }

  connect() {
    this.lineas = []
    this.pendienteProducto = null
    this.render()
  }

  async escanear(event) {
    event.preventDefault()
    const codigo = this.codigoTarget.value.trim()
    if (!codigo) return
    this.codigoTarget.value = ""
    const r = await fetch(`${this.escanearUrlValue}?codigo=${encodeURIComponent(codigo)}`, { headers: { Accept: "application/json" } })
    const datos = await r.json()
    if (!r.ok) { this.avisar(datos.error); return }
    this.avisar("")
    if (datos.unidad !== "pieza") {
      // Kilo, litro o metro: se teclea la cantidad
      this.pendienteProducto = datos
      this.pendienteNombreTarget.textContent = `${datos.nombre} (${T.unidades[datos.unidad] || datos.unidad})`
      this.pendienteCantidadTarget.value = ""
      this.pendienteTarget.classList.remove("hidden")
      this.pendienteCantidadTarget.focus()
    } else {
      const previa = this.lineas.find(l => l.producto_id === datos.producto_id)
      if (previa) { previa.cantidad += 1; this.render() } else this.agregar({ ...datos, cantidad: 1 })
    }
  }

  confirmarPendiente(event) {
    event?.preventDefault()
    const cantidad = Number(this.pendienteCantidadTarget.value)
    if (!(cantidad > 0)) { this.avisar(T.pos.cantidad); return }
    this.agregar({ ...this.pendienteProducto, cantidad })
    this.cancelarPendiente()
  }

  cancelarPendiente() {
    this.pendienteProducto = null
    this.pendienteTarget.classList.add("hidden")
    this.codigoTarget.focus()
  }

  agregar(datos) {
    const l = { producto_id: datos.producto_id, nombre: datos.nombre, unidad: datos.unidad, decimales: datos.decimales,
                cantidad: datos.cantidad, catalogo: datos.precio_centavos, promociones: datos.promociones || [], manual: false }
    l.precio = this.precioVigente(l)
    this.lineas.push(l)
    this.render()
    this.codigoTarget.focus()
  }

  // El mejor precio legítimo para la cantidad: promoción vigente o catálogo. El servidor lo recalcula.
  precioVigente(l) {
    let mejor = l.catalogo
    l.promo = null
    for (const p of l.promociones) {
      if (l.cantidad < Number(p.cantidad_minima)) continue
      const precio = p.tipo === "porcentaje" ? Math.round(l.catalogo * (1 - Number(p.porcentaje) / 100)) : p.precio_centavos
      if (precio < mejor) { mejor = precio; l.promo = p.nombre }
    }
    return mejor
  }

  quitar(event) {
    this.lineas.splice(Number(event.params.indice), 1)
    this.render()
  }

  cambiarPrecio(event) {
    const l = this.lineas[Number(event.params.indice)]
    l.precio = Math.round(Number(event.target.value) * 100)
    l.manual = true
    this.render(false)
  }

  cambiarCantidad(event) {
    const l = this.lineas[Number(event.params.indice)]
    l.cantidad = Number(event.target.value)
    if (!l.manual) l.precio = this.precioVigente(l)
    this.render()
  }

  importe(l) { return Math.round(l.cantidad * l.precio) }
  totalCentavos() { return this.lineas.reduce((s, l) => s + this.importe(l), 0) }
  // Mismo formato que Dinero.pesos en el servidor: símbolo del negocio, miles con coma, dos decimales.
  pesos(c) { const n = Math.abs(c) / 100; return `${c < 0 ? "−" : ""}${window.MONEDA?.simbolo ?? "$"}${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` }
  centavos(input) { return Math.round(Number(input.value || 0) * 100) }

  render(filas = true) {
    if (filas) {
      this.cuerpoTarget.innerHTML = this.lineas.map((l, i) => `
        <tr class="border-t border-stone-100 ${l.manual && l.precio < l.catalogo ? "bg-amber-50" : ""}">
          <td class="px-3 py-2">${l.nombre}${l.promo ? ` <span class="rounded bg-emerald-100 px-1 text-xs text-emerald-800">${l.promo}</span>` : ""}</td>
          <td class="px-3 py-2 text-right font-mono"><input type="number" value="${l.cantidad}" step="${l.unidad === "pieza" ? "1" : "0.001"}" min="0" data-action="change->pos#cambiarCantidad" data-pos-indice-param="${i}" class="w-24 rounded border border-stone-300 px-1 text-right font-mono"> ${l.unidad}</td>
          <td class="px-3 py-2 text-right font-mono"><input type="number" value="${(l.precio / 100).toFixed(2)}" step="0.01" min="0" data-action="change->pos#cambiarPrecio" data-pos-indice-param="${i}" class="w-24 rounded border border-stone-300 px-1 text-right font-mono"></td>
          <td class="px-3 py-2 text-right font-mono" data-importe="${i}">${this.pesos(this.importe(l))}</td>
          <td class="px-1"><button type="button" data-action="pos#quitar" data-pos-indice-param="${i}" class="px-2 text-red-700"><i class="bi bi-x-lg"></i></button></td>
        </tr>`).join("")
    } else {
      this.lineas.forEach((l, i) => { const c = this.cuerpoTarget.querySelector(`[data-importe="${i}"]`); if (c) c.textContent = this.pesos(this.importe(l)) })
    }
    this.totalTarget.textContent = this.pesos(this.totalCentavos())
    this.recalcular()
  }

  // Con el módulo de clientes, lo que va a cuenta cuenta como pagado (el servidor decide si se fía).
  aCuenta() { return this.hasCreditoTarget ? this.centavos(this.creditoTarget) : 0 }

  recalcular() {
    const pagado = this.centavos(this.efectivoTarget) + this.centavos(this.transferenciaTarget) + this.centavos(this.depositoTarget) + this.aCuenta()
    const cambio = pagado - this.totalCentavos()
    this.cambioTarget.textContent = this.pesos(Math.max(cambio, 0))
    this.cambioTarget.classList.toggle("text-red-700", cambio < 0)
  }

  async cobrar() {
    if (this.lineas.length === 0) { this.avisar(T.pos.ticket_vacio); return }
    const total = this.totalCentavos()
    let efectivo = this.centavos(this.efectivoTarget)
    const otros = this.centavos(this.transferenciaTarget) + this.centavos(this.depositoTarget) + this.aCuenta()
    if (efectivo + otros === 0) efectivo = total  // pago exacto en efectivo si no se capturó nada
    const pagos = [
      { forma: "efectivo", monto_centavos: efectivo },
      { forma: "transferencia", monto_centavos: this.centavos(this.transferenciaTarget) },
      { forma: "deposito", monto_centavos: this.centavos(this.depositoTarget) },
      { forma: "credito", monto_centavos: this.aCuenta() }
    ]
    const cuerpo = new FormData()
    cuerpo.append("lineas", JSON.stringify(this.lineas.map(l => ({ producto_id: l.producto_id, cantidad: l.cantidad, precio_centavos: l.manual ? l.precio : null }))))
    cuerpo.append("pagos", JSON.stringify(pagos))
    cuerpo.append("clave", this.claveValue)
    if (this.hasClienteTarget) cuerpo.append("cliente_id", this.clienteTarget.value)
    cuerpo.append("authenticity_token", document.querySelector("meta[name=csrf-token]").content)
    this.botonCobrarTarget.disabled = true
    try {
      const r = await fetch(this.cobrarUrlValue, { method: "POST", body: cuerpo, headers: { Accept: "application/json" } })
      const datos = await r.json()
      if (!r.ok) { this.avisar(datos.error); return }
      window.location.assign(datos.url)
    } finally {
      this.botonCobrarTarget.disabled = false
    }
  }

  vaciar() {
    this.lineas = []
    this.efectivoTarget.value = this.transferenciaTarget.value = this.depositoTarget.value = ""
    if (this.hasCreditoTarget) this.creditoTarget.value = ""
    if (this.hasClienteTarget) this.clienteTarget.value = ""
    this.render()
    this.codigoTarget.focus()
  }

  avisar(texto) { this.avisoTarget.textContent = texto }
}
