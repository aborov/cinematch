import { Controller } from "@hotwired/stimulus"
import Sortable from 'sortablejs'; // Import SortableJS

// Connects to data-controller="watchlist"
export default class extends Controller {
  static targets = [
    "unwatchedList", 
    "watchedList",   
    "unwatchedCount",
    "watchedCount",  
    "detailsModal",  
    "modalBody",
  ]

  static values = {
    sortableResourceUrl: String 
  }

  connect() {
    console.log("Watchlist controller connected");
    this.initializeSortable();
  }

  disconnect() {
    if (this.unwatchedSortable) {
      this.unwatchedSortable.destroy();
    }
    if (this.watchedSortable) {
      this.watchedSortable.destroy();
    }
  }

  initializeSortable() {
    if (this.hasUnwatchedListTarget) {
      this.unwatchedSortable = this.createSortableInstance(this.unwatchedListTarget);
    }
    if (this.hasWatchedListTarget) {
      this.watchedSortable = this.createSortableInstance(this.watchedListTarget);
    }
  }

  createSortableInstance(element) {
    return new Sortable(element, {
      group: 'watchlist',
      handle: '.drag-handle',
      animation: 150,
      onEnd: this.handleSortEnd.bind(this)
    });
  }

  handleSortEnd(evt) {
    if (evt.oldIndex === evt.newIndex && evt.from === evt.to) {
      return; 
    }

    const item = evt.item;
    const sourceId = item.dataset.watchlistSourceIdValue;
    const contentType = item.dataset.watchlistContentTypeValue;
    const newPosition = Array.from(item.parentNode.children)
      .filter(child => child.matches('.watchlist-item'))
      .indexOf(item) + 1;
    const isWatched = evt.to === this.watchedListTarget;

    this.fetchAPI(`/watchlist/${sourceId}/reposition`, 'POST', {
      watchlist_item: {
        position: newPosition,
        content_type: contentType,
        watched: isWatched
      }
    })
    .then(data => {
      if (data.status === 'success') {
        console.log('Reposition successful');
        this.updateSectionCounts();
        this.dispatchWatchlistChangeEvent();
      } else {
        throw new Error(data.message || 'Reposition failed on server');
      }
    })
    .catch(error => {
      console.error('Error repositioning:', error);
      if (evt.from && typeof evt.oldDraggableIndex !== 'undefined') {
          evt.from.insertBefore(item, evt.from.children[evt.oldDraggableIndex]);
      }
      if (evt.from !== evt.to) {
           console.warn("Cross-list drag revert not fully implemented on error.");
      }
      this.showError('Failed to save new position. Please try again.');
    });
  }


  // --- Action Handlers ---

  toggleWatched(event) {
    event.preventDefault();
    event.stopPropagation();
    const button = event.currentTarget;
    const sourceId = button.dataset.watchlistSourceIdValue;
    const contentType = button.dataset.watchlistContentTypeValue;
    this.handleWatchlistAction('toggleWatched', sourceId, contentType, button);
  }

  removeItem(event) {
    event.preventDefault();
    event.stopPropagation();
    const button = event.currentTarget;
    const card = button.closest('.watchlist-item');
    const watchlistItemId = card?.dataset.watchlistItemIdValue; 
    
    if (!watchlistItemId) {
      console.error("Could not find watchlist item ID for removal.");
      this.showError("Could not remove item. ID missing.");
      return;
    }

    if (confirm('Are you sure you want to remove this item from your watchlist?')) {
        this.handleWatchlistAction('removeItem', watchlistItemId, null, button); 
    }
  }

  rateItem(event) {
    event.preventDefault();
    event.stopPropagation();
    const button = event.currentTarget;
    const sourceId = button.dataset.watchlistSourceIdValue;
    const contentType = button.dataset.watchlistContentTypeValue;
    const currentRating = parseInt(button.dataset.watchlistRatingValue) || 0;
    const card = button.closest('.watchlist-item');
    const isWatched = card ? card.closest('[data-watchlist-target="watchedList"]') !== null : false;

    this.handleRating(sourceId, contentType, currentRating, isWatched, card);
  }

  showDetails(event) {
    if (event.target.closest('button, a')) {
      return;
    }
    event.preventDefault();
    const card = event.currentTarget;
    const sourceId = card.dataset.watchlistSourceIdValue;
    const contentType = card.dataset.watchlistContentTypeValue;
    this.showDetailsPopup(sourceId, contentType);
  }

  toggleWatchlistItemInModal(event) {
      event.preventDefault();
      event.stopPropagation();
      const button = event.currentTarget;
      const sourceId = button.dataset.watchlistSourceIdValue;
      const contentType = button.dataset.watchlistContentTypeValue;
      const isInWatchlist = button.classList.contains('in-watchlist');
      const action = isInWatchlist ? 'removeItem' : 'addItem';
      const identifier = isInWatchlist ? button.closest('.modal-content').querySelector('[data-watchlist-item-id-value]')?.dataset.watchlistItemIdValue || sourceId : sourceId;

      this.handleWatchlistAction(action, identifier, contentType, button)
          .then(data => {
              if (data.status === 'success') {
                  const isNowInWatchlist = !isInWatchlist;
                  const watchedStatus = data.watched !== undefined ? data.watched : false;
                  const rating = data.rating !== undefined ? data.rating : null;

                   this.updatePopupUI(this.modalBodyTarget, sourceId, isNowInWatchlist, watchedStatus, rating);

                  if (isNowInWatchlist) {
                       this.fetchItemDataAndCreateCard(sourceId, contentType, data.id);
                  } else {
                      this.removeCardFromUI(sourceId);
                  }
                  this.updateSectionCounts();
              }
          });
  }

    toggleWatchedInModal(event) {
        event.preventDefault();
        event.stopPropagation();
        const button = event.currentTarget;
        const sourceId = button.dataset.watchlistSourceIdValue;
        const contentType = button.dataset.watchlistContentTypeValue;
        this.handleWatchlistAction('toggleWatched', sourceId, contentType, button)
            .then(data => {
                if (data.status === 'success') {
                    this.updatePopupUI(this.modalBodyTarget, sourceId, true, data.watched, data.rating);
                    this.updateWatchlistCardUI(sourceId, true, data.watched, data.rating);
                    this.updateSectionCounts();
                }
            });
    }

    rateItemInModal(event) {
        event.preventDefault();
        event.stopPropagation();
        const button = event.currentTarget;
        const sourceId = button.dataset.watchlistSourceIdValue;
        const contentType = button.dataset.watchlistContentTypeValue;
        const currentRating = parseInt(button.dataset.watchlistRatingValue) || 0;
        const titleElement = button.closest('.modal-content').querySelector('.modal-title');
        const title = titleElement ? titleElement.textContent.replace('Rate "', '').replace('"','') : 'this item';

        this.createRatingPopup(sourceId, contentType, title, currentRating) 
         .then(rating => {
           return this.submitRating(sourceId, contentType, rating);
         })
         .then(data => {
            if (data.status === 'success') {
               this.updatePopupUI(this.modalBodyTarget, sourceId, true, true, data.rating);
               this.updateWatchlistCardUI(sourceId, true, true, data.rating);
               this.updateSectionCounts();
            }
         })
         .catch(error => {
           if (error !== 'Rating cancelled' && error !== 'Rating cancelled via dismiss') {
             console.error('Error during modal rating process:', error);
             this.showError('Failed to save rating.');
           }
         });
    }


  // --- Core Logic Functions ---

  async handleWatchlistAction(action, identifier, contentType, initiatingElement) {
    let url, method;
    let body;

    switch (action) {
        case 'toggleWatched':
            url = `/watchlist/${identifier}/toggle_watched`; 
            method = 'POST';
             body = {
                 watchlist_item: {
                     source_id: identifier, 
                    content_type: contentType
                 }
             };
            break;
        case 'removeItem':
            url = `/watchlist/${identifier}`; 
            method = 'DELETE';
            body = undefined; 
            console.log(`Attempting to remove item. Identifier: ${identifier}, URL: ${url}`); // Keep log
            break;
        case 'addItem':
            url = `/watchlist`;
            method = 'POST';
             body = {
                 watchlist_item: {
                     source_id: identifier,
                    content_type: contentType
                 }
             };
            break;
        default:
            console.error("Invalid watchlist action:", action);
            return Promise.reject("Invalid action");
    }

    try {
        const sourceIdForUI = (action === 'removeItem') 
            ? initiatingElement?.closest('.watchlist-item')?.dataset.watchlistSourceIdValue 
            : (action === 'toggleWatched' ? identifier : identifier);
        
        const watchlistItemIdForUI = (action === 'removeItem') 
            ? identifier 
            : initiatingElement?.closest('.watchlist-item')?.dataset.watchlistItemIdValue;
            
        const data = await this.fetchAPI(url, method, body);
        
        if (data.status === 'success') {
            console.log(`Action ${action} successful for identifier ${identifier}`);

            const isNowInWatchlist = action === 'addItem' || (action !== 'removeItem' && (initiatingElement?.closest('.watchlist-item') || this.findCard(sourceIdForUI)));
            const isNowWatched = data.watched !== undefined ? data.watched : (action === 'toggleWatched' ? !initiatingElement?.classList.contains('watched') : false);
            const rating = data.rating !== undefined ? data.rating : null;

            if (action === 'removeItem') {
                 this.removeCardFromUI(sourceIdForUI); 
            } else if (action === 'addItem') {
                 await this.fetchItemDataAndCreateCard(identifier, contentType, data.id); 
                 this.updateWatchlistCardUI(identifier, true, false, null); 
            } else if (action === 'toggleWatched') {
                 this.updateWatchlistCardUI(identifier, true, data.watched, data.rating); 
            }

            if (this.hasModalBodyTarget && this.modalBodyTarget.querySelector(`[data-watchlist-source-id-value="${sourceIdForUI}"]`)) {
                this.updatePopupUI(this.modalBodyTarget, sourceIdForUI, isNowInWatchlist, isNowWatched, rating);
             }

            this.updateSectionCounts();
             this.dispatchWatchlistChangeEvent(); 
             return data;
        } else {
            throw new Error(data.message || `Action ${action} failed on server`);
        }
    } catch (error) {
        console.error(`Error performing ${action}:`, error);
        this.showError(`Failed to ${action.replace(/([A-Z])/g, ' $1').toLowerCase()}. Please try again.`);
         return Promise.reject(error); 
    }
}


 async handleRating(sourceId, contentType, currentRating, isWatched, cardElement) {
    const title = cardElement ? cardElement.querySelector('.card-title')?.textContent.trim() : "this item";

    try {
        const rating = await this.createRatingPopup(sourceId, contentType, title, currentRating);

        let watchedStatusData = { watched: true };
         if (!isWatched) {
             const toggleData = await this.fetchAPI(`/watchlist/${sourceId}/toggle_watched`, 'POST', { watchlist_item: { source_id: sourceId, content_type: contentType } });
              if (toggleData.status !== 'success' || !toggleData.watched) {
                    throw new Error("Failed to mark item as watched before rating.");
              }
              watchedStatusData = toggleData;
               this.updateWatchlistCardUI(sourceId, true, true, null);
         }

        const ratingData = await this.submitRating(sourceId, contentType, rating);

        if (ratingData.status === 'success') {
             this.updateWatchlistCardUI(sourceId, true, true, ratingData.rating);
             if (this.hasModalBodyTarget && this.modalBodyTarget.querySelector(`[data-watchlist-source-id-value="${sourceId}"]`)) {
               this.updatePopupUI(this.modalBodyTarget, sourceId, true, true, ratingData.rating);
            }
            this.updateSectionCounts();
            this.dispatchWatchlistChangeEvent();
        } else {
            throw new Error(ratingData.message || "Rating submission failed");
        }
    } catch (error) {
        if (error === 'Rating cancelled' || error === 'Rating cancelled via dismiss') {
            console.log('Rating cancelled by user.');
        } else {
            console.error('Error during rating process:', error);
            this.showError('Failed to save rating.');
        }
    }
}


  async submitRating(sourceId, contentType, rating) {
    return this.fetchAPI(`/watchlist/rate`, 'POST', {
      watchlist_item: {
        source_id: sourceId,
        content_type: contentType,
        rating: rating
      }
    });
  }

  // --- UI Update Functions ---

  updateWatchlistCardUI(sourceId, inWatchlist, watched, rating) {
    const card = this.findCard(sourceId);
    if (!card) {
        console.warn("Card not found in UI for update:", sourceId);
        return;
    }

    const watchButton = card.querySelector('[data-action*="watchlist#toggleWatched"]');
    const rateButton = card.querySelector('[data-action*="watchlist#rateItem"]');

    if (watchButton) {
      watchButton.classList.toggle('btn-warning', watched);
      watchButton.classList.toggle('btn-success', !watched);
      watchButton.classList.toggle('mark-unwatched', watched);
      watchButton.classList.toggle('mark-watched', !watched);

      const watchIcon = watchButton.querySelector('i');
      const watchText = watchButton.querySelector('.button-text');
      if (watchIcon) watchIcon.className = `fas ${watched ? 'fa-eye-slash' : 'fa-eye'}`;
      if (watchText) watchText.textContent = watched ? 'Unwatched' : 'Watched';
       watchButton.setAttribute('aria-label', watched ? 'Mark as Unwatched' : 'Mark as Watched');
    }

    if (rateButton) {
        rateButton.classList.toggle('btn-warning', !!rating);
        rateButton.classList.toggle('btn-primary', !rating);
        rateButton.classList.toggle('rated', !!rating);
        rateButton.dataset.watchlistRatingValue = rating || 0;

        const rateText = rateButton.querySelector('.button-text');
         if (rateText) rateText.textContent = rating ? `${rating}/10` : 'Rate';
         rateButton.setAttribute('aria-label', rating ? `Rated ${rating}/10. Click to change rating.` : 'Rate this item');
         // Optional: Show/hide based on watched status - handled by moving card for now
         // rateButton.style.display = watched ? 'inline-flex' : 'none'; 
    }

    const targetList = watched ? this.watchedListTarget : this.unwatchedListTarget;
    const currentList = card.parentElement;

    if (targetList && currentList !== targetList) {
      targetList.insertBefore(card, targetList.firstChild);
       this.refreshSortable(targetList);
       this.refreshSortable(currentList);
    }
  }

    removeCardFromUI(sourceId) {
        const card = this.findCard(sourceId);
        if (card) {
            const parentList = card.parentElement;
            card.remove();
            console.log("Removed card from UI:", sourceId);
             this.updateSectionCounts();
             if(parentList) this.refreshSortable(parentList);
        } else {
             console.warn("Card not found in UI for removal:", sourceId);
        }
    }

    findCard(sourceId) {
        return this.element.querySelector(`.watchlist-item[data-watchlist-source-id-value="${sourceId}"]`);
    }

    refreshSortable(listElement) {
         console.log("Sortable refresh potentially needed for list:", listElement.id);
         // const sortableInstance = Sortable.get(listElement);
         // if (sortableInstance) sortableInstance.option("disabled", listElement.children.length === 0); // Example: disable if empty
    }


  updateSectionCounts() {
    if (this.hasUnwatchedListTarget && this.hasUnwatchedCountTarget) {
      this.unwatchedCountTarget.textContent = this.unwatchedListTarget.querySelectorAll('.watchlist-item').length;
    }
    if (this.hasWatchedListTarget && this.hasWatchedCountTarget) {
      this.watchedCountTarget.textContent = this.watchedListTarget.querySelectorAll('.watchlist-item').length;
    }
  }

  // --- Details Popup Logic ---

  async showDetailsPopup(sourceId, contentType) {
    // Ensure modal target exists before proceeding
    if (!this.hasModalBodyTarget || !this.hasDetailsModalTarget) {
      console.error("Modal targets not found. Cannot show details.");
      this.showError("Could not display details popup.");
      return;
    }
    
    this.modalBodyTarget.innerHTML = '<div class="modal-dialog modal-dialog-centered"><div class="modal-content bg-dark"><div class="modal-body text-center p-5"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading...</span></div></div></div></div>'; // Simplified loading state within modal structure
    const modalInstance = this.getModalInstance();
    if (!modalInstance || typeof modalInstance.show !== 'function') {
         console.error("Failed to get valid modal instance.");
         this.showError("Could not display details popup.");
         return;
    }
    modalInstance.show();

    try {
      const [detailsResponse, statusResponse] = await Promise.all([
         fetch(`/recommendations/${sourceId}?type=${contentType}`),
         fetch(`/watchlist/status?source_id=${sourceId}&content_type=${contentType}`)
      ]);
      
      if (!detailsResponse.ok) throw new Error(`Details fetch failed: ${detailsResponse.statusText}`);
      if (!statusResponse.ok) throw new Error(`Watchlist status fetch failed: ${statusResponse.statusText}`);
      
      const detailsData = await detailsResponse.json();
      const watchlistData = await statusResponse.json();

      const combinedData = {
          ...detailsData,
          source_id: sourceId,
          content_type: contentType, 
          inWatchlist: watchlistData.in_watchlist,
          watched: watchlistData.watched,
          rating: watchlistData.rating,
          // Store the watchlist item ID if available (needed for remove in modal)
          watchlistItemId: watchlistData.watchlist_item_id 
      };

      this.modalBodyTarget.innerHTML = this.generateModalContent(combinedData);
      this.updatePopupUI(this.modalBodyTarget, sourceId, combinedData.inWatchlist, combinedData.watched, combinedData.rating);

    } catch (error) {
      console.error('Error loading details popup:', error);
      // Display error inside the modal structure
      this.modalBodyTarget.innerHTML = `<div class="modal-dialog modal-dialog-centered"><div class="modal-content bg-dark"><div class="modal-body"><div class="alert alert-danger m-3">Failed to load details. ${error.message}</div></div></div></div>`;
    }
  }

  generateModalContent(data) {
    const country = (data.production_countries && data.production_countries.length > 0)
                    ? data.production_countries.map(c => c.name === 'United States of America' ? 'USA' : c.name).join(', ')
                    : (data.country || 'N/A'); 
    const releaseYear = (data.release_date || data.first_air_date || '').substring(0, 4) || 'N/A';
    const runtime = (data.runtime || (data.episode_run_time && data.episode_run_time[0]) || 'N/A');
    const tmdbRating = data.vote_average ? `${data.vote_average.toFixed(1)} (${(data.vote_count || 0).toLocaleString()} votes)` : 'N/A';
    const genres = (data.genres || []).map(g => typeof g === 'string' ? g : g.name).join(', ') || 'N/A';
    const creators = data.created_by ? data.created_by.map(c => c.name).join(', ') : 'N/A'; 
    const seasons = data.number_of_seasons || 'N/A';
    const episodes = data.number_of_episodes || 'N/A';
    const status = data.status || 'N/A';
    const directors = (data.credits?.crew || []).filter(c => c.job === 'Director').map(d => d.name).join(', ') || 'N/A';
    const cast = (data.credits?.cast || []).slice(0, 5).map(c => c.name).join(', ') || 'N/A';

    // Pass watchlistItemId to the remove button if available
    const addRemoveButton = `
        <button class="btn btn-primary watchlist-toggle mb-2 ${data.inWatchlist ? 'in-watchlist' : ''}"
                data-action="click->watchlist#toggleWatchlistItemInModal"
                data-watchlist-source-id-value="${data.source_id}"
                data-watchlist-content-type-value="${data.content_type}"
                ${data.watchlistItemId ? `data-watchlist-item-id-value="${data.watchlistItemId}"` : ''} 
                aria-label="${data.inWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist'}">
            <i class="fas fa-bookmark ${data.inWatchlist ? 'text-warning' : 'text-muted'}"></i>
            <span class="watchlist-text ms-1">${data.inWatchlist ? 'Remove' : 'Add'}</span>
        </button>`;

    const markWatchedButton = `
        <button class="btn btn-secondary watched-toggle mb-2 ${data.watched ? 'watched' : ''}"
                data-action="click->watchlist#toggleWatchedInModal"
                data-watchlist-source-id-value="${data.source_id}"
                data-watchlist-content-type-value="${data.content_type}"
                style="display: ${data.inWatchlist ? 'block' : 'none'};"
                 aria-label="${data.watched ? 'Mark as Unwatched' : 'Mark as Watched'}">
            <i class="fas ${data.watched ? 'fa-eye-slash' : 'fa-eye'}"></i>
            <span class="watched-text ms-1">${data.watched ? 'Unwatched' : 'Watched'}</span>
        </button>`;

    const rateButton = `
        <button class="btn btn-warning rate-item ${data.rating ? 'rated' : ''}"
                data-action="click->watchlist#rateItemInModal"
                data-watchlist-source-id-value="${data.source_id}"
                data-watchlist-content-type-value="${data.content_type}"
                data-watchlist-rating-value="${data.rating || 0}"
                style="display: ${data.inWatchlist && data.watched ? 'block' : 'none'};"
                 aria-label="${data.rating ? `Rated ${data.rating}/10. Click to change rating.` : 'Rate this item'}">
            <i class="fas fa-star"></i>
            <span class="rate-text ms-1">${data.rating ? `${data.rating}/10` : 'Rate'}</span>
        </button>`;

    return `
       <div class="modal-dialog modal-lg modal-dialog-centered modal-dialog-scrollable">
         <div class="modal-content bg-dark text-light">
            <div class="modal-header">
                <h5 class="modal-title text-warning">${data.title || data.name}</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <div class="row">
                    <div class="col-md-4 mb-3 mb-md-0">
                        <img src="${data.poster_path ? `https://image.tmdb.org/t/p/w500${data.poster_path}` : '/assets/placeholder.png'}" class="img-fluid rounded" alt="${data.title || data.name} poster">
                    </div>
                    <div class="col-md-8">
                         <div class="d-flex justify-content-between align-items-start mb-3">
                             <div> 
                                <p class="mb-1"><small><strong>${releaseYear} | ${country} | ${runtime} min</strong></small></p>
                                <p class="mb-1"><strong>TMDb Rating:</strong> ${tmdbRating}</p>
                                <p class="mb-1"><strong>Genres:</strong> ${genres}</p>
                             </div>
                             <div class="d-flex flex-column align-items-end"> 
                                 ${addRemoveButton}
                                 ${markWatchedButton}
                                 ${rateButton}
                             </div>
                         </div>
                        <p><strong>Description:</strong> ${data.overview || 'No description available.'}</p>
                        ${data.content_type === 'movie' ? `
                            <p class="mb-1"><strong>Director(s):</strong> ${directors}</p>
                            <p><strong>Cast:</strong> ${cast}</p>
                        ` : `
                            <p class="mb-1"><strong>Creator(s):</strong> ${creators}</p>
                            <p class="mb-1"><strong>Seasons:</strong> ${seasons} | <strong>Episodes:</strong> ${episodes} | <strong>Status:</strong> ${status}</p>
                            <p><strong>Cast:</strong> ${cast}</p>
                        `}
                    </div>
                </div>
                ${data.trailer_url ? `
                  <div class="mt-3">
                      <h5 class="text-warning">Trailer</h5>
                      <div class="embed-responsive embed-responsive-16by9">
                          <iframe class="embed-responsive-item" width="100%" height="315"
                                  src="${data.trailer_url.replace('watch?v=', 'embed/')}"
                                  allowfullscreen title="${data.title || data.name} trailer"></iframe>
                      </div>
                  </div>
                ` : ''}
            </div>
            <div class="modal-footer">
                 <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
            </div>
          </div>
        </div>
    `;
  }

  updatePopupUI(popupContainer, sourceId, inWatchlist, watched, rating) {
    const watchlistButton = popupContainer.querySelector(`.watchlist-toggle[data-watchlist-source-id-value="${sourceId}"]`);
    const watchedButton = popupContainer.querySelector(`.watched-toggle[data-watchlist-source-id-value="${sourceId}"]`);
    const rateButton = popupContainer.querySelector(`.rate-item[data-watchlist-source-id-value="${sourceId}"]`);

    if (watchlistButton) {
        watchlistButton.classList.toggle('in-watchlist', inWatchlist);
        const icon = watchlistButton.querySelector('i');
        const text = watchlistButton.querySelector('.watchlist-text');
        if (icon) icon.className = `fas fa-bookmark ${inWatchlist ? 'text-warning' : 'text-muted'}`;
        if (text) text.textContent = inWatchlist ? 'Remove' : 'Add';
        watchlistButton.setAttribute('aria-label', inWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist');
    }

    if (watchedButton) {
        watchedButton.classList.toggle('watched', watched);
        const icon = watchedButton.querySelector('i');
        const text = watchedButton.querySelector('.watched-text');
        if (icon) icon.className = `fas ${watched ? 'fa-eye-slash' : 'fa-eye'}`;
        if (text) text.textContent = watched ? 'Unwatched' : 'Watched';
        watchedButton.style.display = inWatchlist ? 'block' : 'none'; 
        watchedButton.setAttribute('aria-label', watched ? 'Mark as Unwatched' : 'Mark as Watched');
    }

    if (rateButton) {
        rateButton.classList.toggle('rated', !!rating);
        rateButton.dataset.watchlistRatingValue = rating || 0;
        const text = rateButton.querySelector('.rate-text');
        if (text) text.textContent = rating ? `${rating}/10` : 'Rate';
        rateButton.style.display = inWatchlist && watched ? 'block' : 'none';
         rateButton.setAttribute('aria-label', rating ? `Rated ${rating}/10. Click to change rating.` : 'Rate this item');
    }
}


  createRatingPopup(sourceId, contentType, title, currentRating = 0) {
    const modalId = `ratingModal-${sourceId}-${contentType}`;
    document.getElementById(modalId)?.remove();

    const modalHTML = `
      <div class="modal fade rating-popup-modal" id="${modalId}" tabindex="-1" aria-labelledby="${modalId}Label" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content bg-dark text-light">
            <div class="modal-header border-secondary">
              <h5 class="modal-title text-warning" id="${modalId}Label">Rate "${title}"</h5>
              <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body text-center">
               <div class="rating-stars mb-3" style="cursor: pointer; font-size: 2rem; color: lightgray;">
                ${[...Array(10).keys()].map(i => `
                  <span class="star rating-star-button" data-value="${i + 1}" style="margin: 0 3px;" role="button" aria-label="Rate ${i + 1} out of 10">★</span>
                `).join('')}
              </div>
              <p><small class="text-light">Click a star to set your rating.</small></p>
            </div>
            <div class="modal-footer border-secondary justify-content-center">
              <button type="button" class="btn btn-primary submit-rating" disabled>Submit Rating</button>
              <button type="button" class="btn btn-secondary cancel-rating" data-bs-dismiss="modal">Cancel</button>
            </div>
          </div>
        </div>
      </div>
    `;

    this.element.insertAdjacentHTML('beforeend', modalHTML);

    const modalElement = document.getElementById(modalId);
    const bootstrapModal = new window.bootstrap.Modal(modalElement);
    const stars = modalElement.querySelectorAll('.star');
    const submitButton = modalElement.querySelector('.submit-rating');
    let currentSelectedValue = currentRating;

    const updateStars = (value) => {
       stars.forEach(star => {
           star.style.color = parseInt(star.dataset.value) <= value ? 'gold' : 'lightgray';
           star.classList.toggle('selected', parseInt(star.dataset.value) <= value);
       });
       submitButton.disabled = value <= 0;
    };

    stars.forEach(star => {
        star.addEventListener('mouseover', () => {
            updateStars(parseInt(star.dataset.value));
        });
        star.addEventListener('mouseout', () => {
            updateStars(currentSelectedValue);
        });
        star.addEventListener('click', () => {
            currentSelectedValue = parseInt(star.dataset.value);
            updateStars(currentSelectedValue);
        });
    });

     updateStars(currentRating);

    return new Promise((resolve, reject) => {
        submitButton.addEventListener('click', () => {
            const rating = currentSelectedValue;
            if (rating > 0) {
                 bootstrapModal.hide(); 
                 resolve(rating);
            } else {
                 console.warn("No rating selected");
            }
        });

        modalElement.querySelector('.cancel-rating').addEventListener('click', () => {
           bootstrapModal.hide(); 
           reject('Rating cancelled'); 
        });
        
        modalElement.addEventListener('hidden.bs.modal', (event) => {
             if (!submitButton.disabled && currentSelectedValue > 0) {
                 // Already resolved by submit, do nothing
             } else {
                 reject('Rating cancelled via dismiss'); 
             }
             try {
                 this.element.focus({ preventScroll: true }); // Add preventScroll option
             } catch (e) { 
                 console.warn("Could not focus controller element after modal close:", e);
             }
             modalElement.remove();
        }, { once: true }); 

         bootstrapModal.show();
    });
}


  // --- Helper Functions ---

  getMetaValue(name) {
    const element = document.head.querySelector(`meta[name="${name}"]`);
    return element ? element.getAttribute("content") : null;
  }

  async fetchAPI(url, method = 'GET', body = null) {
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-CSRF-Token': this.getMetaValue("csrf-token"),
      'X-Requested-With': 'XMLHttpRequest'
    };

    const options = { method, headers };
    if (body && method !== 'GET') {
      options.body = JSON.stringify(body);
    }

    try {
      const response = await fetch(url, options);
      if (!response.ok) {
        let errorData;
        try {
           errorData = await response.json();
        } catch (e) {
        }
        const errorMessage = errorData?.message || errorData?.error || `HTTP error! status: ${response.status} ${response.statusText}`;
        throw new Error(errorMessage);
      }
       if (response.status === 204 || (response.headers.has('Content-Length') && response.headers.get('Content-Length') === '0')) {
           return { status: 'success', message: 'Operation successful (No Content)' }; 
       }
       // Check if content type is JSON before parsing
       const contentTypeHeader = response.headers.get('content-type');
       if (contentTypeHeader && contentTypeHeader.includes('application/json')) {
            return await response.json();
       } else {
            // Handle non-JSON responses if necessary, or assume success if status is OK
             console.warn(`Non-JSON response received for ${method} ${url}. Status: ${response.status}`);
             return { status: 'success', message: `Operation successful (Status: ${response.status})` }; 
       }
    } catch (error) {
      console.error(`Fetch API error (${method} ${url}):`, error);
      throw error;
    }
  }

    async fetchItemDataAndCreateCard(sourceId, contentType, watchlistItemId) {
        if (this.findCard(sourceId)) {
            console.log("Card already exists, skipping creation:", sourceId);
            return;
        }

        console.log("Fetching item data to create card:", sourceId, contentType);
        try {
             const itemDataResponse = await fetch(`/watchlist/${watchlistItemId}`, { headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' } });
              if (!itemDataResponse.ok) {
                   // Try fetching from the combined details endpoint as a fallback
                   console.warn(`Failed to fetch item data from /watchlist/${watchlistItemId}, trying recommendations endpoint...`);
                   const recommendationsResponse = await fetch(`/recommendations/${sourceId}?type=${contentType}`);
                   if (!recommendationsResponse.ok) throw new Error(`Details fetch failed: ${recommendationsResponse.statusText}`);
                   const detailsData = await recommendationsResponse.json();
                   // Need to manually construct the item data for the card
                   const itemData = {
                        id: watchlistItemId, // Use the ID we have
                        source_id: sourceId,
                        content_type: contentType,
                        watched: false, // Assume unwatched when added
                        rating: null,
                        title: detailsData.title || detailsData.name,
                        poster_url: detailsData.poster_path ? `https://image.tmdb.org/t/p/w500${detailsData.poster_path}` : null,
                        release_year: (detailsData.release_date || detailsData.first_air_date || '').substring(0, 4),
                        production_countries: detailsData.production_countries,
                        vote_average: detailsData.vote_average,
                        genres: (detailsData.genres || []).map(g => g.name)
                   };
                   this.createWatchlistCard(itemData);
              } else {
                    const itemData = await itemDataResponse.json();
                    this.createWatchlistCard(itemData);
              }
        } catch (error) {
            console.error("Error fetching item data for card creation:", error);
            this.showError("Failed to add item to the list visually.");
        }
    }

  createWatchlistCard(item) {
    if (!item || !item.id || !item.source_id || !item.content_type || !item.title) {
        console.error("Cannot create card: Missing essential item data.", item);
        return;
    }

    const targetList = item.watched ? this.watchedListTarget : this.unwatchedListTarget;
    if (!targetList) {
        console.error('Target list not found for item:', item);
        return;
    }

    if (this.findCard(item.source_id)) {
        console.warn("Card already exists, skipping creation:", item.source_id);
        return;
    }

    const newCard = document.createElement('div');
    newCard.className = 'card mb-2 watchlist-item';
    newCard.dataset.watchlistSourceIdValue = item.source_id;
    newCard.dataset.watchlistContentTypeValue = item.content_type;
    newCard.dataset.watchlistRatingValue = item.rating || 0;
    newCard.dataset.watchlistItemIdValue = item.id;
    newCard.dataset.action = "click->watchlist#showDetails";
    newCard.setAttribute('role', 'article');
    newCard.setAttribute('aria-labelledby', `title-${item.source_id}`);

    const countries = this.formatCountries(item.production_countries || [{ name: item.country }]);
    const year = item.release_year || 'N/A';
    const type = item.content_type ? item.content_type.charAt(0).toUpperCase() + item.content_type.slice(1) : 'Item';
    const tmdb = item.vote_average ? item.vote_average.toFixed(1) : 'N/A';
    const genres = Array.isArray(item.genres) ? item.genres.join(', ') : (item.genres || 'N/A');
    const poster = item.poster_url || '/assets/placeholder.png';

    newCard.innerHTML = `
        <div class="row g-1">
            <div class="col-4 col-lg-3">
                <img src="${poster}" class="card-img watchlist-poster" alt="${item.title} poster" loading="lazy">
            </div>
            <div class="col-8 col-lg-9">
                <div class="card-body position-relative p-2">
                    <h5 class="card-title mb-1" id="title-${item.source_id}">${item.title}</h5>
                    <div class="card-text-small text-muted mb-1">
                        ${[countries, year, type].filter(Boolean).join(" | ")}
                    </div>
                    <div class="card-text-small text-muted mb-1">
                        <strong>TMDb:</strong> ${tmdb}
                    </div>
                    <div class="card-text-small text-muted mb-2">
                        ${genres}
                    </div>
                    <div class="d-flex gap-1 mt-auto button-container justify-content-between">
                        <div class="d-flex gap-1 flex-grow-1 action-buttons">
                            <button class="btn btn-sm d-inline-flex align-items-center justify-content-center ${item.watched ? 'btn-warning mark-unwatched' : 'btn-success mark-watched'}"
                                    data-action="click->watchlist#toggleWatched"
                                    data-watchlist-source-id-value="${item.source_id}"
                                    data-watchlist-content-type-value="${item.content_type}"
                                    aria-label="${item.watched ? 'Mark as Unwatched' : 'Mark as Watched'}">
                                <i class="fas ${item.watched ? 'fa-eye-slash' : 'fa-eye'}"></i>
                                <span class="button-text d-none d-lg-inline ms-1">${item.watched ? 'Unwatched' : 'Watched'}</span>
                            </button>
                             <button class="btn btn-sm d-inline-flex align-items-center justify-content-center flex-grow-1 ${item.rating ? 'btn-warning rated' : 'btn-primary'} rate-item"
                                    data-action="click->watchlist#rateItem"
                                    data-watchlist-source-id-value="${item.source_id}"
                                    data-watchlist-content-type-value="${item.content_type}"
                                    data-watchlist-rating-value="${item.rating || 0}"
                                     aria-label="${item.rating ? `Rated ${item.rating}/10. Click to change rating.` : 'Rate this item'}">
                                <i class="fas fa-star me-1"></i>
                                <span class="button-text">${item.rating ? `${item.rating}/10` : 'Rate'}</span>
                            </button>
                        </div>
                        <button class="btn btn-sm btn-danger d-inline-flex align-items-center justify-content-center remove-item square-button"
                                data-action="click->watchlist#removeItem"
                                data-watchlist-source-id-value="${item.source_id}"
                                data-watchlist-content-type-value="${item.content_type}"
                                aria-label="Remove from Watchlist">
                            <i class="fas fa-trash-alt"></i>
                            <span class="button-text d-none d-lg-inline ms-1 d-none">Remove</span> 
                        </button>
                    </div>
                </div>
            </div>
        </div>
         <div class="drag-handle position-absolute top-0 start-0 p-2" style="cursor: grab;">
           <i class="fas fa-grip-vertical text-muted"></i>
        </div>
    `;

    targetList.insertBefore(newCard, targetList.firstChild);
     console.log("Created and added card to UI:", item.source_id);

     this.refreshSortable(targetList);
}



  formatCountries(countries) {
    if (!countries) return '';
    if (typeof countries === 'string') {
        return countries.replace('United States of America', 'USA');
    }
    if (!Array.isArray(countries) || countries.length === 0) return '';

    const names = countries.map(c => (c && c.name) ? c.name.replace('United States of America', 'USA') : '').filter(Boolean);

    switch (names.length) {
        case 0: return '';
        case 1: return names[0];
        case 2: return names.join(' & ');
        default: return `${names[0]}, ${names[1]} & ${names.length - 2} more`;
    }
}


  showError(message) {
      alert(`Error: ${message}`);
  }

    getModalInstance() {
        if (!this.hasDetailsModalTarget) {
             console.error("Details modal target not found!");
             return null; // Return null if target missing
        }
        // Use getOrCreateInstance to handle potential race conditions or multiple calls
        return window.bootstrap.Modal.getOrCreateInstance(this.detailsModalTarget);
    }

  dispatchWatchlistChangeEvent() {
    const event = new CustomEvent('watchlist:change', { bubbles: true });
    this.element.dispatchEvent(event);
    console.log("Dispatched watchlist:change event");
  }
}
