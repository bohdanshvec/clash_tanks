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
    if (!this.hasButtonTarget) return

    const active =
      document.fullscreenElement === document.documentElement

    this.buttonTarget.textContent = active
      ? "Звичайний режим"
      : "На весь екран"

    this.buttonTarget.setAttribute(
      "aria-pressed",
      String(active)
    )
  }
}