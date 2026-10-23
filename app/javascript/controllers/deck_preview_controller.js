import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  open(event) {
    const deckCard = event.currentTarget.closest(".deck-card")
    const dialog = deckCard?.querySelector(".deck-card__preview-dialog")

    if (dialog && !dialog.open) {
      dialog.showModal()
    }
  }

  close(event) {
    const dialog = event.currentTarget.closest("dialog")

    if (dialog?.open) {
      dialog.close()
    }
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      event.currentTarget.close()
    }
  }
}