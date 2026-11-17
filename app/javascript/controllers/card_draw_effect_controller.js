
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

    if (!incomingGame) return

    const events = this.parseGameEvents(incomingGame)

    if (!events) return

    const currentPlayerId = incomingGame.dataset.playerId

    // Считаем фактически полученные карты.
    // Каждое событие card_drawn соответствует одной карте.
    const drawnCount = events.filter((item) => {
      return (
        item.type === "card_drawn" &&
        String(item.player_id) === currentPlayerId
      )
    }).length

    if (drawnCount === 0) return

    // Получаем карты только руки текущего игрока.
    const incomingCards = Array.from(
      incomingGame.querySelectorAll(
        ".hand--bottom [data-card-id]"
      )
    )

    // Подсвечиваем последние N карт, где N —
    // количество событий card_drawn.
    const newCards = incomingCards.slice(-drawnCount)

    newCards.forEach((card) => {
      card.classList.add("card-draw-effect--active")
    })

    console.log(
      "[Card Draw Effect] Drawn:",
      drawnCount,
      "Highlighted:",
      newCards.length
    )
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
