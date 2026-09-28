import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    events: Array,
    availableActions: Object
  }

	connect() {
		this.selectedElement = null
		this.draggedCard = null
		this.dragOverTarget = null
		this.hoverTarget = null

		this.eventsValue.forEach((event) => {
		  this.handleEvent(event)
		})
	}

  // --------------------------------------------------
  // Events from Game Engine
  // --------------------------------------------------

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

  // --------------------------------------------------
  // Selection
  // --------------------------------------------------

  select(event) {
    const element = event.currentTarget

    if (this.selectedElement === element) {
      this.clearSelection()
      return
    }

    this.selectElement(element)
  }

  selectElement(element) {
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
		this.clearHover()
	}

  // --------------------------------------------------
  // Click on available action
  // --------------------------------------------------

	handleActionClick(event) {
		const element = event.target.closest(
		  ".game-action--move, " +
		  ".game-action--attack, " +
		  ".game-action--card, " +
		  ".game-action--card-target, " +
		  ".game-action--drop-zone"
		)

		if (element && this.element.contains(element)) {
		  event.preventDefault()
		  event.stopPropagation()

		  if (element.classList.contains("game-action--move")) {
		    this.executeMove(element)
		    return
		  }

		  if (element.classList.contains("game-action--attack")) {
		    this.executeAttack(element)
		    return
		  }

		  if (
		    element.classList.contains("game-action--card") ||
		    element.classList.contains("game-action--card-target") ||
		    element.classList.contains("game-action--drop-zone")
		  ) {
		    this.executeCardAction(element)
		    return
		  }
		}

		if (!this.selectedElement) return

		const selectable = event.target.closest(
		  "[data-card-id], [data-object-type]"
		)

		if (selectable && this.element.contains(selectable)) {
		  return
		}

		this.clearSelection()
	}
	
	// --------------------------------------------------
	// Mouse hover
	// --------------------------------------------------

	mouseOver(event) {
		if (this.draggedCard) return
		if (!this.selectedElement) return

		const target = this.actionTarget(event)

		if (!target) return

		if (this.hoverTarget === target) return

		this.clearHover()

		this.hoverTarget = target
		target.classList.add("game-action--hover")
	}

	mouseOut(event) {
		if (this.draggedCard) return
		if (!this.selectedElement) return

		const target = this.actionTarget(event)

		if (!target) return

		// Переход внутри той же цели не считается выходом.
		if (
		  event.relatedTarget &&
		  target.contains(event.relatedTarget)
		) {
		  return
		}

		if (this.hoverTarget === target) {
		  this.clearHover()
		}
	}

	clearHover() {
		if (this.hoverTarget) {
		  this.hoverTarget.classList.remove("game-action--hover")
		  this.hoverTarget = null
		}

		this.element
		  .querySelectorAll(".game-action--hover")
		  .forEach((element) => {
		    element.classList.remove("game-action--hover")
		  })
	}

	actionTarget(event) {
		const target = event.target.closest(
		  ".game-action--move, " +
		  ".game-action--attack, " +
		  ".game-action--card, " +
		  ".game-action--card-target, " +
		  ".game-action--drop-zone"
		)

		if (!target || !this.element.contains(target)) {
		  return null
		}

		return target
	}

  // --------------------------------------------------
  // Field selection
  // --------------------------------------------------

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

  // --------------------------------------------------
  // Hand selection
  // --------------------------------------------------

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

  // --------------------------------------------------
  // Highlighting
  // --------------------------------------------------

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
    if (!slots || !playerId || slots.length === 0) return

    slots.forEach((slot) => {
      const element = this.element.querySelector(
        `[data-platoon-slot="${slot}"][data-player-id="${playerId}"]`
      )

      if (element) {
        element.classList.add("game-action--card")
      }
    })

    const platoonBar = this.element.querySelector(
      `[data-platoon-bar][data-player-id="${playerId}"]`
    )

    if (platoonBar) {
      platoonBar.classList.add("game-action--drop-zone")
    }
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

  // --------------------------------------------------
  // Click actions
  // --------------------------------------------------

  executeMove(target) {
    const from = this.positionFromElement(this.selectedElement)
    const to = this.positionFromElement(target)

    if (!from || !to) return

    this.clearSelection()

    this.sendAction("move", {
      from_row: from[0],
      from_column: from[1],
      to_row: to[0],
      to_column: to[1]
    })
  }

  executeAttack(target) {
    const attacker = this.positionFromElement(this.selectedElement)
    const targetPosition = this.positionFromElement(target)

    if (!attacker || !targetPosition) return

    this.clearSelection()

    this.sendAction("attack", {
      attacker_row: attacker[0],
      attacker_column: attacker[1],
      target_row: targetPosition[0],
      target_column: targetPosition[1]
    })
  }

  executeCardAction(target) {
    const card = this.selectedElement

    if (!card || !card.dataset.cardId) return

    const cardId = card.dataset.cardId

    // Technique → field
    if (
      target.dataset.position &&
      target.classList.contains("game-action--card")
    ) {
      const position = this.positionFromElement(target)

      this.clearSelection()

      this.sendAction("play_card", {
        card_id: cardId,
        row: position[0],
        column: position[1]
      })

      return
    }

    // Order → target
    if (
      target.dataset.position &&
      target.classList.contains("game-action--card-target")
    ) {
      const position = this.positionFromElement(target)

      this.clearSelection()

      this.sendAction("play_card", {
        card_id: cardId,
        target: `${position[0]},${position[1]}`
      })

      return
    }

    // Order without target → field
    if (
      target.classList.contains("game-action--drop-zone") &&
      target.classList.contains("game-board__field")
    ) {
      this.clearSelection()

      this.sendAction("play_card", {
        card_id: cardId
      })

      return
    }

    // Platoon → platoon bar
    if (
      target.hasAttribute("data-platoon-bar") ||
      target.closest("[data-platoon-bar]")
    ) {
      this.clearSelection()

      this.sendAction("play_card", {
        card_id: cardId
      })
    }
  }

  // --------------------------------------------------
  // Drag & Drop
  // --------------------------------------------------

  dragStart(event) {
    const card = event.target.closest("[data-card-id]")

    if (!card || !this.element.contains(card)) return

    this.draggedCard = card
    this.dragOverTarget = null

    this.selectElement(card)

    card.classList.add("game-object--dragging")

    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData(
        "text/plain",
        card.dataset.cardId
      )
    }
  }

  dragOver(event) {
    if (!this.draggedCard) return

    const target = this.dropTarget(event)

    if (!target) return

    event.preventDefault()

    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = "move"
    }

    if (this.dragOverTarget === target) return

    this.clearDragOver()

    this.dragOverTarget = target
    target.classList.add("game-action--drag-over")
  }

  dragLeave(event) {
    if (!this.draggedCard) return

    const target = this.dropTarget(event)

    if (!target) return

    // Не очищаем подсветку при переходе
    // с родительского элемента на его дочерний.
    if (
      event.relatedTarget &&
      target.contains(event.relatedTarget)
    ) {
      return
    }

    if (this.dragOverTarget === target) {
      this.clearDragOver()
    }
  }

  drop(event) {
    const target = this.dropTarget(event)

    if (!target || !this.draggedCard) return

    event.preventDefault()

    this.executeCardAction(target)
    this.finishDrag()
  }

  dragEnd() {
    this.finishDrag()
  }

	finishDrag() {
		this.clearDragOver()
		this.clearHover()

		if (this.draggedCard) {
		  this.draggedCard.classList.remove("game-object--dragging")
		}

		this.draggedCard = null
	}

  clearDragOver() {
    if (this.dragOverTarget) {
      this.dragOverTarget.classList.remove(
        "game-action--drag-over"
      )

      this.dragOverTarget = null
    }

    this.element
      .querySelectorAll(".game-action--drag-over")
      .forEach((element) => {
        element.classList.remove("game-action--drag-over")
      })
  }

  dropTarget(event) {
    const target = event.target.closest(
      ".game-action--card, " +
      ".game-action--card-target, " +
      ".game-action--drop-zone"
    )

    if (!target || !this.element.contains(target)) {
      return null
    }

    return target
  }

  // --------------------------------------------------
  // Rails actions
  // --------------------------------------------------

  sendAction(type, parameters) {
    const urls = {
      move: this.element.dataset.moveUrl,
      attack: this.element.dataset.attackUrl,
      play_card: this.element.dataset.playCardUrl
    }

    const url = urls[type]

    if (!url) {
      console.error(`Missing URL for action: ${type}`)
      return
    }

    const body = new URLSearchParams()

    body.append(
      "player_id",
      this.element.dataset.playerId
    )

    Object.entries(parameters).forEach(([key, value]) => {
      body.append(key, value)
    })

    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]'
    )?.content

    fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body
    }).then(async (response) => {
      if (!response.ok) {
        const message = await response.text()
        console.error(message)
      }
    }).catch((error) => {
      console.error(error)
    })
  }

  // --------------------------------------------------
  // Game events
  // --------------------------------------------------

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

    if (event.type !== "headquarters_attacked") return

    if (event.attacker.type === "headquarters") {
      this.flashPlatoonsByAttribute(
        event.attacker.player_id,
        "data-firepower"
      )
    }

    if (event.target.type === "headquarters") {
      this.flashPlatoonsByAttribute(
        event.target.player_id,
        "data-armor"
      )
    }
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

  highlightPlatoon(event) {
    const target = this.element.querySelector(
      `[data-platoon-slot="${event.slot}"][data-player-id="${event.player_id}"]`
    )

    this.flash(target)
  }

  flashPlatoonsByAttribute(playerId, attribute) {
    if (!playerId) return

    this.element
      .querySelectorAll(
        `[data-player-id="${playerId}"][${attribute}]`
      )
      .forEach((element) => {
        const value = Number(
          element.dataset[
            attribute.replace("data-", "")
          ]
        )

        if (value > 0) {
          this.flash(element)
        }
      })
  }

  // --------------------------------------------------
  // Helpers
  // --------------------------------------------------

  findPosition(position) {
    if (!position) return null

    const [row, column] = position

    return this.element.querySelector(
      `[data-position="${row},${column}"]`
    )
  }

  positionFromElement(element) {
    if (!element?.dataset.position) return null

    return element.dataset.position
      .split(",")
      .map(Number)
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
}
