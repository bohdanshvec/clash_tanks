import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static EFFECTS = {
    muzzle: 100,
    projectile: 210,
    impactProjectile: 180,
    impact: 220
  }

  connect() {
    this.queue = []
    this.processing = false
    this.lastGameElement = null
    this.animations = new Set()

    this.observer = new MutationObserver(() => {
      this.consumeCurrentGame()
    })

    this.observer.observe(this.element, {
      childList: true,
      subtree: true
    })

    this.boundBlockInteraction =
      this.blockInteraction.bind(this)

    this.interactionEvents = [
      "click",
      "submit",
      "dragstart",
      "dragover",
      "drop",
      "keydown"
    ]

    this.interactionEvents.forEach((eventName) => {
      this.element.addEventListener(
        eventName,
        this.boundBlockInteraction,
        true
      )
    })

    this.consumeCurrentGame()
  }

  disconnect() {
    this.observer?.disconnect()

    this.interactionEvents?.forEach((eventName) => {
      this.element.removeEventListener(
        eventName,
        this.boundBlockInteraction,
        true
      )
    })

    this.animations?.forEach((animation) => {
      animation.cancel()
    })

    this.animations?.clear()

    this.queue = []
    this.setLocked(false)
  }

  // --------------------------------------------------
  // Получение событий после Turbo-обновления
  // --------------------------------------------------

  consumeCurrentGame() {
    const game = this.element.querySelector(".game")

    if (!game || game === this.lastGameElement) return

    this.lastGameElement = game

    let events = []

    try {
      events = JSON.parse(
        game.dataset.gameEventsEventsValue || "[]"
      )
    } catch (error) {
      console.error(
        "[Game Combat Effects] Invalid events:",
        error
      )

      return
    }

    this.enqueueEvents(events)
  }

  enqueueEvents(events) {
    const combatEvents = events.filter((event) => {
      return [
        "shot_fired",
        "counterattack_fired"
      ].includes(event.type)
    })

    if (combatEvents.length === 0) return

    this.queue.push(...combatEvents)

    if (!this.processing) {
      this.playQueue()
    }
  }

  // --------------------------------------------------
  // Очередь боевых эффектов
  // --------------------------------------------------

  async playQueue() {
    if (this.processing) return

    this.processing = true
    this.setLocked(true)

    try {
      while (this.queue.length > 0) {
        const event = this.queue.shift()

        await this.animateShot(event)
      }
    } finally {
      this.processing = false
      this.setLocked(false)

      if (this.queue.length > 0) {
        this.playQueue()
      }
    }
  }

  // --------------------------------------------------
  // Выстрел и попадание
  // --------------------------------------------------

  async animateShot(event) {
    const attackerPosition = event.attacker?.position
    const targetPosition = event.target?.position

    if (!attackerPosition || !targetPosition) return

    const attackerCell = this.findCell(attackerPosition)
    const targetCell = this.findCell(targetPosition)

    if (!attackerCell || !targetCell) return

    const attackerRect = attackerCell.getBoundingClientRect()
    const targetRect = targetCell.getBoundingClientRect()

    const directionX =
      targetRect.left + targetRect.width / 2 -
      (attackerRect.left + attackerRect.width / 2)

    const directionY =
      targetRect.top + targetRect.height / 2 -
      (attackerRect.top + attackerRect.height / 2)

    if (directionX === 0 && directionY === 0) return

    const angle = Math.atan2(
      directionY,
      directionX
    ) * 180 / Math.PI

    const sourceOffset = this.edgeOffset(
      attackerRect,
      directionX,
      directionY
    )

    const targetOffset = this.edgeOffset(
      targetRect,
      -directionX,
      -directionY
    )

    const reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches

    // Вспышка в центре клетки атакующего.
    await this.animateMuzzleFlash(attackerCell)

    if (reducedMotion) {
      await this.animateImpact(targetCell)
      return
    }

    // Снаряд движется от центра клетки атакующего
    // к ближайшей границе в направлении цели.
    await this.animateProjectile(
      attackerCell,
      sourceOffset,
      angle
    )

    // В клетке цели снаряд появляется со стороны
    // атакующего и движется к центру.
    await this.animateIncomingProjectile(
      targetCell,
      targetOffset,
      angle
    )

    // Вспышка попадания в центре клетки цели.
    await this.animateImpact(targetCell)
  }

  // --------------------------------------------------
  // Расчёт точки пересечения с границей клетки
  // --------------------------------------------------

  edgeOffset(rect, directionX, directionY) {
    const halfWidth = Math.max(rect.width / 2 - 8, 1)
    const halfHeight = Math.max(rect.height / 2 - 8, 1)

    const scaleX =
      directionX === 0
        ? Infinity
        : halfWidth / Math.abs(directionX)

    const scaleY =
      directionY === 0
        ? Infinity
        : halfHeight / Math.abs(directionY)

    const scale = Math.min(scaleX, scaleY)

    return {
      x: directionX * scale,
      y: directionY * scale
    }
  }

  // --------------------------------------------------
  // Вспышка выстрела
  // --------------------------------------------------

  async animateMuzzleFlash(cell) {
    const flash = this.createEffect(
      cell,
      "game-combat-effect--muzzle"
    )

    await this.playAnimation(
      flash,
      [
        {
          opacity: 0,
          transform: "translate(-50%, -50%) scale(0.3)"
        },
        {
          opacity: 1,
          transform: "translate(-50%, -50%) scale(1.2)"
        },
        {
          opacity: 0,
          transform: "translate(-50%, -50%) scale(0.5)"
        }
      ],
      {
        duration: this.constructor.EFFECTS.muzzle,
        easing: "ease-out"
      }
    )

    flash.remove()
  }

  // --------------------------------------------------
  // Снаряд в клетке атакующего
  // --------------------------------------------------

  async animateProjectile(cell, offset, angle) {
    const projectile = this.createEffect(
      cell,
      "game-combat-effect--projectile"
    )

    const start = `translate(-50%, -50%) rotate(${angle}deg)`

    const end =
      `translate(calc(-50% + ${offset.x}px), ` +
      `calc(-50% + ${offset.y}px)) ` +
      `rotate(${angle}deg)`

    await this.playAnimation(
      projectile,
      [
        { transform: start, opacity: 1 },
        { transform: end, opacity: 0.2 }
      ],
      {
        duration: this.constructor.EFFECTS.projectile,
        easing: "ease-in"
      }
    )

    projectile.remove()
  }

  // --------------------------------------------------
  // Входящий снаряд в клетке цели
  // --------------------------------------------------

  async animateIncomingProjectile(cell, offset, angle) {
    const projectile = this.createEffect(
      cell,
      "game-combat-effect--projectile"
    )

    const start =
      `translate(calc(-50% + ${offset.x}px), ` +
      `calc(-50% + ${offset.y}px)) ` +
      `rotate(${angle}deg)`

    const end = `translate(-50%, -50%) rotate(${angle}deg)`

    await this.playAnimation(
      projectile,
      [
        { transform: start, opacity: 0.2 },
        { transform: end, opacity: 1 }
      ],
      {
        duration: this.constructor.EFFECTS.impactProjectile,
        easing: "ease-out"
      }
    )

    projectile.remove()
  }

  // --------------------------------------------------
  // Вспышка попадания
  // --------------------------------------------------

  async animateImpact(cell) {
    const impact = this.createEffect(
      cell,
      "game-combat-effect--impact"
    )

    await this.playAnimation(
      impact,
      [
        {
          opacity: 0,
          transform: "translate(-50%, -50%) scale(0.2)"
        },
        {
          opacity: 1,
          transform: "translate(-50%, -50%) scale(1.2)"
        },
        {
          opacity: 0,
          transform: "translate(-50%, -50%) scale(1.8)"
        }
      ],
      {
        duration: window.matchMedia(
          "(prefers-reduced-motion: reduce)"
        ).matches ? 140 : this.constructor.EFFECTS.impact,
        easing: "ease-out"
      }
    )

    impact.remove()
  }

  // --------------------------------------------------
  // Создание визуального элемента
  // --------------------------------------------------

  createEffect(cell, className) {
    const element = document.createElement("div")

    element.className = `game-combat-effect ${className}`
    element.setAttribute("aria-hidden", "true")

    cell.appendChild(element)

    return element
  }

  // --------------------------------------------------
  // Запуск и отслеживание анимации
  // --------------------------------------------------

  async playAnimation(element, keyframes, options) {
    const animation = element.animate(
      keyframes,
      {
        fill: "forwards",
        ...options
      }
    )

    this.animations.add(animation)

    try {
      await animation.finished
    } catch {
      // Анимация могла быть отменена при отключении контроллера.
    } finally {
      this.animations.delete(animation)
    }
  }

  // --------------------------------------------------
  // Временная блокировка игровых действий
  // --------------------------------------------------

  setLocked(locked) {
    this.element.classList.toggle(
      "game-combat-effects--locked",
      locked
    )

    if (locked) {
      this.element.setAttribute("aria-busy", "true")
    } else {
      this.element.removeAttribute("aria-busy")
    }
  }

  blockInteraction(event) {
    if (!this.processing) return

    const target = event.target

    if (!(target instanceof Element)) return

    const blockedElement = target.closest(
      [
        ".game-action--move",
        ".game-action--attack",
        ".game-action--card",
        ".game-action--card-target",
        ".game-action--drop-zone",
        "[data-card-id]",
        "[data-object-type]",
        ".game-board__action--end-turn"
      ].join(", ")
    )

    if (!blockedElement) return

    event.preventDefault()
    event.stopImmediatePropagation()
  }

  // --------------------------------------------------
  // Поиск клетки
  // --------------------------------------------------

  findCell(position) {
    if (!Array.isArray(position)) return null

    const [row, column] = position

    return this.element.querySelector(
      `.battlefield__cell[data-position="${row},${column}"]`
    )
  }
}