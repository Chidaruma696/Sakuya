import { Controller } from "@hotwired/stimulus"

// "Are you still there?": after a while without a key, a click, a touch or a scan, a dialog asks
// with a clock counting down; answering keeps the session, the clock reaching zero signs this
// device out. The server holds the same limit on its side (UserSession), so this is the courtesy
// of asking first, not the lock. Activity is shared between tabs; offline nothing closes, because
// a till without a network could not sign back in.
const SHARED = "sakuya-last-activity"
const TELL_SERVER_EVERY = 60_000 // while someone works without loading pages (a long ticket)

export default class extends Controller {
  static targets = ["dialog", "clock"]
  static values = { after: Number, countdown: Number, keepUrl: String, logoutUrl: String, loginUrl: String }

  connect() {
    this.last = this.told = Date.now()
    this.asking = false
    this.onActivity = () => this.active()
    this.events = ["keydown", "pointerdown", "input", "wheel", "touchstart"]
    this.events.forEach((e) => window.addEventListener(e, this.onActivity, { capture: true, passive: true }))
    this.onCancel = (e) => e.preventDefault() // Esc does not answer for anyone
    this.dialogTarget.addEventListener("cancel", this.onCancel)
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    this.events.forEach((e) => window.removeEventListener(e, this.onActivity, { capture: true }))
    this.dialogTarget.removeEventListener("cancel", this.onCancel)
    clearInterval(this.timer)
  }

  // While it is asking, only the button answers: a stray key or a cat on the keyboard does not.
  active() {
    if (this.asking) return
    this.last = Date.now()
    this.share()
    if (this.last - this.told > TELL_SERVER_EVERY) this.keep()
  }

  share() {
    try { localStorage.setItem(SHARED, String(this.last)) } catch { /* private mode: each tab on its own */ }
  }

  tick() {
    const now = Date.now()
    if (!navigator.onLine) { this.last = now; return }
    let shared = 0
    try { shared = Number(localStorage.getItem(SHARED) || 0) } catch { /* see share() */ }
    if (shared > this.last) {
      // Someone is working in another tab of this same session.
      this.last = shared
      if (this.asking) this.close()
    }
    const idle = (now - this.last) / 1000
    if (!this.asking && idle >= this.afterValue) this.ask()
    if (!this.asking) return
    const left = Math.ceil(this.countdownValue - (idle - this.afterValue))
    if (left <= 0) return this.signOut()
    this.clockTarget.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`
  }

  ask() {
    this.asking = true
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    this.asking = false
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  stay() {
    this.close()
    this.last = Date.now()
    this.share()
    this.keep()
  }

  // Tells the server someone is here. If the session is already gone there, there is nothing to keep.
  async keep() {
    this.told = Date.now()
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const r = await fetch(this.keepUrlValue, { method: "POST", headers: { "X-CSRF-Token": token || "", Accept: "application/json" } }).catch(() => null)
    if (r?.status === 401) window.location.assign(this.loginUrlValue)
  }

  // Nobody answered: sign this device out the ordinary way, saying why.
  signOut() {
    clearInterval(this.timer)
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.logoutUrlValue
    const fields = { _method: "delete", idle: "1", authenticity_token: document.querySelector("meta[name=csrf-token]")?.content || "" }
    for (const [name, value] of Object.entries(fields)) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.append(input)
    }
    document.body.append(form)
    form.submit()
  }
}
