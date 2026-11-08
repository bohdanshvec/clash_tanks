import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  initialize() {
    this.handlePointerOver = this.handlePointerOver.bind(this)
    this.handlePointerOut = this.handlePointerOut.bind(this)
  }

  connect() {
    this.element.addEventListener("pointerover", this.handlePointerOver)
    this.element.addEventListener("pointerout", this.handlePointerOut)
  }

  disconnect() {
    this.element.removeEventListener("pointerover", this.handlePointerOver)
    this.element.removeEventListener("pointerout", this.handlePointerOut)
  }

  handlePointerOver(event) {
    const item = event.target.closest?.(".deck-card__preview-item")

    if (
      !item ||
      !this.element.contains(item) ||
      item.contains(event.relatedTarget)
    ) {
      return
    }

    this.positionPreview(item)
  }

  handlePointerOut(event) {
    const item = event.target.closest?.(".deck-card__preview-item")

    if (
      !item ||
      !this.element.contains(item) ||
      item.contains(event.relatedTarget)
    ) {
      return
    }

    this.resetPreviewPosition(item)
  }

  positionPreview(item) {
    const preview = item.querySelector(".deck-card__card-preview")
    const dialog = item.closest(".deck-card__preview-dialog")
    const list = item.closest(".deck-card__preview-list")

    if (!preview || !dialog || !list || !dialog.open) return

    const dialogRect = dialog.getBoundingClientRect()
    const listRect = list.getBoundingClientRect()
    const itemRect = item.getBoundingClientRect()

    const visibleTop = Math.max(
      listRect.top,
      dialogRect.top + dialog.clientTop
    )

    const visibleBottom = Math.min(
      listRect.bottom,
      dialogRect.top + dialog.clientTop + dialog.clientHeight
    )

    const previewHeight = preview.offsetHeight
    const margin = 8
    const availableHeight = visibleBottom - visibleTop - margin * 2

    if (availableHeight <= 0 || previewHeight <= 0) return

    const scale = Math.min(1, availableHeight / previewHeight)
    const displayedHeight = previewHeight * scale

    const minTop = visibleTop + margin
    const maxTop = visibleBottom - displayedHeight - margin

    const centeredTop =
      itemRect.top + itemRect.height / 2 - displayedHeight / 2

    const targetTop = Math.min(
      Math.max(centeredTop, minTop),
      maxTop
    )

    preview.style.setProperty(
      "--deck-preview-offset-y",
      `${Math.round(targetTop - itemRect.top)}px`
    )

    preview.style.setProperty(
      "--deck-preview-scale",
      scale.toString()
    )
  }

  resetPreviewPosition(item) {
    const preview = item.querySelector(".deck-card__card-preview")

    if (!preview) return

    preview.style.removeProperty("--deck-preview-offset-y")
    preview.style.removeProperty("--deck-preview-scale")
  }

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