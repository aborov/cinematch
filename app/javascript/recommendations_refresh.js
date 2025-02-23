document.addEventListener('DOMContentLoaded', function() {
  const refreshButton = document.getElementById('refresh-recommendations');
  if (!refreshButton) return;
  
  // Check if we need to start polling (either from notice or processing state)
  const notice = document.querySelector('.alert-info');
  const isGenerating = notice && notice.textContent.includes('being generated');
  
  if (isGenerating) {
    // Show spinner instead of refresh button
    refreshButton.disabled = true;
    refreshButton.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Generating...';
    checkStatus(refreshButton);
  } else {
    // Check current status
    fetch('/recommendations/check_status')
      .then(response => response.json())
      .then(data => {
        if (data.status === 'processing') {
          refreshButton.disabled = true;
          refreshButton.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Generating...';
          checkStatus(refreshButton);
        } else {
          initializeRefreshButton();
        }
      });
  }
});

function initializeRefreshButton() {
  const refreshButton = document.getElementById('refresh-recommendations');
  if (!refreshButton) return;
  
  refreshButton.addEventListener('click', async function(event) {
    event.preventDefault();
    refreshButton.disabled = true;
    const originalText = refreshButton.innerHTML;
    refreshButton.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Generating...';
    
    try {
      const response = await fetch('/recommendations/refresh', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      });

      const data = await response.json();
      
      if (data.status === 'processing') {
        checkStatus(refreshButton);
      } else {
        refreshButton.disabled = false;
        refreshButton.innerHTML = originalText;
        alert(data.message || 'Failed to refresh recommendations');
      }
    } catch (error) {
      refreshButton.disabled = false;
      refreshButton.innerHTML = originalText;
      alert('Failed to refresh recommendations');
    }
  });
}

function checkStatus(button) {
  fetch('/recommendations/check_status')
    .then(response => response.json())
    .then(data => {
      if (data.status === 'ready') {
        window.location.reload();
      } else if (data.status === 'processing') {
        setTimeout(() => checkStatus(button), 2000);
      } else {
        if (button) {
          button.disabled = false;
          button.innerHTML = 'Refresh Recommendations';
        }
        alert(data.message || 'Failed to refresh recommendations');
      }
    })
    .catch(error => {
      console.error('Error checking status:', error);
      if (button) {
        button.disabled = false;
        button.innerHTML = 'Refresh Recommendations';
      }
    });
}

function showLoadingState(button) {
  const container = button.parentElement;
  button.disabled = true;
  button.querySelector('i').classList.add('text-primary', 'fa-spin');
  
  // Add loading message
  const message = document.createElement('div');
  message.className = 'text-muted small mt-1';
  message.textContent = 'Generating new recommendations...';
  container.appendChild(message);
}

function showSuccessToast() {
  const toast = document.createElement('div');
  toast.className = 'toast position-fixed bottom-0 end-0 m-3';
  toast.innerHTML = `
    <div class="toast-body bg-success text-white">
      Recommendations updated successfully!
    </div>
  `;
  document.body.appendChild(toast);
  new bootstrap.Toast(toast).show();
}

function checkRecommendationsStatus() {
  fetch('/recommendations/check_status')
    .then(response => response.json())
    .then(data => {
      if (data.status === 'ready') {
        window.location.reload();
      } else if (data.status === 'processing') {
        setTimeout(checkRecommendationsStatus, 2000);
      } else {
        const container = document.getElementById('recommendations-container');
        container.innerHTML = `<div class="alert alert-danger">${data.message || 'Failed to load recommendations'}</div>`;
      }
    })
    .catch(error => console.error('Error checking recommendations status:', error));
} 
