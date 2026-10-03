import { Controller } from "@hotwired/stimulus"

// Ticket design: what is typed on the left shows up right away in the preview on the
// right (the real ticket inside an iframe, with its own styles).
export default class extends Controller {
  static targets = ["frame", "logo", "logoMini", "noLogo", "zoom"]

  get doc() { return this.frameTarget.contentDocument }

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
