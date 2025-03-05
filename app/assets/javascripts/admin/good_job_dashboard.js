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
      
      // If we've failed too many times, try the fallback method
      if (failedUpdates >= maxFailedUpdates) {
        console.log('Too many failed updates. Trying fallback method.');
        updateJobRunnerStatusFallback();
        failedUpdates = 0;
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
    credentials: 'same-origin',
    // Add a cache-busting parameter to prevent caching
    cache: 'no-store'
  })
  .then(response => {
    console.log('Response received:', response.status, response.statusText);
    console.log('Response type:', response.type);
    console.log('Redirected:', response.redirected);
    
    // Always get the text content, even if redirected
    return response.text().then(html => {
      return {
        html: html,
        redirected: response.redirected,
        url: response.url,
        status: response.status
      };
    });
  })
  .then(result => {
    if (!result.html) {
      console.log('No HTML content received');
      return;
    }
    
    console.log('HTML content received, length:', result.html.length);
    
    // Parse the HTML response
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = result.html;
    
    // If we were redirected to the dashboard page, try to extract the job runner status from there
    if (result.redirected && result.url.includes('/admin/good_job_dashboard')) {
      console.log('Redirected to dashboard page, attempting to extract job runner status');
      
      // Try to find the job runner status container in the full page
      const fullPageStatusContainer = tempDiv.querySelector('#job-runner-status-container');
      if (fullPageStatusContainer) {
        const fullPageStatusBox = fullPageStatusContainer.querySelector('.status-box');
        if (fullPageStatusBox) {
          console.log('Found status box in redirected page:', fullPageStatusBox.className);
          
          // Update our status box with the content from the full page
          if (statusBox) {
            statusBox.innerHTML = fullPageStatusBox.innerHTML;
            statusBox.className = fullPageStatusBox.className;
            
            // Update the last-updated attribute
            const now = Math.floor(Date.now() / 1000);
            statusBox.setAttribute('data-last-updated', now.toString());
            
            console.log('Job runner status updated from redirected page');
            return;
          }
        }
      }
      
      // If we couldn't find the status box in the redirected page, try the fallback method
      console.log('Could not find status box in redirected page, using fallback method');
      updateJobRunnerStatusFallback();
      return;
    }
    
    // Extract the status box from the response (for non-redirected responses)
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
      console.log('Response HTML:', result.html.substring(0, 200) + '...');
      
      // If we got a successful response but no status box, try the fallback method
      if (result.status >= 200 && result.status < 300) {
        console.log('Successful response but no status box, using fallback method');
        updateJobRunnerStatusFallback();
      } else {
        if (statusBox) {
          statusBox.innerHTML = '<p>Error updating job runner status: Invalid response</p>';
          statusBox.className = 'status-box status-error';
        }
      }
    }
  })
  .catch(error => {
    console.error('Error updating job runner status:', error);
    if (statusBox) {
      statusBox.innerHTML = '<p>Error updating job runner status: ' + error.message + '</p>';
      statusBox.className = 'status-box status-error';
    }
    
    // On error, try the fallback method
    console.log('Error in primary method, using fallback method');
    updateJobRunnerStatusFallback();
  });
}

// Fallback method to update job runner status by reloading the entire page in the background
function updateJobRunnerStatusFallback() {
  console.log('Using fallback method to update job runner status');
  
  const container = document.getElementById('job-runner-status-container');
  if (!container) {
    console.log('Job runner status container not found');
    return;
  }
  
  const statusBox = container.querySelector('.status-box');
  if (statusBox) {
    statusBox.innerHTML = '<p>Checking job runner status (fallback method)...</p>';
    statusBox.className = 'status-box status-checking';
  }
  
  // Create a hidden iframe to load the dashboard page
  const iframe = document.createElement('iframe');
  iframe.style.display = 'none';
  document.body.appendChild(iframe);
  
  // Set a timeout to remove the iframe after 30 seconds
  const timeoutId = setTimeout(() => {
    console.log('Fallback method timed out');
    document.body.removeChild(iframe);
    
    if (statusBox) {
      statusBox.innerHTML = '<p>Error: Fallback method timed out</p>';
      statusBox.className = 'status-box status-error';
    }
  }, 30000);
  
  // Handle iframe load event
  iframe.onload = function() {
    clearTimeout(timeoutId);
    
    try {
      // Try to access the iframe content (may fail due to same-origin policy)
      const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
      const iframeStatusContainer = iframeDoc.getElementById('job-runner-status-container');
      
      if (iframeStatusContainer) {
        const iframeStatusBox = iframeStatusContainer.querySelector('.status-box');
        
        if (iframeStatusBox && statusBox) {
          console.log('Found status box in iframe:', iframeStatusBox.className);
          
          // Update our status box with the content from the iframe
          statusBox.innerHTML = iframeStatusBox.innerHTML;
          statusBox.className = iframeStatusBox.className;
          
          // Update the last-updated attribute
          const now = Math.floor(Date.now() / 1000);
          statusBox.setAttribute('data-last-updated', now.toString());
          
          console.log('Job runner status updated from iframe');
        } else {
          console.error('No status box found in iframe');
          if (statusBox) {
            statusBox.innerHTML = '<p>Error: Could not find status box in iframe</p>';
            statusBox.className = 'status-box status-error';
          }
        }
      } else {
        console.error('No status container found in iframe');
        if (statusBox) {
          statusBox.innerHTML = '<p>Error: Could not find status container in iframe</p>';
          statusBox.className = 'status-box status-error';
        }
      }
    } catch (error) {
      console.error('Error accessing iframe content:', error);
      if (statusBox) {
        statusBox.innerHTML = '<p>Error accessing iframe content: ' + error.message + '</p>';
        statusBox.className = 'status-box status-error';
      }
    } finally {
      // Always remove the iframe
      document.body.removeChild(iframe);
    }
  };
  
  // Set the iframe source to the dashboard page
  iframe.src = '/admin/good_job_dashboard';
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
    // Try the regular update first
    try {
      updateJobRunnerStatus();
    } catch (error) {
      console.error('Error in manual refresh:', error);
      // If it fails, use the fallback method
      updateJobRunnerStatusFallback();
    }
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
