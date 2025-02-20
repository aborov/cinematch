import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["refreshButton"]

  connect() {
    this.refreshButton = document.getElementById('refresh-recommendations')
    if (this.refreshButton) {
      this.refreshButton.addEventListener('click', this.refreshRecommendations.bind(this))
    }
  }

  async refreshRecommendations(event) {
    event.preventDefault()
    const button = event.currentTarget
    const icon = button.querySelector('i')
    icon.classList.add('text-primary', 'fa-spin')
    button.disabled = true
    
    try {
      const response = await fetch('/recommendations/refresh', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
        }
      })
      
      if (response.ok) {
        this.pollStatus(icon)
      } else {
        throw new Error('Refresh failed')
      }
    } catch (error) {
      console.error('Failed to refresh recommendations:', error)
      icon.classList.remove('text-primary', 'fa-spin')
      button.disabled = false
    }
  }

  async pollStatus(icon) {
    const button = document.getElementById('refresh-recommendations')
    const checkStatus = async () => {
      const response = await fetch('/recommendations/check_status')
      const data = await response.json()
      
      if (data.status === 'ready') {
        icon.classList.remove('text-primary', 'fa-spin')
        button.disabled = false
        window.location.reload()
      } else {
        setTimeout(checkStatus, 2000)
      }
    }
    
    checkStatus()
  }
} 
