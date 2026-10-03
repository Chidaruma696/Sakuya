import { Controller } from "@hotwired/stimulus"

// Multi-step form: a single <form>, one step visible at a time, Next validates the step and
// Back goes back. The appearance controls (theme, text size, density) apply immediately.
export default class extends Controller {
  static targets = ["step", "indicator", "previous", "next", "send", "summary"]
  static values = { initial: { type: Number, default: 1 } }

  connect() {
    this.current = Math.min(Math.max(this.initialValue, 1), this.stepTargets.length)
    this.render()
  }

  next() {
    if (!this.valid()) return
    this.current = Math.min(this.current + 1, this.stepTargets.length)
    this.render()
  }

  previous() {
    this.current = Math.max(this.current - 1, 1)
    this.render()
  }

  // Changing theme, text size or density shows instantly: the attributes live on <html>.
  apply(e) {
    document.documentElement.setAttribute(`data-${e.target.dataset.attribute}`, e.target.value)
  }

  valid() {
    const step = this.stepTargets[this.current - 1]
    for (const field of step.querySelectorAll("input, select")) {
      if (!field.reportValidity()) { field.focus(); return false }
    }
    return true
  }

  render() {
    this.stepTargets.forEach((p, i) => p.classList.toggle("hidden", i !== this.current - 1))
    this.indicatorTargets.forEach((indicator, i) => {
      indicator.classList.toggle("underline", i === this.current - 1)
      indicator.classList.toggle("font-bold", i === this.current - 1)
      indicator.classList.toggle("opacity-50", i > this.current - 1)
    })
    const last = this.current === this.stepTargets.length
    this.previousTarget.classList.toggle("invisible", this.current === 1)
    this.nextTarget.classList.toggle("hidden", last)
    this.sendTarget.classList.toggle("hidden", !last)
    if (last) this.fillSummary()
    this.stepTargets[this.current - 1].querySelector("input:not([type=hidden]):not([type=radio]), select")?.focus()
  }

  // The last step repeats what was entered so it can be checked before creating.
  fillSummary() {
    if (!this.hasSummaryTarget) return
    for (const dd of this.summaryTarget.querySelectorAll("[data-field]")) {
      const field = this.element.querySelector(`[name="setup[${dd.dataset.field}]"]:not([type=radio]), [name="setup[${dd.dataset.field}]"]:checked`)
      let value = field?.value ?? ""
      if (field?.tagName === "SELECT") value = field.selectedOptions[0]?.text ?? value
      if (field?.type === "radio") value = field.closest("label")?.textContent.trim() ?? value
      if (field?.type === "password") value = "•".repeat(value.length)
      dd.textContent = value || dd.dataset.empty || "—"
    }
  }
}
