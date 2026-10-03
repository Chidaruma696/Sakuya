import { Controller } from "@hotwired/stimulus"

// Closing the shift: as bills and coins are counted, the sum drops into "cash counted" by itself and
// the difference against the expected amount is shown. If the total is typed directly, the denominations are cleared.
export default class extends Controller {
  static targets = ["quantity", "counted", "sum", "difference", "reason"]
  static values = { expected: Number, cap: Number, symbol: String }

  add_up() {
    const cents = this.quantityTargets.reduce((total, input) => total + (parseInt(input.value, 10) || 0) * parseInt(input.dataset.value, 10), 0)
    this.countedTarget.value = (cents / 100).toFixed(2)
    this.render(cents)
  }

  typed() {
    this.quantityTargets.forEach((input) => { input.value = "" })
    this.render(Math.round((parseFloat(this.countedTarget.value) || 0) * 100))
  }

  render(cents) {
    const difference = cents - this.expectedValue
    this.sumTarget.textContent = this.format_money(cents)
    this.differenceTarget.textContent = this.format_money(difference)
    this.differenceTarget.classList.toggle("text-red-700", difference < 0)
    this.differenceTarget.classList.toggle("text-green-700", difference >= 0)
    if (this.hasReasonTarget) this.reasonTarget.classList.toggle("hidden", !(this.capValue > 0 && Math.abs(difference) > this.capValue))
  }

  format_money(cents) {
    const sign = cents < 0 ? "−" : ""
    return `${sign}${this.symbolValue}${(Math.abs(cents) / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }
}
