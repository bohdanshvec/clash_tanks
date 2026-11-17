
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.updateButton = this.updateButton.bind(this)

    document.addEventListener("fullscreenchange", this.updateButton)
    document.addEventListener("turbo:render", this.updateButton)

    this.updateButton()
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.updateButton)
    document.removeEventListener("turbo:render", this.updateButton)
  }

  buttonTargetConnected(button) {
    this.updateButtonElement(button)
  }

  async toggle() {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen()
      } else {
        await document.documentElement.requestFullscreen()
      }
    } catch (error) {
      console.error("Site fullscreen error:", error)
    }
  }

  updateButton() {
    this.buttonTargets.forEach((button) => {
      this.updateButtonElement(button)
    })
  }

  updateButtonElement(button) {
    const active =
      document.fullscreenElement === document.documentElement

    button.textContent = active
      ? "Звичайний режим"
      : "На весь екран"

    button.setAttribute("aria-pressed", String(active))
  }
}
