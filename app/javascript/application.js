// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// PWA: with the service worker registered, the browser offers to install Sakuya as an app.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker", { scope: "/" }).then((reg) => {
    // New version deployed: tell the user and offer to reload, instead of leaving them on the old one.
    reg.addEventListener("updatefound", () => {
      const incoming = reg.installing
      incoming?.addEventListener("statechange", () => {
        if (incoming.state === "installed" && navigator.serviceWorker.controller) notifyUpdate()
      })
    })
  }).catch(() => {})
}
window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); window.pwaEvent = e })

function notifyUpdate() {
  if (document.getElementById("notice-update")) return
  const box = document.createElement("div")
  box.id = "notice-update"
  box.className = "fixed inset-x-0 bottom-4 z-50 flex justify-center px-4"
  box.innerHTML = `<div class="flex items-center gap-3 rounded-lg border border-brand-300 bg-white px-4 py-2 text-sm shadow-lg"><i class="bi bi-arrow-repeat text-brand-600"></i><span>${T.pwa.new_version}</span><button type="button" class="btn btn-primary btn-sm">${T.pwa.reload}</button></div>`
  box.querySelector("button").addEventListener("click", () => location.reload())
  document.body.appendChild(box)
}

// Whatever sticks below the ribbon (the order banner, the ticket preview) needs to know how tall it is.
const measureRibbon = () => document.documentElement.style.setProperty("--ribbon-height", `${document.getElementById("ribbon")?.offsetHeight || 0}px`)
document.addEventListener("turbo:load", measureRibbon)
window.addEventListener("resize", measureRibbon)
document.addEventListener("change", (e) => { if (e.target.name?.startsWith("user[")) setTimeout(measureRibbon, 50) })

// Turbo swaps the <body> but leaves the <html> attributes alone, and that is where the user's
// language, theme, density and text size live: copy them from the new document on every render.
document.addEventListener("turbo:before-render", (e) => {
  const incoming = e.detail.newBody?.ownerDocument?.documentElement
  if (!incoming) return
  for (const a of ["lang", "data-theme", "data-density", "data-text-size"]) {
    const v = incoming.getAttribute(a)
    if (v !== null) document.documentElement.setAttribute(a, v)
  }
})
