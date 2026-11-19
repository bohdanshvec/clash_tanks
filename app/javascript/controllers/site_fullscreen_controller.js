
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.updateButton = this.updateButton.bind(this)
    this.handleFullscreenChange = this.handleFullscreenChange.bind(this)
    this.handleTurboRender = this.handleTurboRender.bind(this)
    this.resizeMobileLayout = this.resizeMobileLayout.bind(this)

    this.mobileModeActive =
      this.element.classList.contains("mobile-game-fullscreen")

    this.lastFullscreenState = Boolean(document.fullscreenElement)

    document.addEventListener("fullscreenchange", this.handleFullscreenChange)
    document.addEventListener("turbo:render", this.handleTurboRender)
    document.addEventListener("turbo:load", this.handleTurboRender)

    window.addEventListener("resize", this.resizeMobileLayout)
    window.addEventListener("orientationchange", this.resizeMobileLayout)

    window.visualViewport?.addEventListener(
      "resize",
      this.resizeMobileLayout
    )

    window.visualViewport?.addEventListener(
      "scroll",
      this.resizeMobileLayout
    )

    this.refreshGameContent()
    this.updateButton()
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.handleFullscreenChange)
    document.removeEventListener("turbo:render", this.handleTurboRender)
    document.removeEventListener("turbo:load", this.handleTurboRender)

    window.removeEventListener("resize", this.resizeMobileLayout)
    window.removeEventListener("orientationchange", this.resizeMobileLayout)

    window.visualViewport?.removeEventListener(
      "resize",
      this.resizeMobileLayout
    )

    window.visualViewport?.removeEventListener(
      "scroll",
      this.resizeMobileLayout
    )

    this.clearMobileLayout()
  }

  buttonTargetConnected(button) {
    this.updateButtonElement(button)
  }

  async toggle() {
    if (this.isMobileDevice()) {
      await this.toggleMobileMode()
      return
    }

    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen()
      } else {
        await document.documentElement.requestFullscreen()
      }
    } catch (error) {
      console.error("Site fullscreen error:", error)
    }

    this.updateButton()
  }

  async toggleMobileMode() {
    if (this.mobileModeActive) {
      this.deactivateMobileMode()

      if (document.fullscreenElement) {
        try {
          await document.exitFullscreen()
        } catch (error) {
          console.error("Site fullscreen exit error:", error)
        }
      }

      this.updateButton()
      return
    }

    this.mobileModeActive = true
    this.element.classList.add("mobile-game-fullscreen")

    this.refreshGameContent()
    this.resizeMobileLayout()
    this.updateButton()

    if (typeof document.documentElement.requestFullscreen === "function") {
      try {
        await document.documentElement.requestFullscreen()
      } catch (error) {
        console.info("Native fullscreen unavailable; using mobile layout.")
      }
    }

    this.refreshGameContent()
    this.resizeMobileLayout()
    this.updateButton()
  }

  isMobileDevice() {
    return (
      window.matchMedia("(pointer: coarse)").matches ||
      window.matchMedia("(hover: none)").matches
    )
  }

  refreshGameContent() {
    this.game = this.element.querySelector(".game")
    this.gameContent = this.element.querySelector(".game-content")

    if (!this.game || !this.gameContent) {
      return
    }

    this.resizeMobileLayout()
  }

  handleTurboRender() {
    this.refreshGameContent()
    this.updateButton()
  }

  handleFullscreenChange() {
    const active = Boolean(document.fullscreenElement)

    if (this.lastFullscreenState && !active && this.mobileModeActive) {
      this.deactivateMobileMode()
    }

    this.lastFullscreenState = active

    this.updateButton()
    this.resizeMobileLayout()
  }

  resizeMobileLayout() {
    if (
      !this.mobileModeActive ||
      !this.game ||
      !this.gameContent ||
      !this.game.isConnected ||
      !this.gameContent.isConnected
    ) {
      return
    }

    // offsetWidth/offsetHeight не зависят от CSS transform.
    // scrollWidth/scrollHeight учитывают содержимое, выходящее за границы.
    const contentWidth = Math.max(
      this.gameContent.offsetWidth,
      this.gameContent.scrollWidth
    )

    const contentHeight = Math.max(
      this.gameContent.offsetHeight,
      this.gameContent.scrollHeight
    )

    const gameStyles = window.getComputedStyle(this.game)

    const paddingLeft = parseFloat(gameStyles.paddingLeft) || 0
    const paddingRight = parseFloat(gameStyles.paddingRight) || 0
    const paddingTop = parseFloat(gameStyles.paddingTop) || 0
    const paddingBottom = parseFloat(gameStyles.paddingBottom) || 0

    const availableWidth =
      this.game.clientWidth - paddingLeft - paddingRight

    const availableHeight =
      this.game.clientHeight - paddingTop - paddingBottom

    if (
      contentWidth <= 0 ||
      contentHeight <= 0 ||
      availableWidth <= 0 ||
      availableHeight <= 0
    ) {
      return
    }

    // Единый коэффициент для всей игровой композиции.
    const scale = Math.min(
      availableWidth / contentWidth,
      availableHeight / contentHeight,
      1
    )

    this.gameContent.style.setProperty(
      "--game-scale",
      String(scale)
    )
  }

  deactivateMobileMode() {
    this.mobileModeActive = false
    this.element.classList.remove("mobile-game-fullscreen")

    this.clearMobileLayout()
  }

  clearMobileLayout() {
    this.gameContent?.style.removeProperty("--game-scale")
  }

  updateButton() {
    this.buttonTargets.forEach((button) => {
      this.updateButtonElement(button)
    })
  }

  updateButtonElement(button) {
    const active =
      document.fullscreenElement === document.documentElement ||
      this.mobileModeActive

    button.textContent = active
      ? "Звичайний режим"
      : "На весь екран"

    button.setAttribute("aria-pressed", String(active))
  }
}
