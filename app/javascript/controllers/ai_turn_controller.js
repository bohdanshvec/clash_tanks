import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    enabled: Boolean
  }

  static MAX_RETRIES = 2
  static RETRY_DELAY_MS = 2000

  connect() {
    if (!this.enabledValue) return

    this.started = false
    this.retryCount = 0
    this.checkSubscription()
  }

  disconnect() {
    if (this.subscriptionTimer) {
      clearTimeout(this.subscriptionTimer)
      this.subscriptionTimer = null
    }

    if (this.retryTimer) {
      clearTimeout(this.retryTimer)
      this.retryTimer = null
    }
  }

  checkSubscription() {
    if (this.started || !this.element.isConnected) return

    const source = this.element.querySelector(
      "turbo-cable-stream-source"
    )

    if (
      source?.subscription &&
      source.subscription.consumer.connection.isOpen()
    ) {
      this.started = true
      this.runAiTurn()
      return
    }

    this.subscriptionTimer = setTimeout(() => {
      this.checkSubscription()
    }, 100)
  }

  async runAiTurn() {
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]'
    )?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        credentials: "same-origin"
      })

      if (response.ok) {
        this.retryCount = 0
        return
      }

      console.error(
        "[AI Turn] Request failed:",
        response.status
      )

      this.scheduleRetry()
    } catch (error) {
      console.error("[AI Turn] Request error:", error)
      this.scheduleRetry()
    }
  }

  scheduleRetry() {
    if (!this.element.isConnected) return

    if (this.retryCount >= this.constructor.MAX_RETRIES) {
      console.error(
        "[AI Turn] Retry limit reached. " +
        "Waiting for another controller connection."
      )

      return
    }

    this.retryCount += 1

    this.retryTimer = setTimeout(() => {
      this.retryTimer = null

      if (!this.element.isConnected) return

      this.runAiTurn()
    }, this.constructor.RETRY_DELAY_MS)
  }
}
