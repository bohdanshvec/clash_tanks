import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.scheduleLayout = this.scheduleLayout.bind(this)
    this.handleFullscreenChange = this.handleFullscreenChange.bind(this)
    this.handleTurboRender = this.handleTurboRender.bind(this)

    this.mobileModeActive =
      this.element.classList.contains("mobile-game-fullscreen")

    this.lastFullscreenState = Boolean(document.fullscreenElement)

    this.layoutFrame = null
    this.gameObserver = null
    this.observedGameContent = null

    document.addEventListener("fullscreenchange", this.handleFullscreenChange)
    document.addEventListener("turbo:render", this.handleTurboRender)
    document.addEventListener("turbo:load", this.handleTurboRender)

    window.addEventListener("resize", this.scheduleLayout)
    window.addEventListener("orientationchange", this.scheduleLayout)
    window.visualViewport?.addEventListener("resize", this.scheduleLayout)

    this.syncGameState()
    this.updateButton()
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.handleFullscreenChange)
    document.removeEventListener("turbo:render", this.handleTurboRender)
    document.removeEventListener("turbo:load", this.handleTurboRender)

    window.removeEventListener("resize", this.scheduleLayout)
    window.removeEventListener("orientationchange", this.scheduleLayout)
    window.visualViewport?.removeEventListener("resize", this.scheduleLayout)

    if (this.layoutFrame) {
      window.cancelAnimationFrame(this.layoutFrame)
      this.layoutFrame = null
    }

    this.gameObserver?.disconnect()
    this.gameObserver = null
    this.observedGameContent = null

    this.clearMobileLayout()
  }

  buttonTargetConnected(button) {
    this.updateButtonElement(button)
  }

  // --------------------------------------------------
  // Кнопка «На весь екран»
  // --------------------------------------------------

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

    // Сначала включаем CSS-режим (работает и там, где нет Fullscreen API,
    // например на iPhone), затем пробуем настоящий полноэкранный режим.
    this.mobileModeActive = true
    this.syncGameState()
    this.updateButton()

    await this.enterNativeFullscreen()

    this.relayoutSoon()
    this.updateButton()
  }

  async enterNativeFullscreen() {
    const root = document.documentElement

    if (typeof root.requestFullscreen !== "function") return

    try {
      await root.requestFullscreen({ navigationUI: "hide" })
    } catch (error) {
      console.info("Native fullscreen unavailable; using mobile layout.")
      return
    }

    await this.lockLandscape()
  }

  async lockLandscape() {
    try {
      await screen.orientation?.lock?.("landscape")
    } catch (error) {
      // Блокировка ориентации поддерживается не везде — это нормально.
    }
  }

  unlockOrientation() {
    try {
      screen.orientation?.unlock?.()
    } catch (error) {
      // Игнорируем.
    }
  }

  isMobileDevice() {
    return (
      window.matchMedia("(pointer: coarse)").matches ||
      window.matchMedia("(hover: none)").matches
    )
  }

  // --------------------------------------------------
  // Состояние страницы с игрой
  // --------------------------------------------------

  // Класс на <html> нужен только пока на странице есть игра.
  // Так на других страницах сайта прокрутка не блокируется.
  syncGameState() {
    const game = this.element.querySelector(".game")

    this.element.classList.toggle(
      "mobile-game-fullscreen",
      this.mobileModeActive && Boolean(game)
    )

    this.observeGameContent()
    this.scheduleLayout()
  }

  // Turbo Stream заменяет содержимое #game-content.
  // После каждой замены пересчитываем масштаб.
  observeGameContent() {
    const content = document.getElementById("game-content")

    if (content === this.observedGameContent) return

    this.gameObserver?.disconnect()
    this.gameObserver = null
    this.observedGameContent = content

    if (!content) return

    this.gameObserver = new MutationObserver(() => {
      this.scheduleLayout()
    })

    this.gameObserver.observe(content, { childList: true })
  }

  handleTurboRender() {
    this.syncGameState()
    this.updateButton()
  }

  handleFullscreenChange() {
    const active = Boolean(document.fullscreenElement)

    if (this.lastFullscreenState && !active && this.mobileModeActive) {
      this.deactivateMobileMode()
    }

    this.lastFullscreenState = active

    this.updateButton()
    this.relayoutSoon()
  }

  // --------------------------------------------------
  // Масштабирование игровой композиции
  // --------------------------------------------------

  scheduleLayout() {
    if (this.layoutFrame) return

    this.layoutFrame = window.requestAnimationFrame(() => {
      this.layoutFrame = null
      this.resizeMobileLayout()
    })
  }

  // Размеры окна на Android меняются с задержкой (скрытие адресной строки,
  // анимация входа в fullscreen), поэтому пересчитываем несколько раз.
  relayoutSoon() {
    this.scheduleLayout()

    ;[150, 400, 800].forEach((delay) => {
      window.setTimeout(this.scheduleLayout, delay)
    })
  }

  resizeMobileLayout() {
    if (!this.mobileModeActive) return

    const game = this.element.querySelector(".game")
    const gameContent = game?.querySelector(".game-content")

    if (!game || !gameContent) return

    // offsetWidth/offsetHeight не зависят от CSS transform.
    const contentWidth = gameContent.offsetWidth
    const contentHeight = gameContent.offsetHeight

    const gameStyles = window.getComputedStyle(game)

    const paddingLeft = parseFloat(gameStyles.paddingLeft) || 0
    const paddingRight = parseFloat(gameStyles.paddingRight) || 0
    const paddingTop = parseFloat(gameStyles.paddingTop) || 0
    const paddingBottom = parseFloat(gameStyles.paddingBottom) || 0

    const availableWidth = game.clientWidth - paddingLeft - paddingRight
    const availableHeight = game.clientHeight - paddingTop - paddingBottom

    if (
      contentWidth <= 0 ||
      contentHeight <= 0 ||
      availableWidth <= 0 ||
      availableHeight <= 0
    ) {
      return
    }

    // Единый коэффициент для всей игровой композиции.
    // Округляем вниз, чтобы не получить лишний пиксель за краем экрана.
    const scale = Math.min(
      availableWidth / contentWidth,
      availableHeight / contentHeight,
      1
    )

    // Переменная хранится на <html>, чтобы переживать замену .game
    // при обновлениях через Turbo Stream.
    this.element.style.setProperty(
      "--game-scale",
      String(Math.floor(scale * 1000) / 1000)
    )
  }

  deactivateMobileMode() {
    this.mobileModeActive = false
    this.element.classList.remove("mobile-game-fullscreen")

    this.unlockOrientation()
    this.clearMobileLayout()
  }

  clearMobileLayout() {
    this.element.style.removeProperty("--game-scale")
  }

  // --------------------------------------------------
  // Кнопка
  // --------------------------------------------------

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