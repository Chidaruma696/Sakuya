import { Controller } from "@hotwired/stimulus"

// New stock count: shows the product line and products only when the scope is partial.
export default class extends Controller {
  static targets = ["partial"]

  change(event) {
    const partial = event.target.value === "partial"
    this.partialTarget.classList.toggle("hidden", !partial)
    this.partialTarget.classList.toggle("grid", partial)
  }
}
