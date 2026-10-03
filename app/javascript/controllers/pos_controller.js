import { Controller } from "@hotwired/stimulus"
import { guardarCatalogo, catalogo, encolar, pendientes, quitar, buscar, claveNueva, pedir } from "sin_conexion"

// El ticket en pantalla: escanea, arma líneas, calcula para mostrar y manda todo al servidor,
// que es quien de verdad cobra y recalcula. Sin conexión sigue vendiendo con el catálogo guardado
// en el equipo y encola las ventas; al volver la red se suben solas, una por una.
export default class extends Controller {
  static targets = ["codigo", "cuerpo", "total", "efectivo", "transferencia", "deposito", "cambio", "aviso",
                    "pendiente", "pendienteNombre", "pendienteCantidad", "botonCobrar", "cliente", "credito", "conexion"]
  static values = { escanearUrl: String, cobrarUrl: String, catalogoUrl: String, tokenUrl: String, sucursal: Number, clave: String, pedido: Object }

  connect() {
    this.lineas = []
    this.pendienteProducto = null
    // La página puede venir de la caché (sin conexión): cada ticket estrena clave en el equipo.
    this.clave = claveNueva()
    this.alCambiarRed = () => { this.pintarConexion(); if (navigator.onLine) this.sincronizar() }
    window.addEventListener("online", this.alCambiarRed)
    window.addEventListener("offline", this.alCambiarRed)
    this.reloj = setInterval(() => this.sincronizar(), 30_000)
    this.actualizarCatalogo()
    this.sincronizar()
    // Cobrar un pedido: el ticket llega armado con sus renglones y su cliente.
    if (this.pedidoValue.lineas) {
      this.pedidoValue.lineas.forEach(l => this.agregar(l))
      if (this.hasClienteTarget) this.clienteTarget.value = this.pedidoValue.cliente_id
    }
    this.render()
  }

  disconnect() {
    window.removeEventListener("online", this.alCambiarRed)
    window.removeEventListener("offline", this.alCambiarRed)
    clearInterval(this.reloj)
  }

  async escanear(event) {
    event.preventDefault()
    const codigo = this.codigoTarget.value.trim()
    if (!codigo) return
    this.codigoTarget.value = ""
    const r = await pedir(`${this.escanearUrlValue}?codigo=${encodeURIComponent(codigo)}`, { headers: { Accept: "application/json" } })
    let datos
    if (r) {
      datos = await r.json()
      if (!r.ok) { this.avisar(datos.error); return }
    } else {
      // Sin conexión: el catálogo guardado en el equipo
      datos = buscar(await catalogo(this.sucursalValue), codigo)
      if (!datos) { this.avisar(T.pos.no_en_catalogo); return }
      this.pintarConexion(false)
    }
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
    cuerpo.append("clave", this.clave)
    if (this.hasClienteTarget) cuerpo.append("cliente_id", this.clienteTarget.value)
    if (this.pedidoValue.id) cuerpo.append("pedido_id", this.pedidoValue.id)
    const token = document.querySelector("meta[name=csrf-token]")?.content
    if (token) cuerpo.append("authenticity_token", token)
    this.botonCobrarTarget.disabled = true
    try {
      const r = await pedir(this.cobrarUrlValue, { method: "POST", body: cuerpo, headers: { Accept: "application/json" } })
      if (!r) { await this.guardarSinConexion(cuerpo, total, efectivo + otros - total); return }
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

  // Los avisos son errores en rojo; `bien` los pinta en verde (una venta guardada sin conexión).
  avisar(texto, bien = false) {
    this.avisoTarget.textContent = texto
    for (const c of ["bg-red-50", "text-red-800"]) this.avisoTarget.classList.toggle(c, !bien)
    for (const c of ["bg-green-50", "text-green-800"]) this.avisoTarget.classList.toggle(c, bien)
  }

  // ---- sin conexión

  async actualizarCatalogo() {
    if (!this.hasCatalogoUrlValue) return
    const r = await pedir(this.catalogoUrlValue, { headers: { Accept: "application/json" } })
    if (r?.ok) await guardarCatalogo(await r.json())
  }

  // El cobro no llegó al servidor: la venta queda en el equipo con su clave y la hora en que se hizo.
  async guardarSinConexion(cuerpo, total, cambio) {
    if (this.aCuenta() > 0 || this.pedidoValue.id) { this.avisar(T.pos.necesita_conexion); return }
    await encolar({ clave: this.clave, lineas: cuerpo.get("lineas"), pagos: cuerpo.get("pagos"), cliente_id: cuerpo.get("cliente_id") || "",
                    vendida_en: new Date().toISOString(), total })
    const aviso = T.pos.guardada_sin_conexion.replace("%{total}", this.pesos(total)).replace("%{cambio}", this.pesos(Math.max(cambio, 0)))
    this.vaciar()
    this.clave = claveNueva()
    this.avisar(aviso, true)
    this.pintarConexion(false)
  }

  // Sube la cola, la más vieja primero. Una que el servidor rechaza se queda con su error (no se
  // pierde); si se cae la red a la mitad, sigue la próxima vez.
  async sincronizar() {
    if (this.subiendo) return
    this.subiendo = true
    try {
      const cola = (await pendientes()).sort((a, b) => a.vendida_en.localeCompare(b.vendida_en))
      if (cola.length === 0) return
      const t = await pedir(this.tokenUrlValue, { headers: { Accept: "application/json" } })
      if (!t?.ok) return
      const { token } = await t.json()
      for (const v of cola) {
        const cuerpo = new FormData()
        for (const campo of ["clave", "lineas", "pagos", "cliente_id", "vendida_en"]) cuerpo.append(campo, v[campo] || "")
        cuerpo.append("authenticity_token", token)
        const r = await pedir(this.cobrarUrlValue, { method: "POST", body: cuerpo, headers: { Accept: "application/json" } })
        if (!r) break
        if (r.ok) await quitar(v.clave)
        else await encolar({ ...v, error: (await r.json().catch(() => ({}))).error || String(r.status) })
      }
    } finally {
      this.subiendo = false
      this.pintarConexion()
    }
  }

  async pintarConexion(enLinea = navigator.onLine) {
    if (!this.hasConexionTarget) return
    const cola = await pendientes().catch(() => [])
    const errores = cola.filter((v) => v.error)
    const partes = []
    if (!enLinea) partes.push(T.pos.sin_conexion)
    if (cola.length) partes.push(cola.length === 1 ? T.pos.por_subir_una : T.pos.por_subir.replace("%{n}", cola.length))
    this.conexionTarget.hidden = partes.length === 0
    this.conexionTarget.querySelector("[data-texto]").textContent = partes.join(" · ")
    this.conexionTarget.querySelector("[data-errores]").textContent = errores.map((v) => `${this.pesos(v.total)}: ${v.error}`).join(" · ")
  }
}
