import { Controller } from "@hotwired/stimulus"
import { pending } from "offline"

// On the shift screen: warns if this device still has offline sales waiting to upload,
// so the till is not closed without them.
export default class extends Controller {
  async connect() {
    const n = (await pending().catch(() => [])).length
    this.element.hidden = n === 0
    this.element.textContent = (n === 1 ? T.pos.shift_pending_one : T.pos.shift_pending_other).replace("%{n}", n)
  }
}
