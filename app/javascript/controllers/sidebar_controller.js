import { Controller } from "@hotwired/stimulus"

// On a narrow screen the ribbon becomes a sidebar: this controller opens and closes it
// (menu button, dark backdrop, Escape).
export default class extends Controller {
  static targets = [ "panel", "backdrop" ]

  connect() { this.key = e => { if (e.key === "Escape") this.close() }; document.addEventListener("keydown", this.key) }
  disconnect() { document.removeEventListener("keydown", this.key) }

  open() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  toggle() { this.panelTarget.classList.contains("-translate-x-full") ? this.open() : this.close() }
}
