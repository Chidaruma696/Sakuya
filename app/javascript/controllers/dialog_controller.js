import { Controller } from "@hotwired/stimulus"

// A native <dialog> opened from any button inside the same controller
// (for example "About" from the ribbon logo). With data-dialog-open-value="true" it comes up
// by itself, for a page that has something to ask before going on.
export default class extends Controller {
  static targets = [ "dialog" ]
  static values = { open: Boolean }

  connect() { if (this.openValue) this.open() }

  open() { if (!this.dialogTarget.open) this.dialogTarget.showModal() }
  close() { this.dialogTarget.close() }
  closeOutside(e) { if (e.target === this.dialogTarget) this.close() }
}
