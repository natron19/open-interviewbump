import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "container"]

  connect() {
    this._savedValues = {}
    this.update()
  }

  update() {
    const text = this.templateTarget.value
    const matches = [...text.matchAll(/\{\{(\w+)\}\}/g)]
    const names = [...new Set(matches.map(m => m[1]))]

    // Save values of inputs about to be removed, then remove them
    this.containerTarget.querySelectorAll("[data-var-name]").forEach(el => {
      const name = el.dataset.varName
      if (!names.includes(name)) {
        const input = el.querySelector("input")
        if (input) this._savedValues[name] = input.value
        el.remove()
      }
    })

    // Add inputs for new variables
    names.forEach(name => {
      if (!this.containerTarget.querySelector(`[data-var-name="${name}"]`)) {
        const value = this._savedValues[name] || ""
        const div = document.createElement("div")
        div.className = "mb-2"
        div.dataset.varName = name
        div.innerHTML = `
          <label class="form-label small text-muted">${name}</label>
          <input type="text" name="variables[${name}]" value="${value}"
                 class="form-control form-control-sm" placeholder="${name}">
        `
        this.containerTarget.appendChild(div)
      }
    })
  }
}
