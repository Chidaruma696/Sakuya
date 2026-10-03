import { Controller } from "@hotwired/stimulus"

// "Try" in the Lisp editor: sends the program without saving and shows the result in a modal,
// without leaving the editor. Without JavaScript, the button still works as a normal submit.
export default class extends Controller {
  static targets = [ "dialog", "body" ]

  async dryRun(event) {
    event.preventDefault()
    const button = event.currentTarget
    const form = button.form
    button.disabled = true
    this.bodyTarget.innerHTML = `<p class="py-10 text-center text-sm text-stone-500">${T.loading}</p>`
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    const data = new FormData(form)
    data.set(button.name, button.value)
    try {
      // The page-wide token goes in the header, on top of the one the form carries.
      const r = await fetch(form.action, {
        method: "POST",
        body: data,
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "" }
      })
      this.bodyTarget.innerHTML = await r.text()
    } catch {
      this.bodyTarget.innerHTML = `<p class="py-10 text-center text-sm text-red-800">${T.load_failed}</p>`
    } finally {
      button.disabled = false
    }
  }

  close() { this.dialogTarget.close() }
  closeOutside(e) { if (e.target === this.dialogTarget) this.close() }
}
