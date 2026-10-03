import { Controller } from "@hotwired/stimulus"

// Folios step of the first-run setup: shows what the first ticket would look like with the chosen options.
export default class extends Controller {
  static targets = ["example", "own"]

  connect() { this.render() }

  render() {
    const form = this.element.closest("form")
    const mode = form.querySelector("[name='setup[folios_mode]']:checked")?.value || "per_document"
    const prefix = form.querySelector("[name='setup[folios_prefix]']:checked")?.value || "own"
    const code = (form.querySelector("[name='setup[code]']")?.value || "MTZ").trim().toUpperCase()
    const own = (form.querySelector("[name='setup[folios_sale]']")?.value || "").trim().toUpperCase()
    const parts = []
    if (prefix === "branch") parts.push(code)
    if (prefix === "own" && own) parts.push(own)
    if (prefix === "branch" && mode === "per_document") parts.push("B")
    parts.push("00001")
    this.exampleTarget.textContent = parts.join("-")
    this.ownTarget.classList.toggle("invisible", prefix !== "own")
  }
}
