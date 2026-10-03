import { Controller } from "@hotwired/stimulus"
import { pendientes } from "sin_conexion"

// En la pantalla del corte: avisa si en este equipo quedan ventas hechas sin conexión por subir,
// para no cerrar la caja sin ellas.
export default class extends Controller {
  async connect() {
    const n = (await pendientes().catch(() => [])).length
    this.element.hidden = n === 0
    this.element.textContent = (n === 1 ? T.pos.corte_pendiente : T.pos.corte_pendientes).replace("%{n}", n)
  }
}
