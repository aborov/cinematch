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
    // Add event listener to the document for delegated clicks
    this.boundHandleDelegatedClick = this.handleDelegatedClick.bind(this); // Store bound function
    document.addEventListener('click', this.boundHandleDelegatedClick);
  }

  disconnect() {
    if (this.unwatchedSortable) {
      this.unwatchedSortable.destroy();
    }
    if (this.watchedSortable) {
      this.watchedSortable.destroy();
    }
    // Remove event listener from the document on disconnect
    if (this.boundHandleDelegatedClick) {
      document.removeEventListener('click', this.boundHandleDelegatedClick);
    }
  }

  // --- New Delegated Click Handler ---
  handleDelegatedClick(event) {
    // Check for clicks on watchlist cards to open details popup
    const card = event.target.closest('.watchlist-item[data-watchlist-source-id-value][data-watchlist-content-type-value]');
    if (card && !event.target.closest('button, a, .drag-handle')) {
      event.preventDefault(); // Prevent default if it's a non-interactive part of the card
      const sourceId = card.dataset.watchlistSourceIdValue;
      const contentType = card.dataset.watchlistContentTypeValue;
      console.log(`Card click detected. Source ID: ${sourceId}, Content Type: ${contentType}`);
      this.showDetailsPopup(sourceId, contentType); // Call popup directly
      return;
    }
    
    // Check for clicks on actionable elements (buttons OR stars) INSIDE the modal
    // Look for any element within the modal body that has the correct data-action
    const modalActionElement = event.target.closest('#detailsModal .modal-body [data-action^="click->watchlist#"]');
    if (modalActionElement) {
      event.preventDefault();
      event.stopPropagation(); // Stop propagation for modal actions
      
      const actionString = modalActionElement.dataset.action; // e.g., "click->watchlist#toggleWatchedInModal" or "click->watchlist#handleStarClickInModal"
      const actionParts = actionString.split('->');
      
      if (actionParts.length === 2) {
        const controllerAndMethod = actionParts[1].split('#'); // ["watchlist", "methodName"]
        if (controllerAndMethod.length === 2) {
          const controllerName = controllerAndMethod[0];
          const methodName = controllerAndMethod[1];
          
          if (controllerName === 'watchlist' && typeof this[methodName] === 'function') {
            console.log(`Delegated click: Routing event to this.${methodName} for element:`, modalActionElement);
            // Call method with correct context and pass the original event
            this[methodName].call(this, event); 
      } else {
            console.warn(`Delegated click: Method ${methodName} not found on controller 'watchlist' for action ${actionString}`);
          }
        } else {
           console.warn(`Delegated click: Malformed controller/method part in action: ${actionString}`);
        }
      } else {
        console.warn(`Delegated click: Malformed action string: ${actionString}`);
      }
      return; // Stop processing after handling modal action
    }
    
    // Check for clicks on direct action buttons on cards (outside modal)
    const cardButton = event.target.closest('.watchlist-item button[data-action^="click->watchlist#"]');
    if (cardButton) {
         event.preventDefault();
         event.stopPropagation(); // Also stop propagation for card buttons
         
         const action = cardButton.dataset.action;
         const [controller, method] = action.split('->');
         
         if (controller === 'watchlist' && typeof this[method] === 'function') {
            console.log(`Card button click: Routing event to this.${method}`);
            this[method].call(this, event); // Call method with correct context
         } else {
            console.warn(`Card button click: Method ${method} not found on controller for action ${action}`);
         }
         return; // Stop processing after handling card button
    }
    
    // Allow other clicks (like drag handle) to proceed normally
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
    const contentType = card?.dataset.watchlistContentTypeValue;
    
    if (!watchlistItemId) {
      console.error("Could not find watchlist item ID for removal.");
      this.showError("Could not remove item. ID missing.");
      return;
    }

    if (confirm('Are you sure you want to remove this item from your watchlist?')) {
        this.handleWatchlistAction('removeItem', watchlistItemId, contentType, button); 
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

  toggleWatchlistItemInModal(event) {
    console.log("toggleWatchlistItemInModal triggered", event.target); // Log event.target
    event.preventDefault();
    event.stopPropagation();
    // Use event.target.closest to find the button that triggered the action
    const button = event.target.closest('button[data-action="click->watchlist#toggleWatchlistItemInModal"]');
    if (!button) {
      console.error("Could not find toggleWatchlistItemInModal button from event target:", event.target);
      return; 
    }
    const sourceId = button.dataset.watchlistSourceIdValue;
    const contentType = button.dataset.watchlistContentTypeValue;
    const isInWatchlist = button.classList.contains('in-watchlist');
    
    // *** DIAGNOSTIC LOG ***
    console.log("Checking button dataset for watchlistItemIdValue:", button.dataset.watchlistItemIdValue); 
    
    const identifier = isInWatchlist ? (button.dataset.watchlistItemIdValue || sourceId) : sourceId;
    const modalBody = button.closest('.modal-body');

    this.handleWatchlistAction(isInWatchlist ? 'removeItem' : 'addItem', identifier, contentType, button)
        .then(data => {
            if (data.status === 'success' && modalBody) {
                const isNowInWatchlist = !isInWatchlist;
                const watchedStatus = data.watched !== undefined ? data.watched : false;
                const rating = data.rating !== undefined ? data.rating : null;

                 this.updatePopupUI(modalBody, sourceId, isNowInWatchlist, watchedStatus, rating, data.item?.id);
                 
                 this.updateSectionCounts(); 
            }
        });
  }

    toggleWatchedInModal(event) {
        console.log("toggleWatchedInModal triggered", event.target); // Log event.target
        event.preventDefault();
        event.stopPropagation();
        // Use event.target.closest to find the button that triggered the action
        const button = event.target.closest('button[data-action="click->watchlist#toggleWatchedInModal"]');
         if (!button) {
          console.error("Could not find toggleWatchedInModal button from event target:", event.target);
          return; 
        }
        const sourceId = button.dataset.watchlistSourceIdValue;
        const contentType = button.dataset.watchlistContentTypeValue;
        const modalBody = button.closest('.modal-body');
        
        this.handleWatchlistAction('toggleWatched', sourceId, contentType, button)
            .then(data => {
                if (data.status === 'success' && modalBody) {
                    this.updatePopupUI(modalBody, sourceId, true, data.watched, data.rating, data.item?.id);
                    
                    this.updateSectionCounts(); 
                }
            });
    }

    rateItemInModal(event) {
        console.log("rateItemInModal triggered", event.target); // Log event.target
        event.preventDefault();
        event.stopPropagation();
        // Use event.target.closest to find the button that triggered the action
        const button = event.target.closest('button[data-action="click->watchlist#rateItemInModal"]');
         if (!button) {
           console.error("Could not find rateItemInModal button from event target:", event.target);
           return; 
         }
        
        // *** CHANGE: Instead of calling createRatingPopup, show the inline interface ***
        this.showRatingInterfaceInModal(button); 
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
            // Use the standard REST destroy path for watchlist item ID
            url = `/watchlist/${identifier}`; 
            method = 'DELETE';
            body = contentType ? { content_type: contentType } : undefined;
            console.log(`Attempting to remove item. Identifier: ${identifier}, Content Type: ${contentType}, URL: ${url}`);
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
        let sourceIdForUI;
        if (action === 'removeItem') {
            sourceIdForUI = initiatingElement?.closest('[data-watchlist-source-id-value]')?.dataset.watchlistSourceIdValue;
        } else {
            sourceIdForUI = identifier;
        }
        
        const data = await this.fetchAPI(url, method, body);
        
        if (data.status === 'success') {
            console.log(`Action ${action} successful for identifier ${identifier}`);

            // Use the item ID returned from the 'addItem' action
            const newItemId = action === 'addItem' ? data.item?.id : null; 
            
            let isNowInWatchlist = action !== 'removeItem';
            let isNowWatched = false;
            let rating = null;

            if (data.watched !== undefined) isNowWatched = data.watched;
            if (data.rating !== undefined) rating = data.rating;
            if (action === 'removeItem') isNowInWatchlist = false;
            
            if (action === 'removeItem') {
                 if (sourceIdForUI) {
                     this.removeCardFromUI(sourceIdForUI);
                 }
            } else if (action === 'addItem') {
                 // *** CHANGE: Use the returned item data directly ***
                 if (data.item) {
                    this.createWatchlistCard(data.item); 
                 } else {
                    console.error("Item data missing in addItem response, cannot create card.");
                     // Fallback or error handling needed? Could try fetchItemDataAndCreateCard if really necessary
                     // await this.fetchItemDataAndCreateCard(sourceIdForUI, contentType, newItemId); 
                 }
                 // Don't call updateWatchlistCardUI here, createWatchlistCard handles the initial state
                 // this.updateWatchlistCardUI(sourceIdForUI, true, false, null); 
            } else if (action === 'toggleWatched') {
                 this.updateWatchlistCardUI(sourceIdForUI, true, data.watched, data.rating);
            }

            const modalBody = document.querySelector('#detailsModal .modal-body');
            if (modalBody && modalBody.querySelector(`[data-watchlist-source-id-value="${sourceIdForUI}"]`)) {
                 // *** Pass newItemId to updatePopupUI so it can add the data attribute ***
                 this.updatePopupUI(modalBody, sourceIdForUI, isNowInWatchlist, isNowWatched, rating, newItemId); 
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

    // Update button container classes
    const buttonsContainer = card.querySelector('.button-container');
    if (buttonsContainer) {
        buttonsContainer.className = 'd-flex gap-1 mt-auto button-container justify-content-between';
    }

    // Update watched/unwatched button - set entire HTML content at once
    const watchButton = card.querySelector('.mark-watched, .mark-unwatched');
    if (watchButton) {
        watchButton.className = `btn btn-sm d-inline-flex align-items-center justify-content-center ${watched ? 'btn-warning mark-unwatched' : 'btn-success mark-watched'}`;
        watchButton.innerHTML = `
            <i class="fas ${watched ? 'fa-eye-slash' : 'fa-eye'}"></i>
            <span class="button-text d-none d-lg-inline ms-1">${watched ? 'Unwatched' : 'Watched'}</span>
        `;
        watchButton.setAttribute('aria-label', watched ? 'Mark as Unwatched' : 'Mark as Watched');
    }

    // Update rate button - set entire HTML content at once
    const rateButton = card.querySelector('.rate-item');
    if (rateButton) {
        rateButton.className = `btn btn-sm d-inline-flex align-items-center justify-content-center flex-grow-1 ${rating ? 'btn-warning rate-item rated' : 'btn-primary rate-item'}`;
        rateButton.innerHTML = `
            <i class="fas fa-star me-1"></i>
            <span class="button-text">${rating ? `${rating}/10` : 'Rate'}</span>
        `;
        rateButton.dataset.watchlistRatingValue = rating || 0;
        rateButton.setAttribute('aria-label', rating ? `Rated ${rating}/10. Click to change rating.` : 'Rate this item');
    }

    // Move card to appropriate section
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
       // Cleaned up logging
       const selector = `.watchlist-item[data-watchlist-source-id-value="${sourceId}"]`;
       const card = this.element.querySelector(selector);
       if (!card) {
         console.warn(`Card find failed! Selector: ${selector} within:`, this.element);
       }
       return card;
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
    // Always find modal elements by ID since they are out of controller scope
    const modalElement = document.querySelector('#detailsModal');
    if (!modalElement) {
      console.error("Details modal element (#detailsModal) not found in DOM");
      this.showError("Could not display details popup (Modal missing).");
      return;
    }

    const modalBody = modalElement.querySelector('.modal-body');
    if (!modalBody) {
      console.error("Modal body element (.modal-body) not found in DOM");
      this.showError("Could not display details popup (Body missing).");
      return;
    }

    // Get or create Bootstrap modal instance
    const modalInstance = bootstrap.Modal.getOrCreateInstance(modalElement);
    if (!modalInstance) {
      console.error("Failed to get Bootstrap modal instance.");
      this.showError("Could not display details popup (Instance fail).");
      return;
    }

    // Show the modal
    modalInstance.show();

    // Show loading state directly in the found modal body
    modalBody.innerHTML = '<div class="text-center p-5"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading...</span></div></div>';

    try {
      // Get the existing data from the card, including the poster URL
      const card = this.findCard(sourceId);
      const cardData = {
        poster_url: card?.querySelector('img')?.src,
        title: card?.querySelector('.card-title')?.textContent?.trim(),
        rating: card?.dataset?.watchlistRatingValue
      };

      // Fetch both details and watchlist status
      const [detailsResponse, statusResponse] = await Promise.all([
        fetch(`/recommendations/${sourceId}?type=${contentType}`),
        fetch(`/watchlist/status?source_id=${sourceId}&content_type=${contentType}`)
      ]);
      
      if (!detailsResponse.ok) throw new Error(`Details fetch failed: ${detailsResponse.statusText}`);
      if (!statusResponse.ok) throw new Error(`Watchlist status fetch failed: ${statusResponse.statusText}`);
      
      const detailsData = await detailsResponse.json();
      const watchlistData = await statusResponse.json();

      // *** DIAGNOSTIC LOG ***
      console.log("Watchlist status data received:", watchlistData);
      console.log("Check for watchlistItemId:", watchlistData.watchlist_item_id);

      // Combine the data, prioritizing existing card data for certain fields
      const combinedData = {
        ...detailsData,
        source_id: sourceId,
        content_type: contentType,
        poster_url: cardData.poster_url || detailsData.poster_url || (detailsData.poster_path ? `/proxy_image?url=${encodeURIComponent(`https://image.tmdb.org/t/p/w500${detailsData.poster_path}`)}` : '/assets/placeholder.png'),
        title: cardData.title || detailsData.title || detailsData.name,
        inWatchlist: watchlistData.in_watchlist,
        watched: watchlistData.watched,
        rating: watchlistData.rating || cardData.rating,
        watchlistItemId: watchlistData.watchlist_item_id,
        // Ensure trailer_url is passed through if available in detailsData
        trailer_url: detailsData.trailer_url 
      };

      // Generate content and inject it into the found modal body
      modalBody.innerHTML = this.generateModalContent(combinedData);

      // DO NOT set data-controller here anymore
      // modalBody.setAttribute('data-controller', 'watchlist');

    } catch (error) {
      console.error('Error loading details popup:', error);
      modalBody.innerHTML = `<div class="alert alert-danger m-3">Failed to load details. ${error.message}</div>`;
    }
  }

  // Update the generateModalContent method to ensure proper data attributes AND add inline rating UI
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

    // Handle poster URL - use poster_url if available (from watchlist), otherwise construct TMDb URL
    const posterUrl = data.poster_url || (data.poster_path ? `/proxy_image?url=${encodeURIComponent(`https://image.tmdb.org/t/p/w500${data.poster_path}`)}` : '/assets/placeholder.png');
    const title = data.title || data.name; // Use consistent title variable

    return `
      <div class="row">
        <div class="col-md-4 mb-3 mb-md-0">
          <img src="${posterUrl}" class="img-fluid rounded" alt="${title} poster" role="img">
        </div>
        <div class="col-md-8">
          <div class="d-flex justify-content-between align-items-start mb-3">
            <h2 class="text-warning mb-2">${title}</h2>
            ${data.match_score ? `<span class="badge badge-large bg-warning" role="status" aria-label="Match score">${data.match_score}%</span>` : ''}
          </div>
          <div class="d-flex justify-content-between">
            <div>
              <p class="mb-1 small"><strong>Runtime:</strong> ${runtime} min</p>
              <p class="mb-1 small"><strong>Release Year:</strong> ${releaseYear}</p>
              <p class="mb-1 small"><strong>Country:</strong> ${country}</p>
              <p class="mb-1 small"><strong>TMDb Rating:</strong> ${tmdbRating}</p>
            </div>
            <div class="d-flex flex-column align-items-end">
              <button class="btn btn-primary btn-sm watchlist-toggle mb-2 ${data.inWatchlist ? 'in-watchlist' : ''}"
                      data-action="click->watchlist#toggleWatchlistItemInModal"
                      data-watchlist-source-id-value="${data.source_id}"
                      data-watchlist-content-type-value="${data.content_type}"
                      ${data.watchlistItemId ? `data-watchlist-item-id-value="${data.watchlistItemId}"` : ''}
                      aria-label="${data.inWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist'}">
                <i class="fas fa-bookmark ${data.inWatchlist ? 'text-warning' : 'text-muted'}"></i>
                <span class="watchlist-text ms-1">${data.inWatchlist ? 'Remove' : 'Add'}</span>
              </button>
              
              <button class="btn btn-secondary btn-sm watched-toggle mb-2 ${data.watched ? 'watched' : ''}"
                      data-action="click->watchlist#toggleWatchedInModal"
                      data-watchlist-source-id-value="${data.source_id}"
                      data-watchlist-content-type-value="${data.content_type}"
                      style="display: ${data.inWatchlist ? 'block' : 'none'};"
                      aria-label="${data.watched ? 'Mark as Unwatched' : 'Mark as Watched'}">
                <i class="fas ${data.watched ? 'fa-eye-slash' : 'fa-eye'}"></i>
                <span class="watched-text ms-1">${data.watched ? 'Unwatched' : 'Watched'}</span>
              </button>

              <button class="btn btn-warning btn-sm rate-item ${data.rating ? 'rated' : ''}"
                      data-action="click->watchlist#rateItemInModal"
                      data-watchlist-source-id-value="${data.source_id}"
                      data-watchlist-content-type-value="${data.content_type}"
                      data-watchlist-rating-value="${data.rating || 0}"
                      data-title="${title.replace(/"/g, '&quot;')}" {/* Store title safely */}
                      style="display: ${data.inWatchlist && data.watched ? 'block' : 'none'};"
                      aria-label="${data.rating ? `Rated ${data.rating}/10. Click to change rating.` : 'Rate this item'}">
                <i class="fas fa-star"></i>
                <span class="rate-text ms-1">${data.rating ? `${data.rating}/10` : 'Rate'}</span>
              </button>
              
              <div class="rating-interface mt-2 p-2 border rounded bg-dark" 
                   style="display: none;" 
                   data-watchlist-source-id-value="${data.source_id}" 
                   data-watchlist-content-type-value="${data.content_type}">
                <p class="small mb-1 text-center text-light">Rate "${title}":</p>
                <div class="rating-stars mb-2 text-center" style="cursor: pointer; font-size: 1.5rem; color: lightgray;">
                  ${[...Array(10).keys()].map(i => `
                    <span class="star rating-star-button" 
                          data-action="click->watchlist#handleStarClickInModal" 
                          data-value="${i + 1}" 
                          style="margin: 0 2px;" 
                          role="button" 
                          aria-label="Rate ${i + 1} out of 10">★</span>
                  `).join('')}
                </div>
                <div class="d-flex justify-content-center gap-2">
                  <button type="button" class="btn btn-primary btn-sm submit-rating" 
                          data-action="click->watchlist#submitRatingFromModal" 
                          disabled>Submit</button>
                  <button type="button" class="btn btn-secondary btn-sm cancel-rating" 
                          data-action="click->watchlist#cancelRatingInModal">Cancel</button>
                </div>
              </div>
              
            </div>
          </div>
          <div class="mt-3">
            <p class="mb-1 small"><strong>Genres:</strong> ${genres}</p>
            ${creators !== 'N/A' ? `<p class="mb-1 small"><strong>Creators:</strong> ${creators}</p>` : ''}
            ${seasons !== 'N/A' ? `<p class="mb-1 small"><strong>Seasons:</strong> ${seasons}</p>` : ''}
            ${episodes !== 'N/A' ? `<p class="mb-1 small"><strong>Episodes:</strong> ${episodes}</p>` : ''}
            ${status !== 'N/A' ? `<p class="mb-1 small"><strong>Status:</strong> ${status}</p>` : ''}
            ${directors !== 'N/A' ? `<p class="mb-1 small"><strong>Directors:</strong> ${directors}</p>` : ''}
            ${cast !== 'N/A' ? `<p class="mb-1 small"><strong>Cast:</strong> ${cast}</p>` : ''}
            <p class="mb-1 small"><strong>Description:</strong> ${data.overview || 'No description available.'}</p>
          </div>
        </div>
      </div>
      <div class="embed-responsive embed-responsive-16by9 mt-3">
        ${data.trailer_url ? `
          <iframe class="embed-responsive-item" width="100%" height="315" src="${data.trailer_url.replace('watch?v=', 'embed/')}" allowfullscreen title="${title} trailer"></iframe>
        ` : '<p class="text-center text-muted mt-3 small">Trailer not available.</p>'}
      </div>
    `;
  }

  updatePopupUI(popupContainer, sourceId, inWatchlist, watched, rating, newItemId = null) {
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
        
        // *** Add or remove the watchlist-item-id-value attribute ***
        if (inWatchlist && newItemId) {
            watchlistButton.dataset.watchlistItemIdValue = newItemId;
            console.log("Added watchlistItemIdValue to modal button:", newItemId);
        } else if (!inWatchlist) {
            delete watchlistButton.dataset.watchlistItemIdValue;
             console.log("Removed watchlistItemIdValue from modal button");
        }
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


  // --- ADD Inline Rating Logic (Modal) ---

  showRatingInterfaceInModal(rateButton) {
    const ratingContainer = rateButton.closest('.d-flex.flex-column').querySelector('.rating-interface');
    if (!ratingContainer) {
        console.error("Could not find inline rating container in modal");
        return;
    }

    const currentRating = parseInt(rateButton.dataset.watchlistRatingValue) || 0;
    ratingContainer.dataset.currentRating = currentRating; // Store original rating for cancel

    const stars = ratingContainer.querySelectorAll('.star');
    this.highlightStars(stars, currentRating); // Highlight based on current rating

    // Add hover effects to stars in the modal context
    stars.forEach(star => {
        star.addEventListener('mouseover', () => {
        const hoverValue = parseInt(star.dataset.value);
        this.highlightStars(stars, hoverValue);
        });
        star.addEventListener('mouseout', () => {
         // On mouseout, highlight based on the currently *selected* value in the interface
         const selectedValue = ratingContainer.querySelectorAll('.star.selected').length;
         this.highlightStars(stars, selectedValue);
      });
       // click is handled by handleStarClickInModal via data-action
    });
    
    // Reset selection state and submit button
    stars.forEach(s => s.classList.remove('selected'));
    if(currentRating > 0) {
        stars.forEach(s => { if(parseInt(s.dataset.value) <= currentRating) s.classList.add('selected') });
    }
    ratingContainer.querySelector('.submit-rating').disabled = currentRating <= 0;


    // Show the interface and hide the original button
    ratingContainer.style.display = 'block';
    rateButton.style.display = 'none';
  }

  handleStarClickInModal(event) {
    console.log("handleStarClickInModal triggered"); // Log: Check if handler is called
    const clickedStar = event.target.closest('.star');
    if (!clickedStar) {
        console.error("handleStarClickInModal: Could not find clicked star from event target:", event.target);
        return;
    }
    console.log("handleStarClickInModal: Found clicked star:", clickedStar);
    
    const ratingContainer = clickedStar.closest('.rating-interface');
    if (!ratingContainer) {
        console.error("handleStarClickInModal: Could not find rating container.");
        return;
    }
    console.log("handleStarClickInModal: Found rating container:", ratingContainer);
    
    const stars = ratingContainer.querySelectorAll('.star');
    const value = parseInt(clickedStar.dataset.value);

    // Update selection state
    stars.forEach(s => {
        s.classList.toggle('selected', parseInt(s.dataset.value) <= value);
    });

    // Highlight stars visually based on new selection
    this.highlightStars(stars, value);

    // Enable submit button
    ratingContainer.querySelector('.submit-rating').disabled = false;
  }

  async submitRatingFromModal(event) {
    const submitButton = event.target.closest('.submit-rating');
    if (!submitButton) return;
    
    const ratingContainer = submitButton.closest('.rating-interface');
    if (!ratingContainer) return;

    const rating = ratingContainer.querySelectorAll('.star.selected').length;
    const sourceId = ratingContainer.dataset.watchlistSourceIdValue;
    const contentType = ratingContainer.dataset.watchlistContentTypeValue;

    if (rating > 0 && sourceId && contentType) {
        console.log(`Submitting modal rating ${rating} for ${sourceId} (${contentType})`);
        
        try {
             // Use the existing submitRating logic which calls the API
            const data = await this.submitRating(sourceId, contentType, rating);

             if (data.status === 'success') {
                 // Update the main UI (popup and potentially card)
                 this.updatePopupUI(ratingContainer.closest('.modal-body'), sourceId, true, true, data.rating, data.item?.id);
                 this.updateWatchlistCardUI(sourceId, true, true, data.rating); // Update card as well
                 this.updateSectionCounts();
                 this.dispatchWatchlistChangeEvent();
                 
                 // Hide interface and show original button
                 ratingContainer.style.display = 'none';
                 const rateButton = ratingContainer.closest('.d-flex.flex-column').querySelector('.rate-item');
                 if (rateButton) rateButton.style.display = 'block'; 
             } else {
                 throw new Error(data.message || "Rating submission failed");
             }
        } catch (error) {
            console.error('Error submitting rating from modal:', error);
            this.showError('Failed to save rating.');
            // Optionally re-show interface or button on error?
        }
    } else {
        console.warn("Cannot submit rating - missing data or rating is zero.");
    }
  }

  cancelRatingInModal(event) {
    const cancelButton = event.target.closest('.cancel-rating');
    if (!cancelButton) return;
    
    const ratingContainer = cancelButton.closest('.rating-interface');
    if (!ratingContainer) return;

    // Hide the interface
    ratingContainer.style.display = 'none';

    // Show the original rate button again
    const rateButton = ratingContainer.closest('.d-flex.flex-column').querySelector('.rate-item');
    if (rateButton) {
      rateButton.style.display = 'block';
    }
  }

  // Helper function to highlight stars (can be used by both inline and potentially popup later)
  highlightStars(stars, value) {
    stars.forEach(star => {
      star.style.color = parseInt(star.dataset.value) <= value ? 'gold' : 'lightgray';
    });
  }

  // --- Helper Functions ---

  getMetaValue(name) {
    const element = document.head.querySelector(`meta[name="${name}"]`);
    return element ? element.getAttribute("content") : null;
  }

  async fetchAPI(url, method, body) {
    const token = this.getMetaValue("csrf-token");
    const options = {
      method: method,
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      credentials: "same-origin"
    };

    // Only add body for certain methods
    if (body && (method === 'POST' || method === 'PUT' || method === 'PATCH' || method === 'DELETE')) {
      options.body = JSON.stringify(body);
    }

    // For DELETE with query parameters, append them to the URL
    if (method === 'DELETE' && body && Object.keys(body).length > 0 && !options.body) {
      const params = new URLSearchParams();
      Object.entries(body).forEach(([key, value]) => {
        params.append(key, value);
      });
      url = `${url}?${params.toString()}`;
    }

    try {
      const response = await fetch(url, options);
      
      if (!response.ok) {
        const errorText = await response.text();
        console.error(`API error (${response.status}): ${errorText}`);
        throw new Error(`API error: ${response.statusText} (${response.status})`);
      }
      
      return await response.json();
    } catch (error) {
      console.error("API fetch error:", error);
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
                <img src="${poster}" 
                     class="card-img watchlist-poster" 
                     alt="${item.title} poster" 
                     loading="lazy"
                     onerror="this.onerror=null; this.src='/assets/placeholder.png';">
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

  // --- ADD BACK createRatingPopup method for card rating ---
  createRatingPopup(sourceId, contentType, title, currentRating = 0) {
    const modalId = `ratingModal-${sourceId}-${contentType}`;
    // Clean up any existing modals with the same ID
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

    // Insert the modal HTML into the DOM, potentially outside the controller's element if needed
    document.body.insertAdjacentHTML('beforeend', modalHTML);

    const modalElement = document.getElementById(modalId);
    if (!modalElement) { 
        console.error("Failed to find rating popup modal element after insertion:", modalId);
        return Promise.reject("Failed to create rating popup UI");
    }

    // Ensure Bootstrap's Modal is available
    if (typeof window.bootstrap === 'undefined' || typeof window.bootstrap.Modal === 'undefined') {
      console.error("Bootstrap Modal component not found.");
      return Promise.reject("Bootstrap Modal not available");
    }
    
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
        
        const handleSubmit = () => {
             const rating = currentSelectedValue;
             if (rating > 0) {
                  // We only resolve the rating value, hiding happens in hidden.bs.modal
                  resolve(rating);
             } else {
                  console.warn("No rating selected");
                  reject('No rating selected'); // Reject if no rating
             }
             bootstrapModal.hide(); // Hide modal on submit attempt
        };

        const handleCancel = () => {
           reject('Rating cancelled'); 
           // Hiding is handled by data-bs-dismiss or manually if needed
           bootstrapModal.hide(); 
        };

        submitButton.addEventListener('click', handleSubmit);
        modalElement.querySelector('.cancel-rating').addEventListener('click', handleCancel);
        
        // Handle modal close events (backdrop click, ESC key, explicit close button)
        modalElement.addEventListener('hidden.bs.modal', (event) => {
            // Check if the promise has already been resolved (by submit)
             if (submitButton.disabled || currentSelectedValue === 0) { 
                 // If submit wasn't clicked successfully or no rating was chosen, reject
                 reject('Rating cancelled via dismiss'); 
             }
             // Cleanup: Remove the modal from the DOM after it's hidden
             modalElement.remove(); 
             // Try to return focus to the main controller element
             try {
                 this.element.focus({ preventScroll: true });
             } catch (e) { 
                 console.warn("Could not focus controller element after modal close:", e);
             }
        }, { once: true }); 

         bootstrapModal.show();
    });
  }
}
