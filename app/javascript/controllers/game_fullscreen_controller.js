import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.updateButton = this.updateButton.bind(this)

    document.addEventListener("fullscreenchange", this.updateButton)

    this.updateButton()
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.updateButton)
  }

  async toggle() {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen()
      } else {
        await this.element.requestFullscreen()
      }
    } catch (error) {
      console.error("Fullscreen error:", error)
    }
  }

  updateButton() {
    const active = document.fullscreenElement === this.element

    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = active
        ? "Звичайний режим"
        : "На весь екран"

      this.buttonTarget.setAttribute(
        "aria-pressed",
        String(active)
      )
    }
  }
}