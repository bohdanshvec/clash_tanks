
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundBeforeStreamRender =
      this.beforeStreamRender.bind(this)

    this.boundAnimationEnd =
      this.finishAnimation.bind(this)

    document.addEventListener(
      "turbo:before-stream-render",
      this.boundBeforeStreamRender
    )

    this.element.addEventListener(
      "animationend",
      this.boundAnimationEnd
    )
  }

  disconnect() {
    document.removeEventListener(
      "turbo:before-stream-render",
      this.boundBeforeStreamRender
    )

    this.element.removeEventListener(
      "animationend",
      this.boundAnimationEnd
    )
  }

  // --------------------------------------------------
  // Обнаружение новых карт перед Turbo-обновлением
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
    const incomingGame =
      template?.content.querySelector(".game")

    const currentGame =
      this.element.querySelector(".game")

    if (!incomingGame || !currentGame) return

    const events = this.parseGameEvents(incomingGame)

    if (!events) return

    // Проверяем, действительно ли игрок получил карты.
    const drawnPlayerIds = new Set(
      events
        .filter((item) => item.type === "card_drawn")
        .map((item) => String(item.player_id))
    )

    const currentPlayerId =
      incomingGame.dataset.playerId

    if (!drawnPlayerIds.has(currentPlayerId)) return

    // Считаем экземпляры карт в прежней руке.
    const previousCounts =
      this.countCards(currentGame)

    // Считаем карты в новой руке и отмечаем только
    // те экземпляры, количество которых увеличилось.
    const incomingCards = incomingGame.querySelectorAll(
      ".hand [data-card-id]"
    )

    const incomingCounts = new Map()

    incomingCards.forEach((card, index) => {
      const key = this.cardKey(card)

      const count = (incomingCounts.get(key) || 0) + 1

      incomingCounts.set(key, count)

      const previousCount =
        previousCounts.get(key) || 0

      if (count > previousCount) {
        card.classList.add(
          "card-draw-effect--active"
        )
      }
    })
  }

  // --------------------------------------------------
  // Чтение событий игрового обновления
  // --------------------------------------------------

  parseGameEvents(game) {
    try {
      return JSON.parse(
        game.dataset.gameEventsEventsValue || "[]"
      )
    } catch (error) {
      console.error(
        "[Card Draw Effect] Invalid game events:",
        error
      )

      return null
    }
  }

  // --------------------------------------------------
  // Подсчёт экземпляров карт в руке
  // --------------------------------------------------

  countCards(game) {
    const counts = new Map()

    game.querySelectorAll(
      ".hand [data-card-id]"
    ).forEach((card) => {
      const key = this.cardKey(card)

      counts.set(
        key,
        (counts.get(key) || 0) + 1
      )
    })

    return counts
  }

  // --------------------------------------------------
  // Уникальный ключ типа карты в руке
  // --------------------------------------------------

  cardKey(card) {
    return JSON.stringify([
      card.dataset.playerId,
      card.dataset.cardId,
      card.dataset.cardType
    ])
  }

  // --------------------------------------------------
  // Завершение эффекта после двух миганий
  // --------------------------------------------------

  finishAnimation(event) {
    if (!(event.target instanceof Element)) return

    if (
      !event.target.classList.contains(
        "card-draw-effect--active"
      )
    ) {
      return
    }

    if (event.animationName !== "card-draw-effect-flash") {
      return
    }

    event.target.classList.remove(
      "card-draw-effect--active"
    )
  }
}
