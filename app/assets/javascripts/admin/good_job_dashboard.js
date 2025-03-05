// Wait for document to be ready
document.addEventListener('DOMContentLoaded', initGoodJobDashboard);
document.addEventListener('turbolinks:load', initGoodJobDashboard);
document.addEventListener('page:load', initGoodJobDashboard);

// Initialize dashboard functionality
function initGoodJobDashboard() {
  console.log('Initializing Good Job Dashboard');
  
  // Set up job filtering
  setupJobFiltering();
  
  // Update job runner status immediately and periodically
  updateJobRunnerStatus();
  setInterval(updateJobRunnerStatus, 30000);
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
  
  fetch('/admin/good_job_dashboard/check_job_runner', {
    headers: {
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
    }
  })
  .then(response => response.text())
  .then(html => {
    // Parse the HTML response
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
    
    // Extract the status box from the response
    const newStatusBox = tempDiv.querySelector('.status-box');
    
    if (newStatusBox) {
      // If we already have a status box, replace it
      if (statusBox) {
        statusBox.replaceWith(newStatusBox);
      } else {
        // Otherwise, insert it at the beginning of the container
        container.insertBefore(newStatusBox, container.firstChild);
      }
      console.log('Job runner status updated');
    } else {
      console.error('No status box found in response');
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
