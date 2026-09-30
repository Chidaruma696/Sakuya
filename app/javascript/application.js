// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Turbo cambia el <body> pero no toca los atributos de <html>, y ahí viven el idioma, el tema,
// la densidad y la letra del usuario: se copian del documento nuevo en cada render.
// PWA: con el service worker registrado, el navegador ofrece instalar Sakuya como app.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker", { scope: "/" }).then((reg) => {
    // Versión nueva desplegada: avisar y ofrecer recargar, en vez de dejar al usuario con la vieja.
    reg.addEventListener("updatefound", () => {
      const nuevo = reg.installing
      nuevo?.addEventListener("statechange", () => {
        if (nuevo.state === "installed" && navigator.serviceWorker.controller) avisarActualizacion()
      })
    })
  }).catch(() => {})
}
window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); window.pwaEvento = e })

function avisarActualizacion() {
  if (document.getElementById("aviso-actualizacion")) return
  const caja = document.createElement("div")
  caja.id = "aviso-actualizacion"
  caja.className = "fixed inset-x-0 bottom-4 z-50 flex justify-center px-4"
  caja.innerHTML = `<div class="flex items-center gap-3 rounded-lg border border-marca-300 bg-white px-4 py-2 text-sm shadow-lg"><i class="bi bi-arrow-repeat text-marca-600"></i><span>${T.pwa.version_nueva}</span><button type="button" class="btn btn-primary btn-sm">${T.pwa.recargar}</button></div>`
  caja.querySelector("button").addEventListener("click", () => location.reload())
  document.body.appendChild(caja)
}

// Lo que se pega debajo de la cinta (banner del pedido, vista previa del ticket) necesita saber cuánto mide.
const medirCinta = () => document.documentElement.style.setProperty("--cinta-alto", `${document.getElementById("cinta")?.offsetHeight || 0}px`)
document.addEventListener("turbo:load", medirCinta)
window.addEventListener("resize", medirCinta)
document.addEventListener("change", (e) => { if (e.target.name?.startsWith("usuario[")) setTimeout(medirCinta, 50) })

document.addEventListener("turbo:before-render", (e) => {
  const nuevo = e.detail.newBody?.ownerDocument?.documentElement
  if (!nuevo) return
  for (const a of ["lang", "data-theme", "data-densidad", "data-letra"]) {
    const v = nuevo.getAttribute(a)
    if (v !== null) document.documentElement.setAttribute(a, v)
  }
})
