import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="recommendations"
export default class extends Controller {
  static targets = [
    "container",      // The main div holding recommendations
    "loadingSpinner", // The loading spinner div
    "detailsModal",   // The details modal element
    "modalBody"       // The body content area of the modal
  ]

  connect() {
    console.log('Recommendations controller connected');
    this.setupInitialCardState();
    this.attachEventListeners();
    // If the loading spinner is present on connect, start polling
    if (this.hasLoadingSpinnerTarget && !this.loadingSpinnerTarget.hidden) {
      console.log('Initial loading spinner found, starting status check.');
      this.checkRecommendationsStatus();
    }
  }

  disconnect() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
  }

  // --- Status Checking & Updates ---

  checkRecommendationsStatus() {
    // Prevent multiple polling intervals
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }

    this.pollingInterval = setInterval(async () => {
      try {
        const response = await fetch('/recommendations/check_status', {
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
          }
        });
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        const data = await response.json();

        console.log('Polling status:', data.status);

        if (data.status === 'ready') {
          clearInterval(this.pollingInterval);
          this.pollingInterval = null;
          // Fetch and render the updated recommendations partial
          this.fetchAndUpdateRecommendations();
        } else if (data.status === 'error') {
          clearInterval(this.pollingInterval);
          this.pollingInterval = null;
          this.showError(data.message || 'Failed to load recommendations.');
        }
        // If status is 'processing', continue polling
      } catch (error) {
        console.error('Error checking recommendations status:', error);
        clearInterval(this.pollingInterval);
        this.pollingInterval = null;
        this.showError('Error checking recommendation status. Please refresh.');
      }
    }, 3000); // Poll every 3 seconds
  }

  async fetchAndUpdateRecommendations() {
    try {
      if (this.hasLoadingSpinnerTarget) this.loadingSpinnerTarget.hidden = false;

      const response = await fetch(`/recommendations`, {
        headers: {
          'Accept': 'application/json', // Request JSON response
          'X-Requested-With': 'XMLHttpRequest'
        }
      });
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const data = await response.json();

      if (data.status === 'ready' || data.html) { // Check for status or direct HTML
        this.updateRecommendations(data.html);
      } else if (data.status === 'processing') {
        // Should ideally be handled by polling, but as a fallback:
        if (this.hasLoadingSpinnerTarget) this.loadingSpinnerTarget.hidden = false;
        if (!this.pollingInterval) { // Start polling if not already
          this.checkRecommendationsStatus();
        }
      } else {
         throw new Error(data.message || 'Received unexpected data format.');
      }
    } catch (error) {
      console.error('Error fetching recommendations:', error);
      this.showError('Failed to load recommendations. Please try again.');
    } finally {
       if (this.hasLoadingSpinnerTarget) this.loadingSpinnerTarget.hidden = true;
    }
  }

  updateRecommendations(html) {
    if (!this.hasContainerTarget) return;
    this.containerTarget.innerHTML = html;
    // Re-attach listeners AND re-initialize card states for the new content
    this.attachEventListeners();
    this.setupInitialCardState();
    this.updateWatchlistNavbar(); // Update navbar count after rendering new cards
  }

  showError(message) {
    if (!this.hasContainerTarget) return;
    this.containerTarget.innerHTML = `<div class="alert alert-danger">${message}</div>`;
    if (this.hasLoadingSpinnerTarget) this.loadingSpinnerTarget.hidden = true;
  }

  // --- Event Handling ---

  attachEventListeners() {
    // Attach listener to the controller's root element to capture clicks
    // both in the container and the modal.
    this.element.removeEventListener('click', this.handleContainerClick.bind(this)); // Remove old listener first
    this.element.addEventListener('click', this.handleContainerClick.bind(this));
  }

  handleContainerClick(event) {
     // Handle card clicks for details modal
    const card = event.target.closest('.card[data-id]');
    if (card && !event.target.closest('.watchlist-toggle, .watched-toggle, .rate-item')) { // Don't trigger modal if clicking buttons
      event.preventDefault();
      event.stopPropagation();
      console.log('Card clicked, attempting to show details...'); // Log: Card click detected
      const id = card.dataset.id;
      const type = card.dataset.type;
      // Correctly select the match score badge from the card title
      const matchScoreBadge = card.querySelector('.card-title .badge');
      // Extract text content, remove '%', and trim whitespace
      const matchScore = matchScoreBadge ? matchScoreBadge.textContent.replace('%', '').trim() : null;
      console.log('Extracted match score:', matchScore); // Log extracted score
      this.showDetails(id, type, matchScore);
      return; // Stop further processing for card click
    }

    // Handle watchlist toggle clicks
    const watchlistToggle = event.target.closest('.watchlist-toggle[data-source-id]');
    if (watchlistToggle) {
       event.preventDefault();
       event.stopPropagation();
       const sourceId = watchlistToggle.dataset.sourceId;
       const contentType = watchlistToggle.dataset.contentType;
       this.toggleWatchlist(sourceId, contentType);
       return;
    }

     // Handle watched toggle clicks
    const watchedToggle = event.target.closest('.watched-toggle[data-source-id]');
    if (watchedToggle) {
       event.preventDefault();
       event.stopPropagation();
       const sourceId = watchedToggle.dataset.sourceId;
       const contentType = watchedToggle.dataset.contentType;
       this.toggleWatched(sourceId, contentType);
       return;
    }

    // Handle rate button clicks (to show rating interface)
    const rateButton = event.target.closest('.rate-item[data-source-id]');
    if (rateButton && !event.target.closest('.rating-interface')) { // Don't re-trigger if clicking inside rating stars
       event.preventDefault();
       event.stopPropagation();
       this.showRatingInterface(rateButton);
       return;
    }

    // Handle rating star clicks
    const ratingStar = event.target.closest('.rating-interface .star[data-value]');
    if (ratingStar) {
       event.preventDefault();
       event.stopPropagation();
       this.handleStarClick(ratingStar);
       return;
    }

     // Handle rating submit clicks
    const ratingSubmit = event.target.closest('.rating-interface .submit-rating');
    if (ratingSubmit) {
       event.preventDefault();
       event.stopPropagation();
       this.submitRating(ratingSubmit);
       return;
    }

     // Handle rating cancel clicks
    const ratingCancel = event.target.closest('.rating-interface .cancel-rating');
    if (ratingCancel) {
       event.preventDefault();
       event.stopPropagation();
       this.cancelRating(ratingCancel);
       return;
    }
  }

  // --- Details Modal ---

  async showDetails(id, type, matchScore) {
    console.log('showDetails called with:', id, type, matchScore);
    // Log target detection
    console.log('Modal target found:', this.hasDetailsModalTarget);
    console.log('Modal body target found:', this.hasModalBodyTarget);

    if (!this.hasDetailsModalTarget || !this.hasModalBodyTarget) {
      console.error('Modal targets not found! Check data-recommendations-target attributes in HTML.');
      return;
    }

    // Show a temporary loading state in the modal
    this.modalBodyTarget.innerHTML = '<div class="text-center"><div class="spinner-border" role="status"><span class="visually-hidden">Loading...</span></div></div>';
    
    // Log before showing modal
    console.log('Attempting to get/create Bootstrap modal instance...');
    // Access Modal via the global bootstrap object
    const modal = bootstrap.Modal.getOrCreateInstance(this.detailsModalTarget);
    if (modal) {
        console.log('Bootstrap modal instance obtained, attempting to show...');
        modal.show();
    } else {
        console.error('Failed to get Bootstrap modal instance.');
        return;
    }

    try {
      // Fetch details
      const detailsResponse = await fetch(`/recommendations/${id}?type=${type}`);
      if (!detailsResponse.ok) throw new Error(`Network response was not ok fetching details: ${detailsResponse.status}`);
      const detailsData = await detailsResponse.json();
      console.log('Recommendation data received:', detailsData);

      // Fetch watchlist status
      const watchlistResponse = await fetch(`/watchlist/status?source_id=${detailsData.source_id}&content_type=${type}`);
      const watchlistData = watchlistResponse.ok ? await watchlistResponse.json() : { in_watchlist: false, watched: false, rating: null };
      console.log('Watchlist status received:', watchlistData);

      // Combine data
      const data = {
        ...detailsData,
        inWatchlist: watchlistData.in_watchlist,
        watched: watchlistData.watched,
        rating: watchlistData.rating,
        country: detailsData.production_countries ?
                  detailsData.production_countries.map(c => c.name === 'United States of America' ? 'USA' : c.name).join(', ') :
                  'N/A',
        match_score: matchScore // Use the score passed from the card
      };

      // Generate and insert content
      const modalContent = this.generateModalContent(data);
      this.modalBodyTarget.innerHTML = modalContent;
      // Note: Event listeners for buttons inside the modal are handled by delegation in handleContainerClick

    } catch (error) {
      console.error('Error loading details:', error);
      this.modalBodyTarget.innerHTML = '<div class="alert alert-danger">Failed to load details. Please try again.</div>';
    }
  }

  generateModalContent(data) {
    var details = `
      <div class="row">
        <div class="col-md-4 mb-3 mb-md-0">
          <img src="https://image.tmdb.org/t/p/w500${data.poster_path}" class="img-fluid rounded" alt="${data.title || data.name} poster" role="img">
        </div>
        <div class="col-md-8">
          <div class="d-flex justify-content-between align-items-start mb-3">
            <h2 class="text-warning mb-2">${data.title || data.name}</h2>
            ${data.match_score ? `<span class="badge badge-large bg-warning" role="status" aria-label="Match score">${data.match_score}%</span>` : ''}
          </div>
          <div class="d-flex justify-content-between">
            <div>
              <p class="mb-1 small"><strong>Runtime:</strong> ${data.runtime || (data.episode_run_time && data.episode_run_time[0]) || 'N/A'} min</p>
              <p class="mb-1 small"><strong>Release Year:</strong> ${(data.release_date || data.first_air_date || '').substring(0, 4)}</p>
              <p class="mb-1 small"><strong>Country:</strong> ${data.country || 'N/A'}</p>
              <p class="mb-1 small"><strong>TMDb Rating:</strong> ${data.vote_average ? `${data.vote_average.toFixed(1)} (${data.vote_count} votes)` : 'N/A'}</p>
            </div>
            <div class="d-flex flex-column">
              <button class="btn btn-primary btn-sm watchlist-toggle mb-2 ${data.inWatchlist ? 'in-watchlist' : ''}"
                      data-action="click->recommendations#handleContainerClick"
                      data-source-id="${data.source_id}"
                      data-content-type="${data.content_type}"
                      aria-label="${data.inWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist'}">
                <i class="fas fa-bookmark ${data.inWatchlist ? 'text-warning' : 'text-muted'}" 
                   alt="${data.inWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist'}"></i>
                <span class="watchlist-text ms-1">${data.inWatchlist ? 'Remove' : 'Add'}</span>
              </button>
              <button class="btn btn-secondary btn-sm watched-toggle mb-2 ${data.inWatchlist && data.watched ? 'watched' : ''}"
                      data-action="click->recommendations#handleContainerClick"
                      data-source-id="${data.source_id}"
                      data-content-type="${data.content_type}"
                      aria-label="${data.inWatchlist && data.watched ? 'Mark as Unwatched' : 'Mark as Watched'}"
                      style="display: ${data.inWatchlist ? 'block' : 'none'};">
                <i class="fas ${data.inWatchlist && data.watched ? 'fa-eye-slash' : 'fa-eye'}"
                   alt="${data.inWatchlist && data.watched ? 'Mark as Unwatched' : 'Mark as Watched'}"></i>
                <span class="watched-text ms-1">${data.inWatchlist && data.watched ? 'Mark as Unwatched' : 'Mark as Watched'}</span>
              </button>
              <button class="btn btn-warning btn-sm rate-item ${data.rating ? 'rated' : ''}"
                      data-action="click->recommendations#handleContainerClick"
                      data-source-id="${data.source_id}"
                      data-content-type="${data.content_type}"
                      data-title="${data.title || data.name}"
                      data-rating="${data.rating || 0}"
                      style="display: ${data.inWatchlist && data.watched ? 'block' : 'none'};">
                <i class="fas fa-star"></i>
                <span class="rate-text">Rate${data.rating ? `d (${data.rating})` : ''}</span>
              </button>
              <div id="rating-container" class="rating-interface" style="display: none;">
                <div class="rating-stars">
                  ${[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(star => `
                    <span class="star" data-action="click->recommendations#handleContainerClick" data-value="${star}">★</span>
                  `).join('')}
                </div>
                <div class="rating-actions">
                  <button class="btn btn-sm btn-primary submit-rating" data-action="click->recommendations#handleContainerClick">Submit</button>
                  <button class="btn btn-sm btn-secondary cancel-rating" data-action="click->recommendations#handleContainerClick">Cancel</button>
                </div>
              </div>
            </div>
          </div>
          <p class="mb-1 small"><strong>Genres:</strong> ${(data.genres || []).map(g => typeof g === 'string' ? g : g.name).join(', ')}</p>
          <p class="mb-1 small"><strong>Description:</strong> ${data.overview}</p>
          ${data.content_type === 'movie' ?
            `<p class="mb-1 small"><strong>Director(s):</strong> ${(data.credits?.crew || []).filter(c => c.job === 'Director').map(d => d.name).join(', ') || 'N/A'}</p>` :
            `<p class="mb-1 small"><strong>Creator(s):</strong> ${data.creators ? data.creators.join(', ') : 'N/A'}</p>`
          }
          <p class="mb-1 small"><strong>Cast:</strong> ${(data.credits?.cast || []).slice(0, 5).map(c => c.name).join(', ') || 'N/A'}</p>
          <p class="mb-1 small"><strong>Spoken Languages:</strong> ${(data.spoken_languages || []).map(l => l.name).join(', ') || 'N/A'}</p>
        </div>
      </div>
      ${data.recommendation_reason ? `<p class="mt-3 mb-1 small fst-italic"><i class="fas fa-lightbulb text-info me-2"></i><strong>Why you might like this:</strong> ${data.recommendation_reason}</p>` : ''}
      <div class="embed-responsive embed-responsive-16by9 mt-3">
        ${data.trailer_url ? `
          <iframe class="embed-responsive-item" width="100%" height="315" src="${data.trailer_url.replace('watch?v=', 'embed/')}" allowfullscreen title="${data.title || data.name} trailer"></iframe>
        ` : '<p class="text-center text-muted mt-3 small">Trailer not available.</p>'}
      </div>
    `;
    return details;
  }


  // --- Watchlist & Rating Logic ---

  async toggleWatchlist(sourceId, contentType) {
     console.log('Toggling watchlist for:', sourceId, contentType);

     // Query DOM within the modal to find the button and check its state
     const buttonInModal = this.modalBodyTarget?.querySelector(`.watchlist-toggle[data-source-id="${sourceId}"]`);
     const isInWatchlist = buttonInModal?.classList.contains('in-watchlist'); // Check for 'in-watchlist' class set by updatePopupUI
     console.log('Current isInWatchlist based on modal button query:', isInWatchlist);

     const endpoint = isInWatchlist ? `/watchlist/${sourceId}?content_type=${contentType}` : '/watchlist';
     const method = isInWatchlist ? 'DELETE' : 'POST';
     const body = isInWatchlist ? null : JSON.stringify({
        watchlist_item: { source_id: sourceId, content_type: contentType }
     });

     try {
        const response = await fetch(endpoint, {
           method: method,
           headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': this.getMetaValue("csrf-token"),
              'X-Requested-With': 'XMLHttpRequest',
              'Accept': 'application/json'
           },
           body: body
        });
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        const data = await response.json();

        if (data.status === 'success' || data.in_watchlist !== undefined) {
            const newInWatchlist = data.in_watchlist !== undefined ? data.in_watchlist : !isInWatchlist;
            // When removing, watched/rating is irrelevant
            const watchedStatus = newInWatchlist ? (data.watched || false) : false;
            const ratingStatus = newInWatchlist ? (data.rating || null) : null;
            this.updateWatchlistUI(sourceId, newInWatchlist, watchedStatus, ratingStatus);
            this.updateWatchlistNavbar();
         } else {
           throw new Error(data.message || 'Watchlist toggle failed');
         }
     } catch (error) {
        console.error('Error toggling watchlist:', error);
        // Optional: show an error message to the user
     }
  }

  async toggleWatched(sourceId, contentType) {
    console.log('Toggling watched for:', sourceId, contentType);

    // Query DOM within the modal to find the button and check its state
    const buttonInModal = this.modalBodyTarget?.querySelector(`.watched-toggle[data-source-id="${sourceId}"]`);
    const isWatched = buttonInModal?.classList.contains('watched'); // Check for 'watched' class set by updatePopupUI
    console.log('Current isWatched based on modal button query:', isWatched);

    const newWatchedStatus = !isWatched;

    // Optimistic UI update (can be reverted on error)
    // Assume it's in watchlist (button wouldn't show otherwise)
    // We don't know the rating yet, fetch will confirm
    this.updateWatchlistUI(sourceId, true, newWatchedStatus, null);

    // If marking as unwatched, also clear the rating immediately via separate request
    if (!newWatchedStatus) {
       this.rateItem(sourceId, contentType, null); // Send null rating
    }

    try {
       const response = await fetch(`/watchlist/${sourceId}/toggle_watched`, {
          method: 'POST',
          headers: {
             'Content-Type': 'application/json',
             'X-CSRF-Token': this.getMetaValue("csrf-token"),
             'X-Requested-With': 'XMLHttpRequest',
             'Accept': 'application/json'
          },
          body: JSON.stringify({ content_type: contentType, watched: newWatchedStatus })
       });
       if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
       const data = await response.json();

       if (data.status === 'success') {
          console.log('Item watched status updated:', data);
          // Update UI with confirmed status from server
          this.updateWatchlistUI(sourceId, data.in_watchlist, data.watched, data.rating);
          this.updateWatchlistNavbar(); // Ensure navbar count is accurate

          // If just marked as watched, maybe prompt for rating?
          // if (newWatchedStatus) { /* maybe call rating logic */ }

       } else {
          throw new Error(data.message || 'Toggle watched failed');
          // Revert optimistic update
          // this.updateWatchlistUI(sourceId, true, isWatched, /* need old rating? */);
       }
    } catch (error) {
       console.error('Error toggling watched:', error);
       // Revert optimistic update
       // this.updateWatchlistUI(sourceId, true, isWatched, /* need old rating? */);
    }
 }


  showRatingInterface(rateButton) {
    const ratingContainer = rateButton.closest('.modal-body, .card-body').querySelector('.rating-interface');
    if (!ratingContainer) return;

    const sourceId = rateButton.dataset.sourceId;
    const contentType = rateButton.dataset.contentType;
    const currentRating = parseInt(rateButton.dataset.rating) || 0;

    // Setup stars
    const stars = ratingContainer.querySelectorAll('.star');
    stars.forEach(star => {
      star.classList.remove('active'); // Clear previous state
      star.style.color = 'lightgray'; // Reset color
      if (parseInt(star.dataset.value) <= currentRating) {
         star.classList.add('active');
         star.style.color = 'gold';
      }
      // Add hover effect
      star.onmouseover = () => this.highlightStars(stars, parseInt(star.dataset.value));
      star.onmouseout = () => this.highlightStars(stars, ratingContainer.querySelectorAll('.star.active').length); // Highlight current selection on mouseout
    });

    // Store sourceId/contentType on the container for submit/cancel
    ratingContainer.dataset.sourceId = sourceId;
    ratingContainer.dataset.contentType = contentType;

    // Highlight initially selected stars
    this.highlightStars(stars, currentRating);

    // Show rating interface
    ratingContainer.style.display = 'block';
    rateButton.classList.add('rating-active'); // Indicate rating is in progress
  }

  highlightStars(stars, value) {
      stars.forEach(star => {
          star.style.color = parseInt(star.dataset.value) <= value ? 'gold' : 'lightgray';
      });
  }


  handleStarClick(clickedStar) {
    const ratingContainer = clickedStar.closest('.rating-interface');
    if (!ratingContainer) return;
    const stars = ratingContainer.querySelectorAll('.star');
    const value = parseInt(clickedStar.dataset.value);

    stars.forEach(s => {
      s.classList.toggle('active', parseInt(s.dataset.value) <= value);
    });

    // Highlight stars visually based on selection
    this.highlightStars(stars, value);

    // Enable submit button
    ratingContainer.querySelector('.submit-rating').disabled = false;
  }

  async submitRating(submitButton) {
     const ratingContainer = submitButton.closest('.rating-interface');
     if (!ratingContainer) return;

     const rating = ratingContainer.querySelectorAll('.star.active').length;
     const sourceId = ratingContainer.dataset.sourceId;
     const contentType = ratingContainer.dataset.contentType;

     console.log(`Submitting rating ${rating} for ${sourceId} (${contentType})`);

     await this.rateItem(sourceId, contentType, rating);

     // Hide interface after submission
     ratingContainer.style.display = 'none';
     const rateButton = this.findRateButton(sourceId); // Find the main rate button
     if(rateButton) {
       rateButton.classList.remove('rating-active');
       rateButton.classList.add('rated'); // Add the 'rated' class for styling
     }
  }

  cancelRating(cancelButton) {
    const ratingContainer = cancelButton.closest('.rating-interface');
    if (!ratingContainer) return;
    ratingContainer.style.display = 'none';

    const sourceId = ratingContainer.dataset.sourceId;
    const rateButton = this.findRateButton(sourceId); // Find the main rate button
    if(rateButton) rateButton.classList.remove('rating-active');
  }

  async rateItem(sourceId, contentType, rating) {
    // Rating can be null to clear it
    try {
      const response = await fetch(`/watchlist/rate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getMetaValue("csrf-token"),
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          watchlist_item: {
            source_id: sourceId,
            content_type: contentType,
            rating: rating // Send null to clear rating
          }
        })
      });
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const data = await response.json();

      if (data.status === 'success') {
         console.log('Rating success:', data);
         // Update UI based on the response (which confirms in_watchlist, watched, rating)
         this.updateWatchlistUI(sourceId, data.in_watchlist, data.watched, data.rating);
         this.updateWatchlistNavbar();
      } else {
         throw new Error(data.message || 'Rating update failed');
      }
    } catch (error) {
      console.error('Error rating item:', error);
      // Optional: show error message
    }
  }


  // --- UI Updates ---

  setupInitialCardState() {
    if (!this.hasContainerTarget) return;
    const cards = this.containerTarget.querySelectorAll('.card[data-source-id]');
    console.log(`Found ${cards.length} cards for initial state setup.`); // Log: Found cards
    cards.forEach(card => {
      const sourceId = card.dataset.sourceId;
      // Read state directly from data attributes set by the Rails partial
      const inWatchlist = card.dataset.inWatchlist === 'true';
      const watched = card.dataset.watched === 'true';
      const ratingStr = card.dataset.rating; // Get rating as string
      const rating = ratingStr && ratingStr !== 'null' && ratingStr !== '' ? parseInt(ratingStr) : null; // Parse carefully
      console.log(`Card ${sourceId}: inWatchlist=${inWatchlist}, watched=${watched}, rating=${rating}`); // Log: Card state
      this.updateCardIcon(sourceId, inWatchlist, watched, rating);
    });
  }

  updateWatchlistUI(sourceId, inWatchlist, watched, rating) {
     console.log('updateWatchlistUI called with:', sourceId, inWatchlist, watched, rating);
     // Update card in the main recommendations list
     const card = this.containerTarget?.querySelector(`.card[data-source-id="${sourceId}"]`);
     if (card) {
        this.updateCardIcon(sourceId, inWatchlist, watched, rating);
     }

     // Update buttons within the currently open modal, if any
     const modalBody = this.modalBodyTarget; // Use the target
     if (modalBody && modalBody.querySelector(`[data-source-id="${sourceId}"]`)) {
        this.updatePopupUI(modalBody, sourceId, inWatchlist, watched, rating);
     }
  }

  updateCardIcon(sourceId, inWatchlist, watched, rating) {
    console.log(`Updating card icon for ${sourceId}: inWatchlist=${inWatchlist}, watched=${watched}, rating=${rating}`);
    
    const card = document.querySelector(`#card-${sourceId}`);
    if (!card) {
      console.error(`Card not found for source ID: ${sourceId}`);
      return;
    }

    const iconParentContainer = card.querySelector('.col-8');
    console.log('Found icon parent container:', iconParentContainer);

    // First, remove any existing icon container
    const existingIconContainer = iconParentContainer.querySelector('.position-absolute');
    if (existingIconContainer) {
      existingIconContainer.remove();
      console.log('>>> Removed existing icon container');
    }

    // Only create new icon if in watchlist
    if (inWatchlist) {
      const newIconContainer = document.createElement('div');
      newIconContainer.className = 'position-absolute bottom-0 end-0 m-3';
      
      let iconHtml = '';
      if (rating) {
        iconHtml = `<div class="star-score card-icon-display" title="Your rating: ${rating}/10"><span>${rating}</span></div>`;
        console.log('>>> Created rating icon');
      } else if (watched) {
        iconHtml = '<i class="fas fa-eye fs-5 card-icon-display" title="Watched"></i>';
        console.log('>>> Created watched icon');
      } else {
        iconHtml = '<i class="fas fa-bookmark fs-5 card-icon-display" title="In Watchlist"></i>';
        console.log('>>> Created watchlist icon');
      }
      
      newIconContainer.innerHTML = iconHtml;
      iconParentContainer.appendChild(newIconContainer);
      console.log('>>> Added new icon container to card');
    }

    // Update background classes
    const existingClasses = ['card-bg-watchlist-rated', 'card-bg-watchlist-watched', 'card-bg-watchlist-unwatched'];
    console.log('>>> Called classList.remove for backgrounds. Were present:', 
      existingClasses.reduce((acc, cls) => ({...acc, [cls.split('-').pop()]: card.classList.contains(cls)}), {}));
    
    existingClasses.forEach(cls => card.classList.remove(cls));
    console.log('>>> Card className AFTER removal:', card.className);

    if (inWatchlist) {
      const newClass = rating ? 'card-bg-watchlist-rated' 
                    : watched ? 'card-bg-watchlist-watched' 
                    : 'card-bg-watchlist-unwatched';
      card.classList.add(newClass);
      console.log(`>>> Added new background class: ${newClass}`);
    } else {
      console.log('>>> No new background class to add.');
    }
  }

  updatePopupUI(modalBody, sourceId, inWatchlist, watched, rating) {
    const watchlistButton = modalBody.querySelector('.watchlist-toggle');
    const watchedButton = modalBody.querySelector('.watched-toggle');
    const rateButton = modalBody.querySelector('.rate-item');
    const matchScoreContainer = modalBody.querySelector('.match-score');

    // Add match score if it exists
    const headerActions = modalBody.querySelector('.modal-header .actions');
    if (headerActions && matchScoreContainer && matchScoreContainer.dataset.score) {
      const matchBadge = headerActions.querySelector('.match-badge') || document.createElement('div');
      matchBadge.className = 'match-badge badge bg-success me-2';
      matchBadge.innerHTML = `${matchScoreContainer.dataset.score}% Match`;
      if (!headerActions.contains(matchBadge)) {
        headerActions.insertBefore(matchBadge, headerActions.firstChild);
      }
    }

    if (watchlistButton) {
      watchlistButton.classList.toggle('in-watchlist', inWatchlist);
      watchlistButton.innerHTML = `
        <i class="fas fa-bookmark ${inWatchlist ? 'text-warning' : 'text-muted'}" 
           alt="${inWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist'}"></i>
        <span class="watchlist-text ms-1">${inWatchlist ? 'Remove' : 'Add'}</span>
      `;
    }

    if (watchedButton) {
      watchedButton.classList.toggle('watched', watched);
      watchedButton.innerHTML = `
        <i class="fas ${watched ? 'fa-eye-slash' : 'fa-eye'}" 
           alt="${watched ? 'Mark as Unwatched' : 'Mark as Watched'}"></i>
        <span class="watched-text ms-1">${watched ? 'Mark as Unwatched' : 'Mark as Watched'}</span>
      `;
      watchedButton.style.display = inWatchlist ? 'inline-block' : 'none';
    }

    if (rateButton) {
      rateButton.style.display = (inWatchlist && watched) ? 'inline-block' : 'none';
      rateButton.classList.toggle('rated', !!rating); // Toggle the 'rated' class based on rating existence
      if (rating) {
        rateButton.innerHTML = `
          <i class="fas fa-star text-warning"></i>
          <span class="rating-text ms-1">Rated ${rating}/10</span>
        `;
      } else {
        rateButton.innerHTML = `
          <i class="fas fa-star text-muted"></i>
          <span class="rating-text ms-1">Rate</span>
        `;
      }
    }
  }

  // This assumes navbar-watchlist-updater controller exists and dispatches this event
  updateWatchlistNavbar() {
    // Dispatch a custom event that the navbar controller can listen for
    // This decouples the recommendations controller from the navbar implementation
    window.dispatchEvent(new CustomEvent('watchlistUpdated'));
    console.log('Dispatched watchlistUpdated event');
  }

  // --- Helpers ---

  getMetaValue(name) {
    const element = document.head.querySelector(`meta[name="${name}"]`);
    return element ? element.getAttribute("content") : null;
  }

  findRateButton(sourceId) {
      // Find rate button either in modal or potentially on a card if modal isn't open/relevant
      const modalButton = this.modalBodyTarget?.querySelector(`.rate-item[data-source-id="${sourceId}"]`);
      if (modalButton) return modalButton;
      return this.containerTarget?.querySelector(`.rate-item[data-source-id="${sourceId}"]`);
  }

} 
