// What the till keeps on the device to keep selling offline (IndexedDB): the branch catalog and
// the queue of sales waiting to upload. Each sale carries its unique key, so uploading it twice
// does not duplicate it on the server.
const BASE = "sakuya-till"
const VERSION = 1

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(BASE, VERSION)
    request.onupgradeneeded = () => {
      const db = request.result
      if (!db.objectStoreNames.contains("catalog")) db.createObjectStore("catalog", { keyPath: "branch_id" })
      if (!db.objectStoreNames.contains("queue")) db.createObjectStore("queue", { keyPath: "key" })
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function operate(storeName, mode, action) {
  const db = await open()
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode)
    const request = action(tx.objectStore(storeName))
    tx.oncomplete = () => resolve(request?.result)
    tx.onerror = () => reject(tx.error)
  })
}

export const saveCatalog = (data) => operate("catalog", "readwrite", (s) => s.put(data))
export const catalog = (branchId) => operate("catalog", "readonly", (s) => s.get(branchId))
export const enqueue = (sale) => operate("queue", "readwrite", (s) => s.put(sale))
export const pending = () => operate("queue", "readonly", (s) => s.getAll())
export const remove = (key) => operate("queue", "readwrite", (s) => s.delete(key))

// Searches the saved catalog the same way the server does: barcode (with or without the
// leading zero), PLU or key.
export function search(cat, text) {
  if (!cat) return null
  const t = text.trim()
  const digits = t.replace(/\D/g, "")
  return cat.products.find((p) => digits && p.codes.some((c) => c === digits || c === `0${digits}` || `0${c}` === digits)) ||
    (digits === t && cat.products.find((p) => String(p.plu) === String(Number(digits)))) ||
    cat.products.find((p) => p.key === t.toUpperCase()) || null
}

// A new key for each ticket. crypto.randomUUID only exists in secure contexts (HTTPS or
// localhost); on the local network over http it is built with getRandomValues.
export function newKey() {
  if (crypto.randomUUID) return crypto.randomUUID()
  const b = crypto.getRandomValues(new Uint8Array(16))
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("")
}

// fetch that tells "no network" (or the server not answering) apart from an error response.
export async function request(url, options = {}) {
  try {
    return await fetch(url, options)
  } catch {
    return null
  }
}
