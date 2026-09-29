import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["gameTime", "turnTime"]

  static values = {
    gameStatus: String,
    currentPlayerId: Number,
    turnStartedAt: String,
    serverTime: String,
    turnDuration: Number,
    endTurnUrl: String,
    playerId: Number
  }

  connect() {
    this.endTurnRequested = false

    if (this.gameStatusValue === "finished") {
      return
    }

    this.serverOffset =
      Date.parse(this.serverTimeValue) - Date.now()

    this.tick()

    this.interval = setInterval(() => {
      this.tick()
    }, 1000)
  }

  disconnect() {
    this.stopTimer()
  }

  stopTimer() {
    clearInterval(this.interval)
    this.interval = null
  }

  tick() {
    if (this.gameStatusValue === "finished") {
      this.stopTimer()
      return
    }

    const now = Date.now() + this.serverOffset
    const turnStartedAt = Date.parse(this.turnStartedAtValue)

    const elapsedSeconds = Math.max(
      (now - turnStartedAt) / 1000,
      0
    )

    const turnRemaining = Math.max(
      this.turnDurationValue - Math.ceil(elapsedSeconds),
      0
    )

    this.turnTimeTargets.forEach((element) => {
      element.textContent = this.formatTime(turnRemaining)
    })

    let currentPlayerTimeRemaining = null

    this.gameTimeTargets.forEach((element) => {
      const playerId = Number(element.dataset.playerId)
      const baseRemaining = Number(element.dataset.remainingTime)

      let remaining = baseRemaining

      if (playerId === this.currentPlayerIdValue) {
        remaining -= Math.ceil(elapsedSeconds)
        currentPlayerTimeRemaining = remaining
      }

      remaining = Math.max(remaining, 0)

      element.textContent = this.formatTime(remaining)
    })

    if (this.playerIdValue !== this.currentPlayerIdValue) {
      return
    }

    if (currentPlayerTimeRemaining !== null &&
        currentPlayerTimeRemaining <= 0) {
      this.requestEndTurn()
      return
    }

    if (turnRemaining <= 0) {
      this.requestEndTurn()
    }
  }

  requestEndTurn() {
    if (this.gameStatusValue === "finished") return

    if (this.endTurnRequested) return

    if (this.playerIdValue !== this.currentPlayerIdValue) return

    this.endTurnRequested = true

    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]'
    )?.content

    const url = new URL(this.endTurnUrlValue, window.location.origin)

    url.searchParams.set("player_id", this.playerIdValue)

    fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      credentials: "same-origin"
    })
  }

  formatTime(totalSeconds) {
    const seconds = Math.max(Math.floor(totalSeconds), 0)

    const minutes = Math.floor(seconds / 60)
    const remainingSeconds = seconds % 60

    return `${String(minutes).padStart(2, "0")}:${String(remainingSeconds).padStart(2, "0")}`
  }
}
