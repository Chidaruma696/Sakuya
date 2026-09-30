import { Controller } from "@hotwired/stimulus"

// Conteo nuevo: enseña la línea y los productos solo cuando el alcance es parcial.
export default class extends Controller {
  static targets = ["parcial"]

  cambiar(event) {
    const parcial = event.target.value === "parcial"
    this.parcialTarget.classList.toggle("hidden", !parcial)
    this.parcialTarget.classList.toggle("grid", parcial)
  }
}
