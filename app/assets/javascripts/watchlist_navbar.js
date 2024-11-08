function updateWatchlistNavbar() {
  Promise.all([
    fetch('/watchlist_items/unwatched_count').then(response => {
      if (!response.ok) throw new Error('Count fetch failed');
      return response.json();
    }),
    fetch('/watchlist_items/recent').then(response => {
      if (!response.ok) throw new Error('Recent fetch failed');
      return response.json();
    })
  ])
    .then(([countData, recentData]) => {
      const badge = document.querySelector('#watchlist-count');
      if (badge) {
        badge.textContent = countData.count;
        badge.style.display = countData.count > 0 ? 'inline-block' : 'none';
      }

      const dropdown = document.querySelector('#watchlist-dropdown');
      if (dropdown) {
        if (recentData.items && recentData.items.length > 0) {
          dropdown.innerHTML = recentData.items.map(item => `
            <li><a class="dropdown-item" href="/watchlist_items">
              <img src="${item.poster_url}" alt="${item.title}" class="me-2" style="width: 30px; height: 45px; object-fit: cover;">
              <span>${item.title} (${item.release_year})</span>
            </a></li>
          `).join('') + `
            <li><hr class="dropdown-divider"></li>
            <li><a class="dropdown-item text-primary" href="/watchlist_items">View All</a></li>
          `;
        } else {
          dropdown.innerHTML = '<li><span class="dropdown-item">No items in watchlist</span></li>';
        }
      }
    })
    .catch(error => {
      console.error('Error updating watchlist navbar:', error);
      const badge = document.querySelector('#watchlist-count');
      if (badge) badge.style.display = 'none';
    });
}

document.addEventListener('DOMContentLoaded', function() {
  updateWatchlistNavbar();
});
