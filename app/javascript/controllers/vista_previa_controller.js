import { Controller } from "@hotwired/stimulus"

// «Probar» del editor en Lisp: manda el programa sin guardar y enseña cómo queda en un modal,
// sin salir del editor. Sin JavaScript, el botón sigue funcionando como un envío normal.
export default class extends Controller {
  static targets = [ "dialogo", "cuerpo" ]

  async probar(event) {
    event.preventDefault()
    const boton = event.currentTarget
    const formulario = boton.form
    boton.disabled = true
    this.cuerpoTarget.innerHTML = `<p class="py-10 text-center text-sm text-stone-500">${T.cargando}</p>`
    if (!this.dialogoTarget.open) this.dialogoTarget.showModal()
    const datos = new FormData(formulario)
    datos.set(boton.name, boton.value)
    try {
      // El token general de la página va en la cabecera, además del que trae el formulario.
      const r = await fetch(formulario.action, {
        method: "POST",
        body: datos,
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "" }
      })
      this.cuerpoTarget.innerHTML = await r.text()
    } catch {
      this.cuerpoTarget.innerHTML = `<p class="py-10 text-center text-sm text-red-800">${T.no_se_pudo}</p>`
    } finally {
      boton.disabled = false
    }
  }

  cerrar() { this.dialogoTarget.close() }
  cerrarFuera(e) { if (e.target === this.dialogoTarget) this.cerrar() }
}
