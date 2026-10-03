import { Controller } from "@hotwired/stimulus"

// Notice toasts: green ones go away by themselves after 6 s, red ones stay until closed.
export default class extends Controller {
  static targets = ["notice"]

  connect() {
    this.timers = this.noticeTargets
      .filter(a => a.classList.contains("bg-green-50"))
      .map(a => setTimeout(() => this.remove(a), 6000))
  }

  disconnect() { this.timers?.forEach(clearTimeout) }

  close(e) { this.remove(e.currentTarget.closest("[data-notice-target]")) }

  remove(notice) {
    if (!notice) return
    notice.style.transition = "opacity .3s"
    notice.style.opacity = "0"
    setTimeout(() => notice.remove(), 300)
  }
}
