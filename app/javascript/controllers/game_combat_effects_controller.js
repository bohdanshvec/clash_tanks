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
    this.destroyedVisuals = new Map()
    this.destroyedPlatoonVisuals = new Map()

    this.boundBeforeStreamRender =
      this.beforeStreamRender.bind(this)

    document.addEventListener(
      "turbo:before-stream-render",
      this.boundBeforeStreamRender
    )

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
    document.removeEventListener(
      "turbo:before-stream-render",
      this.boundBeforeStreamRender
    )

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

    this.destroyedVisuals?.clear()
    this.destroyedPlatoonVisuals?.clear()
  }

  // --------------------------------------------------
  // Сохранение уничтожаемой техники до Turbo-обновления
  // --------------------------------------------------

  beforeStreamRender(event) {
    const stream = event.target

    if (!(stream instanceof Element)) return

    if (stream.getAttribute("target") !== this.element.id) {
      return
    }

    if (stream.getAttribute("action") !== "update") {
      return
    }

    const template = stream.querySelector("template")
    const incomingGame = template?.content.querySelector(".game")

    if (!incomingGame) return

    let events = []

    try {
      events = JSON.parse(
        incomingGame.dataset.gameEventsEventsValue || "[]"
      )
    } catch (error) {
      console.error(
        "[Game Combat Effects] Invalid incoming events:",
        error
      )

      return
    }

    // При уничтожении штаба временно скрываем результат игры.
    // Покажем его после завершения анимации.
    const headquartersDestroyed = events.some((item) => {
      return (
        item.type === "game_finished" &&
        [
          "headquarters_destroyed",
          "empty_deck_damage"
        ].includes(item.reason)
      )
    })

    if (headquartersDestroyed) {
      const result = incomingGame.querySelector(".game-result")

      if (result) {
        result.style.display = "none"
      }

      incomingGame
        .querySelector(".game-content--muted")
        ?.classList.remove("game-content--muted")
    }

    const destroyedEvents = events.filter(
      (item) => item.type === "technique_destroyed"
    )

    destroyedEvents.forEach((destroyedEvent) => {
      const position = destroyedEvent.target?.position
      const key = this.positionKey(position)

      if (!key) return

      const cell = this.findCell(position)
      const object = cell?.querySelector(".cell-object")

      if (!object) return

      const queue = this.destroyedVisuals.get(key) || []

      queue.push(object.cloneNode(true))

      this.destroyedVisuals.set(key, queue)
    })

    // Сохраняем изображения уничтожаемых взводов
    // до замены игрового DOM через Turbo.
    const destroyedPlatoons = events.filter(
      (item) => item.type === "platoon_destroyed"
    )

    destroyedPlatoons.forEach((destroyedEvent) => {
      const playerId = destroyedEvent.platoon?.player_id
      const slotIndex = destroyedEvent.platoon?.slot

      if (playerId == null || !Number.isInteger(slotIndex)) return

      const slot = this.findPlatoonSlot(playerId, slotIndex)
      const visual = slot?.querySelector(".platoon-field")

      if (!slot || !visual) return

      const key = this.platoonKey(playerId, slotIndex)
      const queue = this.destroyedPlatoonVisuals.get(key) || []

      queue.push(visual.cloneNode(true))

      this.destroyedPlatoonVisuals.set(key, queue)
    })
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
    const headquartersAttack = events.find((event) => {
      return (
        event.type === "headquarters_attacked" &&
        event.target?.type === "headquarters"
      )
    })

    // При уничтожении штаба пустой колодой
    // координаты находятся в damage_applied.
    const emptyDeckDamage = events.find((event) => {
      return (
        event.type === "damage_applied" &&
        event.source?.type === "empty_deck_draw" &&
        event.target?.type === "headquarters"
      )
    })

    const combatEvents = events.filter((event) => {
      return [
        "shot_fired",
        "counterattack_fired",
        "technique_destroyed",
        "platoon_destroyed"
      ].includes(event.type) || (
        event.type === "game_finished" &&
        [
          "headquarters_destroyed",
          "empty_deck_damage"
        ].includes(event.reason)
      )
    })

    if (combatEvents.length === 0) return

    combatEvents.forEach((event) => {
      if (event.type === "technique_destroyed") {
        const key = this.positionKey(
          event.target?.position
        )

        if (key) {
          const visuals = this.destroyedVisuals.get(key) || []

          event.destroyedVisual = visuals.shift() || null

          if (visuals.length > 0) {
            this.destroyedVisuals.set(key, visuals)
          } else {
            this.destroyedVisuals.delete(key)
          }
        }

        // Возвращаем сохранённую картинку на поле сразу,
        // до запуска анимаций выстрела и попадания.
        const cell = this.findCell(event.target?.position)
        const visual = event.destroyedVisual

        if (cell && visual) {
          visual.classList.add(
            "game-combat-effect--destroyed-object"
          )

          visual.setAttribute("aria-hidden", "true")

          cell.appendChild(visual)
        }
      }

      if (event.type === "platoon_destroyed") {
        const playerId = event.platoon?.player_id
        const slotIndex = event.platoon?.slot

        if (playerId == null || !Number.isInteger(slotIndex)) {
          return
        }

        const key = this.platoonKey(playerId, slotIndex)
        const visuals = this.destroyedPlatoonVisuals.get(key) || []

        event.destroyedVisual = visuals.shift() || null

        if (visuals.length > 0) {
          this.destroyedPlatoonVisuals.set(key, visuals)
        } else {
          this.destroyedPlatoonVisuals.delete(key)
        }

        // Возвращаем изображение уничтоженного взвода
        // в освободившийся слот до запуска анимации.
        const slot = this.findPlatoonSlot(playerId, slotIndex)
        const visual = event.destroyedVisual

        if (slot && visual) {
          visual.classList.add(
            "game-combat-effect--destroyed-object"
          )

          visual.setAttribute("aria-hidden", "true")

          slot.appendChild(visual)
        }
      }

      if (
        event.type === "game_finished" &&
        [
          "headquarters_destroyed",
          "empty_deck_damage"
        ].includes(event.reason)
      ) {
        if (event.reason === "empty_deck_damage") {
          // Координаты штаба берём из фактического
          // события нанесения урона пустой колодой.
          event.destroyedHeadquartersPosition =
            emptyDeckDamage?.target?.position
        } else {
          // При боевом уничтожении штаба координаты
          // берём из события атаки штаба.
          event.destroyedHeadquartersPosition =
            headquartersAttack?.target?.position
        }
      }

      this.queue.push(event)
    })

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

        if (
          event.type === "shot_fired" ||
          event.type === "counterattack_fired"
        ) {
          await this.animateShot(event)
        } else if (event.type === "technique_destroyed") {
          await this.animateTechniqueDestroyed(event)
        } else if (event.type === "platoon_destroyed") {
          await this.animatePlatoonDestroyed(event)
        } else if (
          event.type === "game_finished" &&
          [
            "headquarters_destroyed",
            "empty_deck_damage"
          ].includes(event.reason)
        ) {
          await this.animateHeadquartersDestroyed(event)
        }
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
  // Уничтожение техники
  // --------------------------------------------------

  async animateTechniqueDestroyed(event) {
    const position = event.target?.position

    if (!position) return

    const cell = this.findCell(position)
    const visual = event.destroyedVisual

    if (!cell || !visual || !cell.contains(visual)) return

    await this.animateDestroyedVisual(cell, visual)
  }

  // --------------------------------------------------
  // Уничтожение взвода
  // --------------------------------------------------

  async animatePlatoonDestroyed(event) {
    const playerId = event.platoon?.player_id
    const slotIndex = event.platoon?.slot
    const visual = event.destroyedVisual

    if (playerId == null || !Number.isInteger(slotIndex) || !visual) {
      return
    }

    const slot = this.findPlatoonSlot(playerId, slotIndex)

    if (!slot || !slot.contains(visual)) return

    await this.animateDestroyedVisual(
      slot,
      visual,
      true
    )
  }

  // --------------------------------------------------
  // Уничтожение штаба
  // --------------------------------------------------

  async animateHeadquartersDestroyed(event) {
    const position = event.destroyedHeadquartersPosition

    if (!position) {
      this.revealGameResult()
      return
    }

    const cell = this.findCell(position)

    const visual = cell?.querySelector(
      ".cell-object--headquarters"
    )

    if (!cell || !visual) {
      this.revealGameResult()
      return
    }

    visual.classList.add(
      "game-combat-effect--destroyed-object"
    )

    visual.setAttribute("aria-hidden", "true")

    await this.animateDestroyedVisual(cell, visual)

    // Показываем результат только после уничтожения штаба.
    this.revealGameResult()
  }

  // --------------------------------------------------
  // Общая анимация уничтожения объекта
  // --------------------------------------------------

  async animateDestroyedVisual(cell, visual, compact = false) {
    const reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches

    // При включённом уменьшении движения —
    // только короткое плавное исчезновение.
    if (reducedMotion) {
      await this.playAnimation(
        visual,
        [
          { opacity: 1 },
          { opacity: 0 }
        ],
        {
          duration: 180,
          easing: "ease-out"
        }
      )

      visual.remove()
      return
    }

    // Создаём визуальные слои огня и дыма.
    const fire = document.createElement("div")

    fire.className =
      "game-combat-effect--destruction-fire"

    if (compact) {
      fire.classList.add(
        "game-combat-effect--platoon-fire"
      )
    }

    fire.setAttribute("aria-hidden", "true")

    const smoke = document.createElement("div")

    smoke.className =
      "game-combat-effect--destruction-smoke"

    if (compact) {
      smoke.classList.add(
        "game-combat-effect--platoon-smoke"
      )
    }

    smoke.setAttribute("aria-hidden", "true")

    cell.appendChild(fire)
    cell.appendChild(smoke)

    // 1. Короткий импульс от попадания.
    await this.playAnimation(
      visual,
      compact
        ? [
            {
              transform: "translateX(0) scale(1)",
              filter: "brightness(1)"
            },
            {
              transform: "translateX(-1px) scale(1.01)",
              filter: "brightness(1.8)"
            },
            {
              transform: "translateX(1px) scale(0.995)",
              filter: "brightness(1.35)"
            },
            {
              transform: "translateX(0) scale(1)",
              filter: "brightness(1)"
            }
          ]
        : [
            {
              transform: "translateX(0) scale(1)",
              filter: "brightness(1)"
            },
            {
              transform: "translateX(-3px) scale(1.015)",
              filter: "brightness(1.8)"
            },
            {
              transform: "translateX(2px) scale(0.99)",
              filter: "brightness(1.35)"
            },
            {
              transform: "translateX(0) scale(1)",
              filter: "brightness(1)"
            }
          ],
      {
        duration: 220,
        easing: "ease-out"
      }
    )

    // 2. Огонь появляется на объекте.
    // 3. Изображение темнеет и исчезает.
    // 4. Дым поднимается и рассеивается.
    await Promise.all([
      this.playAnimation(
        visual,
        [
          {
            opacity: 1,
            filter: "brightness(1) saturate(1)"
          },
          {
            opacity: 1,
            filter: "brightness(0.75) saturate(0.7)"
          },
          {
            opacity: 0.75,
            filter: "brightness(0.35) saturate(0.35)"
          },
          {
            opacity: 0,
            filter: "brightness(0.15) saturate(0)"
          }
        ],
        {
          duration: 780,
          easing: "ease-in"
        }
      ),

      this.playAnimation(
        fire,
        [
          {
            opacity: 0,
            transform: "scale(0.35)"
          },
          {
            opacity: 0.95,
            transform: "scale(1.05)"
          },
          {
            opacity: 0.85,
            transform: "scale(1.15)"
          },
          {
            opacity: 0,
            transform: "scale(1.35)"
          }
        ],
        {
          duration: 680,
          easing: "ease-out"
        }
      ),

      this.playAnimation(
        smoke,
        [
          {
            opacity: 0,
            transform: "translateY(12%) scale(0.65)"
          },
          {
            opacity: 0.7,
            transform: "translateY(0) scale(0.9)"
          },
          {
            opacity: 0.55,
            transform: "translateY(-12%) scale(1.15)"
          },
          {
            opacity: 0,
            transform: "translateY(-35%) scale(1.5)"
          }
        ],
        {
          duration: 1050,
          easing: "ease-out"
        }
      )
    ])

    visual.remove()
    fire.remove()
    smoke.remove()
  }

  // --------------------------------------------------
  // Отображение результата завершённой игры
  // --------------------------------------------------

  revealGameResult() {
    const result = this.element.querySelector(".game-result")

    if (result) {
      result.style.removeProperty("display")
    }
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
  // Работа со слотами взводов
  // --------------------------------------------------

  platoonKey(playerId, slotIndex) {
    return `${playerId}:${slotIndex}`
  }

  findPlatoonSlot(playerId, slotIndex) {
    return Array.from(
      this.element.querySelectorAll(".platoon-slot")
    ).find((slot) => {
      return (
        slot.dataset.playerId === String(playerId) &&
        slot.dataset.platoonSlot === String(slotIndex)
      )
    }) || null
  }

  positionKey(position) {
    if (!Array.isArray(position)) return null

    return `${position[0]},${position[1]}`
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