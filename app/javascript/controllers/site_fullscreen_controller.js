
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.updateButton = this.updateButton.bind(this)
    this.handleFullscreenChange = this.handleFullscreenChange.bind(this)
    this.handleTurboRender = this.handleTurboRender.bind(this)
    this.resizeMobileLayout = this.resizeMobileLayout.bind(this)

    this.mobileModeActive = false
    this.lastFullscreenState = Boolean(document.fullscreenElement)

    document.addEventListener("fullscreenchange", this.handleFullscreenChange)
    document.addEventListener("turbo:render", this.handleTurboRender)

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

    this.deactivateMobileMode()
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

    this.resizeMobileLayout()
    this.updateButton()

    // CSS-адаптация продолжит работать, даже если браузер
    // не поддерживает Fullscreen API.
    if (typeof document.documentElement.requestFullscreen === "function") {
      try {
        await document.documentElement.requestFullscreen()
      } catch (error) {
        console.info("Native fullscreen unavailable; using mobile layout.")
      }
    }

    this.updateButton()
    this.resizeMobileLayout()
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

    if (!this.gameContent && this.mobileModeActive) {
      this.deactivateMobileMode()
    }

    this.resizeMobileLayout()
  }

  handleTurboRender() {
    this.refreshGameContent()
    this.updateButton()
  }

  handleFullscreenChange() {
    const active = Boolean(document.fullscreenElement)

    // Выход через системную кнопку браузера или Escape.
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
      !this.gameContent
    ) {
      return
    }

    // Сначала возвращаем исходный размер для измерения.
    this.gameContent.style.setProperty("--game-scale", "1")

    const contentRect = this.gameContent.getBoundingClientRect()
    const gameStyles = window.getComputedStyle(this.game)

    const paddingLeft = parseFloat(gameStyles.paddingLeft) || 0
    const paddingRight = parseFloat(gameStyles.paddingRight) || 0
    const paddingTop = parseFloat(gameStyles.paddingTop) || 0
    const paddingBottom = parseFloat(gameStyles.paddingBottom) || 0

    const viewport = window.visualViewport

    const viewportWidth =
      viewport?.width || document.documentElement.clientWidth

    const viewportHeight =
      viewport?.height || window.innerHeight

    const availableWidth =
      viewportWidth - paddingLeft - paddingRight

    const availableHeight =
      viewportHeight - paddingTop - paddingBottom

    if (
      contentRect.width <= 0 ||
      contentRect.height <= 0 ||
      availableWidth <= 0 ||
      availableHeight <= 0
    ) {
      return
    }

    const scale = Math.min(
      availableWidth / contentRect.width,
      availableHeight / contentRect.height,
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
