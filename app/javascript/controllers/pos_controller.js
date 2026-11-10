import { Controller } from "@hotwired/stimulus"
import { saveCatalog, catalog, enqueue, pending, remove, search, newKey, request } from "offline"

// The on-screen ticket: scans, builds lines, calculates for display and sends everything to the server,
// which is what really checks out and recalculates. Offline it keeps selling with the catalog saved
// on the device and queues the sales; when the network comes back they upload by themselves, one by one.

// Names go into the ticket as HTML: escaped, so a name is always just text.
const escapeHtml = (text) => String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

export default class extends Controller {
  static targets = ["code", "body", "total", "cash", "transfer", "deposit", "change", "notice",
                    "pending", "pendingName", "pendingQuantity", "checkoutButton", "customer", "credit", "connection"]
  static values = { scanUrl: String, checkoutUrl: String, catalogUrl: String, tokenUrl: String, loginUrl: String, branch: Number, user: Number, key: String, order: Object }

  connect() {
    this.lines = []
    this.pendingProduct = null
    // The page may come from the cache (offline): every ticket gets a fresh key on the device.
    this.key = newKey()
    this.onNetworkChange = () => { this.renderConnection(); if (navigator.onLine) this.sync() }
    window.addEventListener("online", this.onNetworkChange)
    window.addEventListener("offline", this.onNetworkChange)
    this.clock = setInterval(() => this.sync(), 30_000)
    this.updateCatalog()
    this.sync()
    // Checking out an order: the ticket arrives prefilled with its lines and its customer.
    if (this.orderValue.lines) {
      this.orderValue.lines.forEach(l => this.add(l))
      if (this.hasCustomerTarget) this.customerTarget.value = this.orderValue.customer_id
    }
    this.render()
  }

  disconnect() {
    window.removeEventListener("online", this.onNetworkChange)
    window.removeEventListener("offline", this.onNetworkChange)
    clearInterval(this.clock)
  }

  async scan(event) {
    event.preventDefault()
    const code = this.codeTarget.value.trim()
    if (!code) return
    this.codeTarget.value = ""
    const r = await request(`${this.scanUrlValue}?code=${encodeURIComponent(code)}`, { headers: { Accept: "application/json" } })
    let data
    if (r) {
      data = await r.json()
      if (!r.ok) { this.notify(data.error); return }
    } else {
      // Offline: the catalog saved on the device
      data = search(await catalog(this.branchValue), code)
      if (!data) { this.notify(T.pos.not_in_catalog); return }
      this.renderConnection(false)
    }
    this.notify("")
    if (data.unit !== "piece") {
      // Kilo, liter or meter: the quantity is typed in
      this.pendingProduct = data
      this.pendingNameTarget.textContent = `${data.name} (${T.units[data.unit] || data.unit})`
      this.pendingQuantityTarget.value = ""
      this.pendingTarget.classList.remove("hidden")
      this.pendingQuantityTarget.focus()
    } else {
      const existing = this.lines.find(l => l.product_id === data.product_id)
      if (existing) { existing.quantity += 1; this.render() } else this.add({ ...data, quantity: 1 })
    }
  }

  confirmPending(event) {
    event?.preventDefault()
    if (!this.pendingProduct) return // nothing is waiting for a quantity (the scan has not answered yet)
    const quantity = Number(this.pendingQuantityTarget.value)
    if (!(quantity > 0)) { this.notify(T.pos.quantity); return }
    this.add({ ...this.pendingProduct, quantity })
    this.cancelPending()
  }

  cancelPending() {
    this.pendingProduct = null
    this.pendingTarget.classList.add("hidden")
    this.codeTarget.focus()
  }

  add(data) {
    const l = { product_id: data.product_id, name: data.name, unit: data.unit, decimals: data.decimals,
                quantity: data.quantity, catalog: data.price_cents, promotions: data.promotions || [], manual: false }
    l.price = this.currentPrice(l)
    this.lines.push(l)
    this.render()
    this.codeTarget.focus()
  }

  // The best legitimate price for the quantity: an active promotion or the catalog. The server recalculates it.
  currentPrice(l) {
    let best = l.catalog
    l.promo = null
    for (const p of l.promotions) {
      if (l.quantity < Number(p.minimum_quantity)) continue
      // In whole numbers, like the server: a float would turn an exact half cent into 0.4999… and round it down.
      const price = p.kind === "percentage" ? Math.round(l.catalog * (10000 - Math.round(Number(p.percentage) * 100)) / 10000) : p.price_cents
      if (price < best) { best = price; l.promo = p.name }
    }
    return best
  }

  remove(event) {
    this.lines.splice(Number(event.params.index), 1)
    this.render()
  }

  changePrice(event) {
    const l = this.lines[Number(event.params.index)]
    l.price = Math.round(Number(event.target.value) * 100)
    l.manual = true
    this.render(false)
  }

  changeQuantity(event) {
    const l = this.lines[Number(event.params.index)]
    l.quantity = Number(event.target.value)
    if (!l.manual) l.price = this.currentPrice(l)
    this.render()
  }

  // Thousandths × cents in whole numbers, so the screen shows the same cents the server will charge.
  amount(l) { return Math.round(Math.round(l.quantity * 1000) * l.price / 1000) }
  totalCents() { return this.lines.reduce((s, l) => s + this.amount(l), 0) }
  // Same format as Money.format_money on the server: the business symbol, comma thousands, two decimals.
  format_money(c) { const n = Math.abs(c) / 100; return `${c < 0 ? "−" : ""}${window.CURRENCY?.symbol ?? "$"}${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` }
  cents(input) { return Math.round(Number(input.value || 0) * 100) }

  render(rows = true) {
    if (rows) {
      this.bodyTarget.innerHTML = this.lines.map((l, i) => `
        <tr class="border-t border-stone-100 ${l.manual && l.price < l.catalog ? "bg-amber-50" : ""}">
          <td class="px-3 py-2">${escapeHtml(l.name)}${l.promo ? ` <span class="rounded bg-emerald-100 px-1 text-xs text-emerald-800">${escapeHtml(l.promo)}</span>` : ""}</td>
          <td class="px-3 py-2 text-right font-mono"><input type="number" value="${l.quantity}" step="${l.unit === "piece" ? "1" : "0.001"}" min="0" data-action="change->pos#changeQuantity" data-pos-index-param="${i}" class="w-24 rounded border border-stone-300 px-1 text-right font-mono"> ${T.units[l.unit] || l.unit}</td>
          <td class="px-3 py-2 text-right font-mono"><input type="number" value="${(l.price / 100).toFixed(2)}" step="0.01" min="0" data-action="change->pos#changePrice" data-pos-index-param="${i}" class="w-24 rounded border border-stone-300 px-1 text-right font-mono"></td>
          <td class="px-3 py-2 text-right font-mono" data-amount="${i}">${this.format_money(this.amount(l))}</td>
          <td class="px-1"><button type="button" data-action="pos#remove" data-pos-index-param="${i}" class="px-2 text-red-700"><i class="bi bi-x-lg"></i></button></td>
        </tr>`).join("")
    } else {
      this.lines.forEach((l, i) => { const c = this.bodyTarget.querySelector(`[data-amount="${i}"]`); if (c) c.textContent = this.format_money(this.amount(l)) })
    }
    this.totalTarget.textContent = this.format_money(this.totalCents())
    this.recalculate()
  }

  // With the customers feature, what goes on account counts as paid (the server decides whether to extend credit).
  onAccount() { return this.hasCreditTarget ? this.cents(this.creditTarget) : 0 }

  recalculate() {
    const paid = this.cents(this.cashTarget) + this.cents(this.transferTarget) + this.cents(this.depositTarget) + this.onAccount()
    const change = paid - this.totalCents()
    this.changeTarget.textContent = this.format_money(Math.max(change, 0))
    this.changeTarget.classList.toggle("text-red-700", change < 0)
  }

  async checkout() {
    if (this.signedOut) { this.notify(T.pos.signed_out); return }
    if (this.lines.length === 0) { this.notify(T.pos.ticket_empty); return }
    const total = this.totalCents()
    let cash = this.cents(this.cashTarget)
    const others = this.cents(this.transferTarget) + this.cents(this.depositTarget) + this.onAccount()
    if (cash + others === 0) cash = total  // exact cash payment if nothing was entered
    const payments = [
      { payment_method: "cash", amount_cents: cash },
      { payment_method: "transfer", amount_cents: this.cents(this.transferTarget) },
      { payment_method: "deposit", amount_cents: this.cents(this.depositTarget) },
      { payment_method: "credit", amount_cents: this.onAccount() }
    ]
    const body = new FormData()
    body.append("lines", JSON.stringify(this.lines.map(l => ({ product_id: l.product_id, quantity: l.quantity, price_cents: l.manual ? l.price : null }))))
    body.append("payments", JSON.stringify(payments))
    body.append("key", this.key)
    if (this.hasCustomerTarget) body.append("customer_id", this.customerTarget.value)
    if (this.orderValue.id) body.append("order_id", this.orderValue.id)
    const token = document.querySelector("meta[name=csrf-token]")?.content
    if (token) body.append("authenticity_token", token)
    this.checkoutButtonTarget.disabled = true
    try {
      const r = await request(this.checkoutUrlValue, { method: "POST", body: body, headers: { Accept: "application/json" } })
      if (!r) { await this.saveOffline(body, total, cash + others - total); return }
      const data = await r.json().catch(() => ({}))
      if (r.status === 401) { this.lostSession(); this.notify(data.error || T.pos.signed_out); return }
      if (!r.ok) { this.notify(data.error || String(r.status)); return }
      window.location.assign(data.url)
    } finally {
      this.checkoutButtonTarget.disabled = false
    }
  }

  clear() {
    this.lines = []
    this.cashTarget.value = this.transferTarget.value = this.depositTarget.value = ""
    if (this.hasCreditTarget) this.creditTarget.value = ""
    if (this.hasCustomerTarget) this.customerTarget.value = ""
    this.render()
    this.codeTarget.focus()
  }

  // Notices are errors in red; `ok` paints them green (a sale saved offline).
  notify(text, ok = false) {
    this.noticeTarget.textContent = text
    for (const c of ["bg-red-50", "text-red-800"]) this.noticeTarget.classList.toggle(c, !ok)
    for (const c of ["bg-green-50", "text-green-800"]) this.noticeTarget.classList.toggle(c, ok)
  }

  // ---- offline

  async updateCatalog() {
    if (!this.hasCatalogUrlValue) return
    const r = await request(this.catalogUrlValue, { headers: { Accept: "application/json", "X-Background": "1" } })
    if (r?.ok) await saveCatalog(await r.json())
  }

  // The checkout did not reach the server: the sale stays on the device with its key and the time it was made.
  async saveOffline(body, total, change) {
    if (this.onAccount() > 0 || this.orderValue.id) { this.notify(T.pos.needs_connection); return }
    await enqueue({ key: this.key, lines: body.get("lines"), payments: body.get("payments"), customer_id: body.get("customer_id") || "", sold_by: this.userValue || "",
                    sold_at: new Date().toISOString(), total })
    const notice = T.pos.saved_offline.replace("%{total}", this.format_money(total)).replace("%{change}", this.format_money(Math.max(change, 0)))
    this.clear()
    this.key = newKey()
    this.notify(notice, true)
    this.renderConnection(false)
  }

  // Uploads the queue, oldest first. One the server rejects stays with its error (it is not
  // lost); if the network drops halfway, it carries on next time.
  async sync() {
    if (this.uploading) return
    this.uploading = true
    try {
      const queue = (await pending()).sort((a, b) => a.sold_at.localeCompare(b.sold_at))
      if (queue.length === 0) return
      // Uploading is the page's own doing, not someone using the till: it does not keep the session alive.
      const background = { Accept: "application/json", "X-Background": "1" }
      const t = await request(this.tokenUrlValue, { headers: background })
      if (t?.status === 401) { this.lostSession(); return }
      if (!t?.ok) return
      // Signed out, the answer is the login page, not a token: nothing is uploaded and nothing is lost.
      const { token } = await t.json().catch(() => ({}))
      if (!token) return
      for (const v of queue) {
        const body = new FormData()
        for (const field of ["key", "lines", "payments", "customer_id", "sold_at", "sold_by"]) body.append(field, v[field] || "")
        body.append("authenticity_token", token)
        const r = await request(this.checkoutUrlValue, { method: "POST", body: body, headers: background })
        if (!r) break
        if (r.status === 401) { this.lostSession(); break }
        const data = await r.json().catch(() => null)
        // Only the till's own answer, with the folio, takes a sale off the device.
        if (r.ok && data?.folio) await remove(v.key)
        else if (r.ok) break
        else await enqueue({ ...v, error: data?.error || String(r.status) })
      }
    } finally {
      this.uploading = false
      this.renderConnection()
    }
  }

  async renderConnection(online = navigator.onLine) {
    if (!this.hasConnectionTarget) return
    const queue = await pending().catch(() => [])
    const errors = queue.filter((v) => v.error)
    const parts = []
    if (!online) parts.push(T.pos.offline)
    if (this.signedOut) parts.push(queue.length === 0 ? T.pos.signed_out : queue.length === 1 ? T.pos.sign_in_to_upload_one : T.pos.sign_in_to_upload.replace("%{n}", queue.length))
    else if (queue.length) parts.push(queue.length === 1 ? T.pos.to_upload_one : T.pos.to_upload.replace("%{n}", queue.length))
    this.connectionTarget.hidden = parts.length === 0
    const text = this.connectionTarget.querySelector("[data-text]")
    text.textContent = parts.join(" · ")
    const signIn = this.connectionTarget.querySelector("[data-sign-in]")
    signIn.textContent = T.pos.sign_in
    signIn.hidden = !this.signedOut
    // Uploading by hand only makes sense with something to upload and a session to upload it with.
    this.connectionTarget.querySelector("[data-upload]").hidden = this.signedOut || queue.length === 0
    // A sale the server refuses stays with its reason until someone decides to discard it.
    this.connectionTarget.querySelector("[data-errors]").replaceChildren(...errors.map((v) => {
      const row = document.createElement("div")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "link ml-2"
      button.textContent = T.pos.discard
      button.addEventListener("click", () => this.discard(v))
      row.append(`${this.format_money(v.total)}: ${v.error}`, button)
      return row
    }))
  }

  // This device's session ended (opened elsewhere, or left unused). What is waiting stays on the
  // device; nothing is charged or retried until someone signs in here.
  lostSession() {
    this.signedOut = true
    clearInterval(this.clock)
    this.renderConnection()
  }

  async discard(sale) {
    if (!confirm(T.pos.discard_confirm.replace("%{total}", this.format_money(sale.total)))) return
    await remove(sale.key)
    this.renderConnection()
  }
}
