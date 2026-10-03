import { Controller } from "@hotwired/stimulus"

// Receipt or invoice lines: the reader scans (or a name/key/PLU is typed) and the product
// lands in a new line, or it is picked by hand. The first row is the template.
export default class extends Controller {
  static targets = ["body", "row", "scanner", "notice"]
  static values = { url: String }

  add(product) {
    const template = this.rowTargets[0]
    const empty = this.rowTargets.find(f => !f.querySelector("select").value)
    const row = empty || template.cloneNode(true)
    if (!empty) {
      const n = Date.now()
      row.querySelectorAll("select, input").forEach(el => {
        el.name = el.name.replace(/\[\d+\]/, `[${n}]`)
        el.id = el.id.replace(/_\d+_/, `_${n}_`)
        if (el.tagName === "INPUT") el.value = ""
        else el.selectedIndex = 0
      })
      this.bodyTarget.appendChild(row)
    }
    if (product) {
      row.querySelector("select").value = product.id
      const quantity = row.querySelector("[data-field=quantity]")
      if (product.quantity) quantity.value = product.quantity
      quantity.focus(); quantity.select()
    } else {
      row.querySelector("select").focus()
    }
  }

  new() { this.add(null) }

  remove(event) {
    if (this.rowTargets.length > 1) event.target.closest("tr").remove()
    else this.rowTargets[0].querySelectorAll("input").forEach(i => i.value = "")
  }

  async scan(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    const q = this.scannerTarget.value.trim()
    if (!q) return
    const r = await fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
    const list = r.ok ? await r.json() : []
    this.scannerTarget.value = ""
    if (list.length === 1) {
      this.notify("")
      this.add(list[0])
    } else if (list.length === 0) {
      this.notify(window.T?.not_found || "?")
    } else {
      this.notify(list.map(p => p.name).join(" · "))
      this.add(null)
    }
  }

  notify(text) { if (this.hasNoticeTarget) this.noticeTarget.textContent = text }
}
