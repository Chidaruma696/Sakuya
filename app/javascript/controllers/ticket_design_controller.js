import { Controller } from "@hotwired/stimulus"

// Ticket design: what is typed on the left shows up right away in the preview on the
// right (the real ticket inside an iframe, with its own styles).
export default class extends Controller {
  static targets = ["frame", "logo", "logoMini", "noLogo", "zoom", "layout", "labels", "selected", "tool", "tray"]

  get doc() { return this.frameTarget.contentDocument }

  // The ticket is a stack of blocks (a thermal printer prints line by line): each one can be
  // dragged up or down on the paper and, once picked, aligned, enlarged or hidden. The order
  // and look travel in a hidden field as JSON and are saved with the rest of the form.
  connect() {
    // If the preview finished loading before this controller connected, its load event is gone.
    if (this.doc?.readyState === "complete" && this.blocks().length) this.ready()
  }

  ready() {
    this.zoomFit()
    this.blocks().filter((b) => !b.dataset.grabbed).forEach((b) => { b.dataset.grabbed = "1"; this.grab(b) })
    this.words().filter((w) => !w.dataset.grabbed).forEach((w) => { w.dataset.grabbed = "1"; this.word(w) })
    this.refresh()
  }

  // The ticket's fixed words (Product, Quantity, TOTAL…): a double click on one lets it be
  // retyped on the paper itself; Enter or clicking away keeps it, Escape undoes it, and leaving
  // it blank brings the built-in word back. Only the changed ones travel, as JSON.
  words() { return Array.from(this.doc?.querySelectorAll("[data-label-key]") || []) }

  word(w) {
    w.addEventListener("dblclick", (e) => {
      e.stopPropagation()
      const block = w.closest("[data-block]")
      if (block) block.draggable = false
      w.dataset.before = w.textContent
      w.contentEditable = "true"
      w.focus()
      this.doc.getSelection()?.selectAllChildren(w)
    })
    w.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); w.blur() }
      if (e.key === "Escape") { w.textContent = w.dataset.before; w.blur() }
    })
    w.addEventListener("blur", () => {
      if (w.contentEditable !== "true") return
      w.contentEditable = "false"
      const block = w.closest("[data-block]")
      if (block) block.draggable = true
      w.textContent = w.textContent.replace(/\s+/g, " ").trim().slice(0, 40) || w.dataset.default
      const typed = {}
      this.words().forEach((x) => { if (x.textContent !== x.dataset.default) typed[x.dataset.labelKey] = x.textContent })
      this.labelsTarget.value = Object.keys(typed).length ? JSON.stringify(typed) : ""
    })
  }

  blocks() { return Array.from(this.doc?.querySelectorAll("[data-block]") || []) }

  grab(b) {
    b.draggable = true
    b.addEventListener("click", () => this.pick(b))
    b.addEventListener("dragstart", (e) => {
      this.dragged = b
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", b.dataset.block)
      b.classList.add("dragging")
    })
    b.addEventListener("dragend", () => { b.classList.remove("dragging"); this.clearDrop(); this.dragged = null })
    b.addEventListener("dragover", (e) => {
      if (!this.dragged || this.dragged === b) return
      e.preventDefault()
      const box = b.getBoundingClientRect()
      this.after = e.clientY > box.top + box.height / 2
      this.clearDrop()
      b.classList.add(this.after ? "drop-after" : "drop-before")
    })
    b.addEventListener("drop", (e) => {
      e.preventDefault()
      if (!this.dragged || this.dragged === b) return
      b.parentNode.insertBefore(this.dragged, this.after ? b.nextSibling : b)
      this.clearDrop()
      this.pick(this.dragged)
      this.store()
    })
  }

  clearDrop() { this.blocks().forEach((b) => b.classList.remove("drop-before", "drop-after")) }

  pick(b) {
    this.picked = b
    this.refresh()
  }

  can(b, what) { return (b?.dataset.can || "").split(" ").includes(what) }

  align(e) {
    const b = this.picked
    if (!this.can(b, "align")) return
    b.classList.remove("a-left", "a-center", "a-right")
    b.classList.add(`a-${e.currentTarget.dataset.side}`)
    this.store()
  }

  size() {
    if (!this.can(this.picked, "size")) return
    this.picked.classList.toggle("large")
    this.store()
  }

  // Bold and underline go with the blocks whose size can change.
  style(e) {
    if (!this.can(this.picked, "size")) return
    this.picked.classList.toggle(e.currentTarget.dataset.style)
    this.store()
  }

  hide() {
    if (!this.can(this.picked, "hide")) return
    this.picked.classList.add("off")
    this.picked = null
    this.store()
  }

  bringBack(e) {
    const b = this.blocks().find((x) => x.dataset.block === e.currentTarget.dataset.block)
    if (!b) return
    b.classList.remove("off")
    this.pick(b)
    this.store()
  }

  // Back to the ticket as it comes: the built-in order, alignment and size, nothing hidden.
  reset() {
    const paper = this.node("paper")
    const bold = this.trayTarget.dataset.bold.split(" ")
    const aligns = Object.fromEntries(this.trayTarget.dataset.aligns.split(" ").map((x) => x.split(":")))
    this.trayTarget.dataset.order.split(" ").forEach((key) => {
      const b = this.blocks().find((x) => x.dataset.block === key)
      if (!b) return
      b.classList.remove("a-left", "a-center", "a-right", "large", "bold", "underline", "off")
      if (bold.includes(key)) b.classList.add("bold")
      if (aligns[key]) b.classList.add(`a-${aligns[key]}`)
      paper.appendChild(b)
    })
    this.picked = null
    this.store()
  }

  sideOf(b) { return ["left", "center", "right"].find((s) => b.classList.contains(`a-${s}`)) }

  store() {
    const list = this.blocks().map((b) => {
      const item = { k: b.dataset.block }
      const side = this.sideOf(b)
      if (side) item.a = side
      if (b.classList.contains("large")) item.l = true
      if (this.can(b, "size")) item.b = b.classList.contains("bold")
      if (b.classList.contains("underline")) item.u = true
      if (b.classList.contains("off")) item.off = true
      return item
    })
    this.layoutTarget.value = JSON.stringify(list)
    this.refresh()
  }

  // The toolbar follows the picked block, and the hidden ones wait in the tray to be brought back.
  refresh() {
    const b = this.picked
    this.blocks().forEach((x) => x.classList.toggle("selected", x === b))
    this.selectedTarget.textContent = b ? b.dataset.label : this.selectedTarget.dataset.none
    this.toolTargets.forEach((t) => {
      t.disabled = !this.can(b, t.dataset.needs)
      const on = b && ((t.dataset.side && this.sideOf(b) === t.dataset.side) || (t.dataset.style && b.classList.contains(t.dataset.style)))
      t.classList.toggle("btn-primary", !!on)
      t.classList.toggle("btn-secondary", !on)
    })
    const hidden = this.blocks().filter((x) => x.classList.contains("off"))
    this.trayTarget.replaceChildren()
    if (!hidden.length) return
    const label = document.createElement("span")
    label.className = "text-stone-500"
    label.textContent = this.trayTarget.dataset.label
    this.trayTarget.appendChild(label)
    hidden.forEach((x) => {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "btn btn-ghost btn-xs"
      chip.dataset.block = x.dataset.block
      chip.dataset.action = "ticket-design#bringBack"
      chip.textContent = `+ ${x.dataset.label}`
      this.trayTarget.appendChild(chip)
    })
  }

  // Prints the sample exactly as shown: useful to test the printer and the paper width.
  print() { this.frameTarget.contentWindow?.print() }

  // Preview zoom: the paper shows at whatever size you like; on open, fitted to the width.
  zoomPlus() { this.setZoom((this.factor || 1) + 0.25) }
  zoomMinus() { this.setZoom((this.factor || 1) - 0.25) }
  zoomFit() {
    const paper = this.node("paper")
    if (!paper) return
    const available = this.frameTarget.clientWidth - 24
    this.setZoom(Math.floor((available / paper.offsetWidth) * 20) / 20)
  }
  setZoom(factor) {
    this.factor = Math.min(Math.max(factor, 0.5), 4)
    const paper = this.node("paper")
    if (paper) paper.style.zoom = this.factor
    if (this.hasZoomTarget) this.zoomTarget.textContent = `${Math.round(this.factor * 100)} %`
  }

  node(key) { return this.doc?.querySelector(`[data-ticket="${key}"]`) }

  text(e) {
    const n = this.node(e.target.dataset.key)
    if (!n) return
    const v = e.target.value.trim()
    n.textContent = v || n.dataset.empty || ""
    n.classList.toggle("hidden", !v && !n.dataset.empty)
  }

  show(e) {
    this.node(e.target.dataset.key)?.classList.toggle("hidden", !e.target.checked)
  }

  width(e) {
    const mm = e.target.value === "58" ? 48 : 72
    const paper = this.node("paper")
    if (paper) paper.style.width = `${mm}mm`
    this.zoomFit()
  }

  logo(e) {
    const file = e.target.files[0]
    if (!file) return
    if (file.size > 300 * 1024) { alert(T.ticket.logo_large); e.target.value = ""; return }
    const reader = new FileReader()
    reader.onload = () => this.setLogo(reader.result)
    reader.readAsDataURL(file)
  }

  removeLogo() { this.setLogo("") }

  setLogo(dataUrl) {
    this.logoTarget.value = dataUrl
    this.logoMiniTarget.src = dataUrl || "data:,"
    this.logoMiniTarget.classList.toggle("hidden", !dataUrl)
    this.noLogoTarget.classList.toggle("hidden", !!dataUrl)
    const n = this.node("logo")
    if (n) { n.querySelector("img").src = dataUrl || "data:,"; n.classList.toggle("hidden", !dataUrl) }
  }
}
