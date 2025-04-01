import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="navbar-watchlist-updater"
export default class extends Controller {
  static targets = [ "count", "dropdown" ]

  connect() {
    console.log("Navbar watchlist updater connected.");
    // Bind the update method to maintain the controller context ('this')
    this.boundUpdate = this.update.bind(this);
    window.addEventListener('watchlist:change', this.boundUpdate);
    // Initial update on connect might be redundant if server renders correctly
    // this.update();
  }

  disconnect() {
    console.log("Navbar watchlist updater disconnected.");
    window.removeEventListener('watchlist:change', this.boundUpdate);
  }

  async update() {
    console.log("Received watchlist:change event, updating navbar...");
    try {
        const [countResponse, recentResponse] = await Promise.all([
            fetch('/watchlist/unwatched_count', { headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' } }),
            fetch('/watchlist/recent', { headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' } })
        ]);

        if (!countResponse.ok) throw new Error(`Unwatched count fetch failed: ${countResponse.statusText}`);
        if (!recentResponse.ok) throw new Error(`Recent items fetch failed: ${recentResponse.statusText}`);

        const countData = await countResponse.json();
        const recentData = await recentResponse.json();

        if (this.hasCountTarget) {
            const badge = this.countTarget;
            badge.textContent = countData.count;
            badge.style.display = countData.count > 0 ? 'inline-block' : 'none';
        } else {
            console.warn("Navbar updater: Count target not found.");
        }

        if (this.hasDropdownTarget) {
            const dropdown = this.dropdownTarget;
             if (recentData.items && recentData.items.length > 0) {
                  dropdown.innerHTML = recentData.items.map(item => `
                      <li>
                        <a class="dropdown-item d-flex align-items-center" href="/watchlist" title="${item.title}">
                          <img src="${item.poster_url || '/assets/placeholder.png'}" alt="" class="me-2" style="width: 30px; height: 45px; object-fit: cover; flex-shrink: 0;">
                          <span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">
                            ${item.title} 
                            <small class="text-muted">(${item.release_year || 'N/A'})</small>
                          </span>
                        </a>
                      </li>
                  `).join('') + `
                      <li><hr class="dropdown-divider"></li>
                      <li><a class="dropdown-item text-primary text-center fw-bold" href="/watchlist">View All (${countData.count})</a></li>
                  `;
              } else {
                  dropdown.innerHTML = ` 
                    <li><span class="dropdown-item disabled">Watchlist is empty</span></li>
                    <li><hr class="dropdown-divider"></li>
                    <li><a class="dropdown-item text-primary text-center" href="/watchlist">View Watchlist</a></li>
                   `; 
              }
        } else {
            console.warn("Navbar updater: Dropdown target not found.");
        }
        console.log("Navbar watchlist updated via event.");
    } catch (error) {
        console.error('Error updating watchlist navbar via event:', error);
    }
  }
} 
