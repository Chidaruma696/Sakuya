import { Controller } from "@hotwired/stimulus"

// A native <dialog> opened from any button inside the same controller
// (for example "About" from the ribbon logo).
export default class extends Controller {
  static targets = [ "dialog" ]

  open() { if (!this.dialogTarget.open) this.dialogTarget.showModal() }
  close() { this.dialogTarget.close() }
  closeOutside(e) { if (e.target === this.dialogTarget) this.close() }
}
