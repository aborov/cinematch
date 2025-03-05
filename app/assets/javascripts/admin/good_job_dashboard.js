// Wait for document to be ready
document.addEventListener('DOMContentLoaded', initGoodJobDashboard);
document.addEventListener('turbolinks:load', initGoodJobDashboard);
document.addEventListener('page:load', initGoodJobDashboard);

// Initialize dashboard functionality
function initGoodJobDashboard() {
  console.log('Initializing Good Job Dashboard');
  
  // Set up job filtering
  setupJobFiltering();
  
  // Set up error toggling
  setupErrorToggling();
  
  // Update job runner status immediately and periodically
  updateJobRunnerStatus();
  
  // Set up periodic updates with fallback mechanism
  let failedUpdates = 0;
  const maxFailedUpdates = 3;
  
  const statusUpdateInterval = setInterval(() => {
    // Check if the status box has been updated recently
    const container = document.getElementById('job-runner-status-container');
    if (container) {
      const statusBox = container.querySelector('.status-box');
      if (statusBox) {
        const lastUpdated = parseInt(statusBox.getAttribute('data-last-updated') || '0', 10);
        const now = Math.floor(Date.now() / 1000);
        const timeSinceUpdate = now - lastUpdated;
        
        // If it's been more than 2 minutes since the last update, try a page reload
        if (lastUpdated > 0 && timeSinceUpdate > 120) {
          console.log('Status box has not been updated for', timeSinceUpdate, 'seconds. Reloading page.');
          window.location.reload();
          return;
        }
      }
    }
    
    // Try to update the status
    try {
      updateJobRunnerStatus();
    } catch (error) {
      console.error('Error in periodic status update:', error);
      failedUpdates++;
      
      // If we've failed too many times, reload the page
      if (failedUpdates >= maxFailedUpdates) {
        console.log('Too many failed updates. Reloading page.');
        window.location.reload();
        clearInterval(statusUpdateInterval);
      }
    }
  }, 30000);
  
  // Set up refresh button for job runner status
  setupJobRunnerStatusRefresh();
  
  // Set up job deletion handling
  setupJobDeletion();
}

// Function to update job runner status
function updateJobRunnerStatus() {
  const container = document.getElementById('job-runner-status-container');
  if (!container) {
    console.log('Job runner status container not found');
    return;
  }

  console.log('Updating job runner status');
  
  // Get the current status box and refresh controls
  const statusBox = container.querySelector('.status-box');
  const refreshControls = container.querySelector('.refresh-controls');
  
  // Show loading indicator only if status box exists
  if (statusBox) {
    statusBox.innerHTML = '<p>Checking job runner status...</p>';
    statusBox.className = 'status-box status-checking';
  }
  
  // Get CSRF token from meta tag
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || '';
  console.log('Using CSRF token:', csrfToken ? 'Found token' : 'No token found');
  
  console.log('Fetching job runner status from /admin/good_job_dashboard/check_job_runner');
  fetch('/admin/good_job_dashboard/check_job_runner', {
    method: 'GET',
    headers: {
      'X-CSRF-Token': csrfToken,
      'Accept': 'text/html, application/xhtml+xml',
      'X-Requested-With': 'XMLHttpRequest'
    },
    credentials: 'same-origin'
  })
  .then(response => {
    console.log('Response received:', response.status, response.statusText);
    console.log('Response type:', response.type);
    console.log('Redirected:', response.redirected);
    if (response.redirected) {
      console.log('Redirected to:', response.url);
      
      if (statusBox) {
        statusBox.innerHTML = '<p>Error: Authentication required. Please refresh the page.</p>';
        statusBox.className = 'status-box status-error';
      }
      // Reload the page after a short delay to re-authenticate
      setTimeout(() => { window.location.reload(); }, 3000);
      return null;
    }
    return response.text();
  })
  .then(html => {
    if (!html) {
      console.log('No HTML content received');
      return; // Handle the redirect case
    }
    
    console.log('HTML content received, length:', html.length);
    
    // Parse the HTML response
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
    
    // Extract the status box from the response
    const newStatusBox = tempDiv.querySelector('.status-box');
    
    if (newStatusBox) {
      console.log('Status box found in response:', newStatusBox.className);
      
      // If we already have a status box, replace it
      if (statusBox) {
        statusBox.replaceWith(newStatusBox);
      } else {
        // Otherwise, insert it at the beginning of the container
        container.insertBefore(newStatusBox, container.firstChild);
      }
      console.log('Job runner status updated successfully');
    } else {
      console.error('No status box found in response');
      console.log('Response HTML:', html.substring(0, 200) + '...');
      
      if (statusBox) {
        statusBox.innerHTML = '<p>Error updating job runner status: Invalid response</p>';
        statusBox.className = 'status-box status-error';
      }
    }
  })
  .catch(error => {
    console.error('Error updating job runner status:', error);
    if (statusBox) {
      statusBox.innerHTML = '<p>Error updating job runner status: ' + error.message + '</p>';
      statusBox.className = 'status-box status-error';
    }
  });
}

// Set up job filtering
function setupJobFiltering() {
  const jobFilter = document.getElementById('job-filter');
  const statusFilter = document.getElementById('status-filter');
  
  if (!jobFilter || !statusFilter) {
    console.log('Job filters not found');
    return;
  }
  
  console.log('Setting up job filtering');
  
  jobFilter.addEventListener('change', filterJobs);
  statusFilter.addEventListener('change', filterJobs);
  
  // Initial filtering
  filterJobs();
}

// Function to filter jobs
function filterJobs() {
  const jobFilter = document.getElementById('job-filter');
  const statusFilter = document.getElementById('status-filter');
  
  if (!jobFilter || !statusFilter) return;
  
  const jobClass = jobFilter.value;
  const status = statusFilter.value;
  
  console.log(`Filtering jobs: class=${jobClass}, status=${status}`);
  
  const rows = document.querySelectorAll('.job-row');
  let visibleCount = 0;
  
  rows.forEach(row => {
    const rowJobClass = row.getAttribute('data-job-class');
    const rowStatus = row.getAttribute('data-status');
    
    const jobClassMatch = jobClass === 'all' || rowJobClass === jobClass;
    const statusMatch = status === 'all' || rowStatus === status;
    
    if (jobClassMatch && statusMatch) {
      row.style.display = '';
      visibleCount++;
    } else {
      row.style.display = 'none';
    }
  });
  
  console.log(`Filtered jobs: ${visibleCount} visible out of ${rows.length} total`);
}

// Set up error toggling
function setupErrorToggling() {
  const toggleButtons = document.querySelectorAll('.toggle-error-btn');
  
  if (toggleButtons.length === 0) {
    console.log('No error toggle buttons found');
    return;
  }
  
  console.log('Setting up error toggling for', toggleButtons.length, 'buttons');
  
  toggleButtons.forEach(button => {
    button.addEventListener('click', function() {
      const jobId = this.getAttribute('data-job-id');
      const errorDetails = document.getElementById('error-' + jobId);
      
      if (errorDetails) {
        // Toggle the hidden class
        errorDetails.classList.toggle('hidden');
        
        // Update button text
        if (errorDetails.classList.contains('hidden')) {
          this.textContent = 'View Error';
        } else {
          this.textContent = 'Hide Error';
        }
      }
    });
  });
}

// Set up refresh button for job runner status
function setupJobRunnerStatusRefresh() {
  const refreshButton = document.getElementById('refresh-job-runner-status');
  
  if (!refreshButton) {
    console.log('Refresh button for job runner status not found');
    return;
  }
  
  console.log('Setting up refresh button for job runner status');
  
  refreshButton.addEventListener('click', function() {
    updateJobRunnerStatus();
  });
}

// Set up job deletion handling
function setupJobDeletion() {
  const deleteButtons = document.querySelectorAll('.delete-job-btn, .delete-job');
  
  if (deleteButtons.length === 0) {
    console.log('No job deletion buttons found');
    return;
  }
  
  console.log('Setting up job deletion for', deleteButtons.length, 'buttons');
  
  deleteButtons.forEach(button => {
    button.addEventListener('click', function(event) {
      // The default Rails UJS will handle the actual deletion
      // This is just to ensure we reload the page after deletion
      const originalHref = this.getAttribute('href');
      
      // Log the deletion attempt
      console.log('Deleting job via:', originalHref);
    });
  });
} 
