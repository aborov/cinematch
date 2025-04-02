import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="recommendations-refresh"
export default class extends Controller {
  static targets = [ "button" ]

  connect() {
    // Check initial status when the controller connects
    this.checkInitialStatus();
  }

  async checkInitialStatus() {
    try {
      const response = await fetch('/recommendations/check_status');
      const data = await response.json();
      if (data.status === 'processing') {
        this.showProcessingState();
        this.pollStatus(); // Start polling
      }
    } catch (error) {
      console.error("Error checking initial status:", error);
      // Optionally, handle the error state in the UI
    }
  }

  async refresh(event) {
    event.preventDefault();
    const button = this.buttonTarget;
    const originalContent = button.innerHTML; // Store original content
    this.showProcessingState(originalContent); // Pass original content

    try {
      const response = await fetch('/recommendations/refresh', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getMetaValue("csrf-token")
        }
      });

      const data = await response.json();

      if (data.status === 'processing') {
        this.pollStatus(originalContent); // Start polling
      } else {
        this.showIdleState(originalContent); // Restore original content on failure/unexpected status
        alert(data.message || 'Failed to start recommendation refresh');
      }
    } catch (error) {
      console.error("Error refreshing recommendations:", error);
      this.showIdleState(originalContent); // Restore original content on error
      alert('An error occurred while refreshing recommendations.');
    }
  }

  pollStatus(originalContent) {
    this.pollingInterval = setInterval(async () => {
      try {
        const response = await fetch('/recommendations/check_status');
        const data = await response.json();

        if (data.status === 'ready') {
          clearInterval(this.pollingInterval);
          // Only reload if we are on the recommendations page
          if (window.location.pathname === '/recommendations') {
            window.location.reload(); // Reload the page when ready
          } else {
            // Optional: Show a notification or update UI elsewhere if needed
            console.log("Recommendations ready, but not reloading as user is not on the recommendations page.");
            this.showIdleState(originalContent); // Restore button state
          }
        } else if (data.status !== 'processing') {
          // Handle error or unexpected status
          clearInterval(this.pollingInterval);
          this.showIdleState(originalContent);
          alert(data.message || 'Failed to get recommendations status');
        }
        // If status is 'processing', continue polling
      } catch (error) {
        console.error("Error polling status:", error);
        clearInterval(this.pollingInterval);
        this.showIdleState(originalContent);
        alert('An error occurred while checking status.');
      }
    }, 2000); // Poll every 2 seconds
  }

  showProcessingState(originalContent = null) {
    const button = this.buttonTarget;
    button.disabled = true;
    // Store original content if not already stored (e.g., during initial status check)
    if (originalContent && !this.originalButtonContent) {
        this.originalButtonContent = originalContent;
    }
     button.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Generating...';
  }

  showIdleState(originalContent = null) {
    const button = this.buttonTarget;
    button.disabled = false;
    // Restore original content, use stored content if available, otherwise use passed content or default
    const contentToRestore = this.originalButtonContent || originalContent || 'Refresh Recommendations'; // Provide a default
    button.innerHTML = contentToRestore;
    this.originalButtonContent = null; // Clear stored content
  }

  disconnect() {
    // Clear interval when the controller disconnects (element is removed from DOM)
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
  }

  getMetaValue(name) {
    const element = document.head.querySelector(`meta[name="${name}"]`);
    return element.getAttribute("content");
  }
} 
