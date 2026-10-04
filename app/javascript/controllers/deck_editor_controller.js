import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "headquarters",
    "nation",
    "nationSection",
    "quantity",
    "count",
    "weight"
  ]

  connect() {
    this.update()
  }

  update() {
    this.updateNation()
    this.updateSummary()
  }

  updateNation() {
    const selectedOption =
      this.hasHeadquartersTarget
        ? this.headquartersTarget.selectedOptions[0]
        : null

    const nationId =
      selectedOption?.dataset.nationId ||
      this.element.dataset.currentNationId

    this.nationSectionTargets.forEach((section) => {
      section.hidden =
        section.dataset.nationId !== nationId
    })

    if (!nationId) {
      this.nationTarget.textContent = "не выбрана"
      return
    }

    const section = this.nationSectionTargets.find(
      (section) => section.dataset.nationId === nationId
    )

    this.nationTarget.textContent =
      section?.querySelector("h2")?.textContent.trim() ||
      "не выбрана"
  }

  increase(event) {
    this.changeQuantity(event, 1)
  }

  decrease(event) {
    this.changeQuantity(event, -1)
  }

  changeQuantity(event, delta) {
    const cardId =
      event.currentTarget.dataset.cardId

    const input = document.querySelector(
      `#deck_card_quantities_${cardId}`
    )

    if (!input) {
      return
    }

    let quantity =
      Number.parseInt(input.value, 10) || 0

    quantity += delta
    quantity = Math.max(0, Math.min(3, quantity))

    input.value = quantity

    const card =
      event.currentTarget.closest(".deck-editor__card")

    const counter =
      card.querySelector(".deck-editor__quantity-value")

    counter.textContent = quantity

    this.updateSummary()
  }

  updateSummary() {
    let count = 0
    let weight = 0

    this.quantityTargets.forEach((input) => {
      const quantity =
        Number.parseInt(input.value, 10) || 0

      const card =
        input.closest(".deck-editor__card")

      const cardWeight =
        Number.parseInt(
          card?.dataset.cardWeight,
          10
        ) || 0

      count += quantity
      weight += quantity * cardWeight
    })

    this.countTarget.textContent = count
    this.weightTarget.textContent = weight

    this.countTarget
      .closest("strong")
      .classList.toggle(
        "deck-editor__summary--over-limit",
        count > 10
      )
  }
}
