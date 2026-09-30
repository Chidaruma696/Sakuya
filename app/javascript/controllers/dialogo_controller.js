import { Controller } from "@hotwired/stimulus"

// Un <dialog> nativo que se abre desde cualquier botón dentro del mismo controlador
// (por ejemplo el "Acerca de" desde el logo de la cinta).
export default class extends Controller {
  static targets = [ "dialogo" ]

  abrir() { if (!this.dialogoTarget.open) this.dialogoTarget.showModal() }
  cerrar() { this.dialogoTarget.close() }
  cerrarFuera(e) { if (e.target === this.dialogoTarget) this.cerrar() }
}
