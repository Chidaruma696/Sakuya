import { Controller } from "@hotwired/stimulus"

// "Install the app" button: only shows up when the browser offers to install (beforeinstallprompt) and
// the app is not installed yet; pressing it opens the native dialog.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.onOffer = (e) => { e.preventDefault(); this.event = e; this.show(true) }
    this.onInstall = () => { this.event = null; this.show(false) }
    window.addEventListener("beforeinstallprompt", this.onOffer)
    window.addEventListener("appinstalled", this.onInstall)
    if (window.pwaEvent) { this.event = window.pwaEvent; this.show(true) }
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onOffer)
    window.removeEventListener("appinstalled", this.onInstall)
  }

  show(visible) { this.buttonTargets.forEach((b) => b.classList.toggle("hidden", !visible)) }

  async install() {
    if (!this.event) return
    this.event.prompt()
    const { outcome } = await this.event.userChoice
    if (outcome === "accepted") this.show(false)
  }
}
