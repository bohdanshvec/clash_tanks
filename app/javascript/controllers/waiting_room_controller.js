import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String
  }

  connect() {
    this.sendHeartbeat()

    this.timer = setInterval(() => {
      this.sendHeartbeat()
    }, 10_000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async sendHeartbeat() {
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const headers = {
        "Accept": "text/vnd.turbo-stream.html"
      }

      if (csrfToken) {
        headers["X-CSRF-Token"] = csrfToken
      }

      await fetch(this.urlValue, {
        method: "POST",
        headers,
        credentials: "same-origin"
      })
    } catch {
      // Waiting room may have been closed or navigated away from.
    }
  }
}
