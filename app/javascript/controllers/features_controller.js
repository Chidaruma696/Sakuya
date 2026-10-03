import { Controller } from "@hotwired/stimulus"

// Feature switches: turning one on checks what it needs (and, if it needs "any of", the
// first one when none is on); turning one off unchecks those that need it and those left
// without any base. That way what reaches the server is already consistent and nothing is half on.
export default class extends Controller {
  static targets = ["toggle"]

  change(event) {
    const toggle = event.target
    const list = (el, field) => (el.dataset[field] || "").split(" ").filter(Boolean)
    if (toggle.checked) {
      list(toggle, "needs").forEach((m) => this.mark(m, true))
      const any = list(toggle, "any")
      if (any.length && !any.some((m) => this.toggle(m)?.checked)) this.mark(any[0], true)
    } else {
      list(toggle, "dependents").forEach((m) => this.mark(m, false))
      this.toggleTargets.forEach((other) => {
        const any = list(other, "any")
        if (other.checked && any.includes(toggle.dataset.feature) && !any.some((m) => this.toggle(m)?.checked)) this.mark(other.dataset.feature, false)
      })
    }
  }

  toggle(feature) { return this.toggleTargets.find((c) => c.dataset.feature === feature) }

  mark(feature, value) {
    const toggle = this.toggle(feature)
    if (toggle && toggle.checked !== value) {
      toggle.checked = value
      toggle.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }
}
