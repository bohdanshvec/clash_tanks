import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    events: Array,
    availableActions: Object
  }

  connect() {
    this.selectedElement = null

    this.eventsValue.forEach((event) => {
      this.handleEvent(event)
    })
  }

  handleEvent(event) {
    switch (event.type) {
      case "technique_moved":
        this.highlightMove(event)
        break

      case "technique_attacked":
      case "headquarters_attacked":
        this.highlightAttack(event)
        break

      case "technique_played":
        this.highlightPlayedCard(event)
        break

      case "order_played":
        this.highlightPlayedCard(event)
        break

      case "platoon_played":
        this.highlightPlatoon(event)
        break

      case "turn_ended":
        this.highlightTurnEnded()
        break

      default:
        break
    }
  }

  select(event) {
    const element = event.currentTarget

    if (this.selectedElement === element) {
      this.clearSelection()
      return
    }

    this.clearSelection()

    this.selectedElement = element
    element.classList.add("game-object--selected")

    if (element.dataset.cardId) {
      this.showHandAvailableActions(element)
    } else {
      this.showFieldAvailableActions(element)
    }
  }

  clearSelection() {
    if (this.selectedElement) {
      this.selectedElement.classList.remove("game-object--selected")
      this.selectedElement = null
    }

    this.clearAvailableActions()
  }

  showFieldAvailableActions(element) {
    const position = element.dataset.position

    if (!position) return

    const fieldActions = this.availableActionsValue?.field || {}
    const actions = fieldActions[position]

    if (!actions) return

    this.highlightPositions(
      actions.moves,
      "game-action--move"
    )

    this.highlightPositions(
      actions.attacks,
      "game-action--attack"
    )
  }

	showHandAvailableActions(element) {
		const cardId = element.dataset.cardId

		if (!cardId) return

		const handActions = this.availableActionsValue?.hand || {}
		const actions = handActions[cardId]

		if (!actions) return

		switch (actions.type) {
		  case "technique":
		    this.highlightPositions(
		      actions.positions,
		      "game-action--card"
		    )
		    break

		  case "platoon":
		    this.highlightPlatoonSlots(
		      actions.slots,
		      element.dataset.playerId
		    )
		    break

		  case "order":
		    if (actions.targets) {
		      this.highlightPositions(
		        actions.targets,
		        "game-action--card-target"
		      )
		    } else if (actions.drop_zone === "field") {
		      this.highlightFieldDropZone()
		    }
		    break

		  default:
		    break
		}
	}

  highlightPositions(positions, className) {
    if (!positions) return

    positions.forEach((position) => {
      const element = this.findPosition(position)

      if (element) {
        element.classList.add(className)
      }
    })
  }

	highlightPlatoonSlots(slots, playerId) {
		if (!slots || !playerId) return

		slots.forEach((slot) => {
		  const element = this.element.querySelector(
		    `[data-platoon-slot="${slot}"][data-player-id="${playerId}"]`
		  )

		  if (element) {
		    element.classList.add("game-action--card")
		  }
		})
	}

  highlightFieldDropZone() {
    const field = this.element.querySelector(".game-board__field")

    if (field) {
      field.classList.add("game-action--drop-zone")
    }
  }

  clearAvailableActions() {
    this.element
      .querySelectorAll(
        ".game-action--move, " +
        ".game-action--attack, " +
        ".game-action--card, " +
        ".game-action--card-target, " +
        ".game-action--drop-zone"
      )
      .forEach((element) => {
        element.classList.remove(
          "game-action--move",
          "game-action--attack",
          "game-action--card",
          "game-action--card-target",
          "game-action--drop-zone"
        )
      })
  }

  highlightMove(event) {
    const from = this.findPosition(event.from)
    const to = this.findPosition(event.to)

    this.flash(from)
    this.flash(to)
  }

  highlightAttack(event) {
    const attacker = this.findPosition(event.attacker.position)
    const target = this.findPosition(event.target.position)

    this.flash(attacker)
    this.flash(target)
  }

  highlightPlayedCard(event) {
    if (event.position) {
      const target = this.findPosition(event.position)
      this.flash(target)
      return
    }

    if (event.targets?.length) {
      event.targets.forEach((target) => {
        const element = this.findPosition([
          target.row,
          target.column
        ])

        this.flash(element)
      })
    }
  }

  highlightTurnEnded() {
    this.element.classList.add("game--turn-changed")

    window.setTimeout(() => {
      this.element.classList.remove("game--turn-changed")
    }, 500)
  }

  findPosition(position) {
    if (!position) return null

    const [row, column] = position

    return this.element.querySelector(
      `[data-position="${row},${column}"]`
    )
  }

  flash(element) {
    if (!element) return

    element.classList.remove("game-event--flash")

    void element.offsetWidth

    element.classList.add("game-event--flash")

    window.setTimeout(() => {
      element.classList.remove("game-event--flash")
    }, 500)
  }

	highlightPlatoon(event) {
		const target = this.element.querySelector(
		  `[data-platoon-slot="${event.slot}"][data-player-id="${event.player_id}"]`
		)

		this.flash(target)
	}
}
