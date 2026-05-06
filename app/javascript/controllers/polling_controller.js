import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["terminalStatus"]
  static values  = {
    status:   String,
    interval: { type: Number, default: 3000 }
  }

  connect() {
    if (!this.isTerminal(this.statusValue)) {
      this.timer = setInterval(() => this.poll(), this.intervalValue)
    }
  }

  // Force a fresh Turbo Frame load by removing then resetting src
  poll() {
    const src = this.element.getAttribute("src")
    if (src) {
      this.element.removeAttribute("src")
      this.element.setAttribute("src", src)
    }
  }

  // Fires when a terminal-status target appears inside the frame (complete or failed state rendered)
  terminalStatusTargetConnected() {
    this.stop()
  }

  statusValueChanged() {
    if (this.isTerminal(this.statusValue)) {
      this.stop()
    }
  }

  disconnect() {
    this.stop()
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  isTerminal(status) {
    return status === "complete" || status === "failed"
  }
}
