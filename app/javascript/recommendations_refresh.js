async function initializeRefreshButton() {
  console.log('Looking for refresh button...');
  const refreshButton = document.getElementById('refresh-recommendations');
  console.log('Refresh button found:', refreshButton);
  
  if (!refreshButton) return;
  
  console.log('Looking for icon...');
  const icon = refreshButton.querySelector('i');
  console.log('Icon found:', icon);
  
  if (!icon) return;
  
  console.log('Setting up click handler...');
  refreshButton.addEventListener('click', async function(event) {
    console.log('Refresh button clicked');
    event.preventDefault();
    icon.classList.add('text-primary', 'fa-spin');
    this.disabled = true;

    try {
      const response = await fetch('/recommendations/refresh', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'X-Requested-With': 'XMLHttpRequest'
        }
      });

      const data = await response.json();
      if (data.status === 'success') {
        pollStatus(icon, refreshButton);
      } else {
        throw new Error(data.message || 'Refresh failed');
      }
    } catch (error) {
      console.error('Failed to refresh recommendations:', error);
      icon.classList.remove('text-primary', 'fa-spin');
      this.disabled = false;
    }
  });
}

async function pollStatus(icon, button) {
  const checkStatus = async () => {
    try {
      const response = await fetch('/recommendations/check_status');
      const data = await response.json();
      
      if (data.status === 'ready') {
        icon.classList.remove('text-primary', 'fa-spin');
        button.disabled = false;
        window.location.reload();
      } else {
        setTimeout(checkStatus, 2000);
      }
    } catch (error) {
      console.error('Error checking status:', error);
      icon.classList.remove('text-primary', 'fa-spin');
      button.disabled = false;
    }
  };
  
  checkStatus();
}

document.addEventListener('DOMContentLoaded', function() {
  console.log('Recommendations refresh initialization starting');
  initializeRefreshButton();
  console.log('Recommendations refresh initialization complete');
}); 
