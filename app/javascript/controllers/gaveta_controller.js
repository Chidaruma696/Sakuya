import { Controller } from "@hotwired/stimulus"

// Cierre del corte: al contar billetes y monedas, la suma cae sola en "efectivo contado" y se
// enseña la diferencia contra lo esperado. Si se teclea el total directo, las denominaciones se vacían.
export default class extends Controller {
  static targets = ["cantidad", "contado", "suma", "diferencia", "motivo"]
  static values = { esperado: Number, tope: Number, simbolo: String }

  sumar() {
    const centavos = this.cantidadTargets.reduce((total, input) => total + (parseInt(input.value, 10) || 0) * parseInt(input.dataset.valor, 10), 0)
    this.contadoTarget.value = (centavos / 100).toFixed(2)
    this.pintar(centavos)
  }

  tecleado() {
    this.cantidadTargets.forEach((input) => { input.value = "" })
    this.pintar(Math.round((parseFloat(this.contadoTarget.value) || 0) * 100))
  }

  pintar(centavos) {
    const diferencia = centavos - this.esperadoValue
    this.sumaTarget.textContent = this.pesos(centavos)
    this.diferenciaTarget.textContent = this.pesos(diferencia)
    this.diferenciaTarget.classList.toggle("text-red-700", diferencia < 0)
    this.diferenciaTarget.classList.toggle("text-green-700", diferencia >= 0)
    if (this.hasMotivoTarget) this.motivoTarget.classList.toggle("hidden", !(this.topeValue > 0 && Math.abs(diferencia) > this.topeValue))
  }

  pesos(centavos) {
    const signo = centavos < 0 ? "−" : ""
    return `${signo}${this.simboloValue}${(Math.abs(centavos) / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }
}
