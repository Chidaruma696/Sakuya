// Lo que la caja guarda en el equipo para seguir vendiendo sin conexión (IndexedDB): el catálogo de
// la sucursal y la cola de ventas por subir. Cada venta lleva su clave única, así que subirla dos
// veces no la duplica en el servidor.
const BASE = "sakuya-caja"
const VERSION = 1

function abrir() {
  return new Promise((resolver, fallar) => {
    const pedido = indexedDB.open(BASE, VERSION)
    pedido.onupgradeneeded = () => {
      const db = pedido.result
      if (!db.objectStoreNames.contains("catalogo")) db.createObjectStore("catalogo", { keyPath: "sucursal_id" })
      if (!db.objectStoreNames.contains("cola")) db.createObjectStore("cola", { keyPath: "clave" })
    }
    pedido.onsuccess = () => resolver(pedido.result)
    pedido.onerror = () => fallar(pedido.error)
  })
}

async function operar(almacen, modo, accion) {
  const db = await abrir()
  return new Promise((resolver, fallar) => {
    const tx = db.transaction(almacen, modo)
    const pedido = accion(tx.objectStore(almacen))
    tx.oncomplete = () => resolver(pedido?.result)
    tx.onerror = () => fallar(tx.error)
  })
}

export const guardarCatalogo = (datos) => operar("catalogo", "readwrite", (s) => s.put(datos))
export const catalogo = (sucursalId) => operar("catalogo", "readonly", (s) => s.get(sucursalId))
export const encolar = (venta) => operar("cola", "readwrite", (s) => s.put(venta))
export const pendientes = () => operar("cola", "readonly", (s) => s.getAll())
export const quitar = (clave) => operar("cola", "readwrite", (s) => s.delete(clave))

// Busca en el catálogo guardado lo mismo que busca el servidor: código de barras (con o sin el
// cero de adelante), PLU o clave.
export function buscar(cat, texto) {
  if (!cat) return null
  const t = texto.trim()
  const digitos = t.replace(/\D/g, "")
  return cat.productos.find((p) => digitos && p.codigos.some((c) => c === digitos || c === `0${digitos}` || `0${c}` === digitos)) ||
    (digitos === t && cat.productos.find((p) => String(p.plu) === String(Number(digitos)))) ||
    cat.productos.find((p) => p.clave === t.toUpperCase()) || null
}

// Una clave nueva para cada ticket. crypto.randomUUID solo existe en contextos seguros (HTTPS o
// localhost); en la red local por http se arma con getRandomValues.
export function claveNueva() {
  if (crypto.randomUUID) return crypto.randomUUID()
  const b = crypto.getRandomValues(new Uint8Array(16))
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("")
}

// fetch que distingue "no hay red" (o el servidor no contesta) de una respuesta con error.
export async function pedir(url, opciones = {}) {
  try {
    return await fetch(url, opciones)
  } catch {
    return null
  }
}
