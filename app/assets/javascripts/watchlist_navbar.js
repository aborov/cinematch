function updateWatchlistNavbar() {
  // Exit early if not on a page with watchlist elements
  if (!document.querySelector('#watchlist-count') && !document.querySelector('#watchlist-dropdown')) {
    return;
  }

  console.log('Fetching watchlist counts...');
  
  // Use AbortController to handle timeouts
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 5000); // 5 second timeout

  Promise.all([
    fetch('/watchlist/unwatched_count', {
      signal: controller.signal,
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    }).then(response => {
      if (!response.ok) throw new Error('Count fetch failed');
      return response.json();
    }),
    fetch('/watchlist/recent', {
      signal: controller.signal,
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    }).then(response => {
      if (!response.ok) throw new Error('Recent fetch failed');
      return response.json();
    })
  ])
    .then(([countData, recentData]) => {
      clearTimeout(timeoutId);
      updateWatchlistUI(countData, recentData);
    })
    .catch(error => {
      clearTimeout(timeoutId);
      if (error.name === 'AbortError') {
        console.warn('Watchlist navbar update timed out');
      } else {
        console.error('Error updating watchlist navbar:', error);
      }
      handleWatchlistError();
    });
}

function updateWatchlistUI(countData, recentData) {
  const badge = document.querySelector('#watchlist-count');
  if (badge) {
    badge.textContent = countData.count;
    badge.style.display = countData.count > 0 ? 'inline-block' : 'none';
  }

  const dropdown = document.querySelector('#watchlist-dropdown');
  if (dropdown) {
    if (recentData.items && recentData.items.length > 0) {
      dropdown.innerHTML = recentData.items.map(item => `
        <li><a class="dropdown-item" href="/watchlist">
          <img src="${item.poster_url}" alt="${item.title}" class="me-2" style="width: 30px; height: 45px; object-fit: cover;">
          <span>${item.title} (${item.release_year})</span>
        </a></li>
      `).join('') + `
        <li><hr class="dropdown-divider"></li>
        <li><a class="dropdown-item text-primary" href="/watchlist">View All</a></li>
      `;
    } else {
      dropdown.innerHTML = `
        <li><span class="dropdown-item text-muted">No unwatched items</span></li>
        <li><hr class="dropdown-divider"></li>
        <li><a class="dropdown-item text-primary" href="/watchlist">View Watchlist</a></li>
      `;
    }
  }
}

function handleWatchlistError() {
  const badge = document.querySelector('#watchlist-count');
  if (badge) badge.style.display = 'none';
  
  const dropdown = document.querySelector('#watchlist-dropdown');
  if (dropdown) {
    dropdown.innerHTML = `
      <li><span class="dropdown-item text-muted">Unable to load watchlist</span></li>
      <li><hr class="dropdown-divider"></li>
      <li><a class="dropdown-item text-primary" href="/watchlist">View Watchlist</a></li>
    `;
  }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
  if (document.querySelector('#watchlist-count') || document.querySelector('#watchlist-dropdown')) {
    updateWatchlistNavbar();
  }
});
