import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.handleDocumentClick = this.handleDocumentClick.bind(this)

    document.addEventListener("click", this.handleDocumentClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
  }

  handleDocumentClick(event) {
    const clickedPreview = event.target.closest(".deck-card__preview")

    this.element
      .querySelectorAll(".deck-card__preview[open]")
      .forEach((preview) => {
        if (preview !== clickedPreview) {
          preview.removeAttribute("open")
        }
      })
  }
}
