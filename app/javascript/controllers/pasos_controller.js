import { Controller } from "@hotwired/stimulus"

// Formulario por pasos: un solo <form>, un paso visible a la vez, Siguiente valida lo del paso y
// Anterior vuelve. Los controles de apariencia (tema, letra, densidad) se aplican al momento.
export default class extends Controller {
  static targets = ["paso", "indicador", "anterior", "siguiente", "enviar", "resumen"]
  static values = { inicial: { type: Number, default: 1 } }

  connect() {
    this.actual = Math.min(Math.max(this.inicialValue, 1), this.pasoTargets.length)
    this.pintar()
  }

  siguiente() {
    if (!this.valido()) return
    this.actual = Math.min(this.actual + 1, this.pasoTargets.length)
    this.pintar()
  }

  anterior() {
    this.actual = Math.max(this.actual - 1, 1)
    this.pintar()
  }

  // Cambiar tema, letra o densidad se ve al instante: los atributos viven en <html>.
  aplicar(e) {
    document.documentElement.setAttribute(`data-${e.target.dataset.atributo}`, e.target.value)
  }

  valido() {
    const paso = this.pasoTargets[this.actual - 1]
    for (const campo of paso.querySelectorAll("input, select")) {
      if (!campo.reportValidity()) { campo.focus(); return false }
    }
    return true
  }

  pintar() {
    this.pasoTargets.forEach((p, i) => p.classList.toggle("hidden", i !== this.actual - 1))
    this.indicadorTargets.forEach((ind, i) => {
      ind.classList.toggle("text-marca-800", i === this.actual - 1)
      ind.classList.toggle("font-bold", i === this.actual - 1)
      ind.classList.toggle("opacity-50", i > this.actual - 1)
    })
    const ultimo = this.actual === this.pasoTargets.length
    this.anteriorTarget.classList.toggle("invisible", this.actual === 1)
    this.siguienteTarget.classList.toggle("hidden", ultimo)
    this.enviarTarget.classList.toggle("hidden", !ultimo)
    if (ultimo) this.llenarResumen()
    this.pasoTargets[this.actual - 1].querySelector("input:not([type=hidden]):not([type=radio]), select")?.focus()
  }

  // El último paso repite lo capturado para revisarlo antes de crear.
  llenarResumen() {
    if (!this.hasResumenTarget) return
    for (const dd of this.resumenTarget.querySelectorAll("[data-campo]")) {
      const campo = this.element.querySelector(`[name="instalacion[${dd.dataset.campo}]"]:not([type=radio]), [name="instalacion[${dd.dataset.campo}]"]:checked`)
      let valor = campo?.value ?? ""
      if (campo?.tagName === "SELECT") valor = campo.selectedOptions[0]?.text ?? valor
      if (campo?.type === "radio") valor = campo.closest("label")?.textContent.trim() ?? valor
      if (campo?.type === "password") valor = "•".repeat(valor.length)
      dd.textContent = valor || dd.dataset.vacio || "—"
    }
  }
}
