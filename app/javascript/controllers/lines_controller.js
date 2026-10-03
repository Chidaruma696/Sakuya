import { Controller } from "@hotwired/stimulus"

// Form line items: clones the first row with a new index and removes rows.
export default class extends Controller {
  static targets = ["body", "row"]

  add() {
    const template = this.rowTargets[0]
    const n = Date.now()
    const copy = template.cloneNode(true)
    copy.querySelectorAll("select, input").forEach(el => {
      el.name = el.name.replace(/\[\d+\]/, `[${n}]`)
      el.id = el.id.replace(/_\d+_/, `_${n}_`)
      if (el.tagName === "INPUT") el.value = ""
      else el.selectedIndex = 0
    })
    this.bodyTarget.appendChild(copy)
    copy.querySelector("select").focus()
  }

  remove(event) {
    if (this.rowTargets.length > 1) event.target.closest("tr").remove()
  }
}
