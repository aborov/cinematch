# Fetcher Service Guide

## Overview

The fetcher service is a separate Rails application that handles memory-intensive background jobs for CineMatch. This guide provides technical details about the fetcher service, how it works, and how to debug issues.

## How It Works

### Job Routing

When a job is marked with `runs_on_fetcher`, the `ApplicationJob` class routes it to the fetcher service:

1. The job is enqueued using `perform_later`
2. The `perform_later` method in `ApplicationJob` checks if the job is marked with `runs_on_fetcher`
3. If it is, the job is routed to the fetcher service using `JobRoutingService.enqueue`
4. The `JobRoutingService` makes an API call to the fetcher service to enqueue the job

### Fetcher Service Client

The `FetcherServiceClient` class handles communication with the fetcher service:

```ruby
# app/services/fetcher_service_client.rb
class FetcherServiceClient
  def self.fetch_movies(provider, batch_size)
    # Make API call to fetcher service
  end
  
  def self.enqueue_job(job_class, args)
    # Make API call to fetcher service to enqueue a job
  end
  
  def self.check_status
    # Check the status of the fetcher service
  end
  
  def self.wake_up
    # Wake up the fetcher service if it's sleeping
  end
end
```

### Job Execution

The fetcher service runs the jobs in its own process, isolated from the main application. This prevents memory-intensive jobs from affecting the main application's performance.

## Debugging

### Checking Job Status

You can check the status of jobs in the fetcher service using the admin dashboard at `/admin/fetcher_service`.

### Checking Logs

The fetcher service logs can be viewed in the Render dashboard. Look for errors related to job execution, memory usage, or API calls.

### Common Issues

#### Jobs Not Being Processed

If jobs are not being processed by the fetcher service:

1. Check if the fetcher service is running
2. Verify the `FETCHER_SERVICE_URL` environment variable is set correctly
3. Check the fetcher service logs for errors
4. Try restarting the fetcher service

#### Memory Issues

If the fetcher service is crashing due to memory issues:

1. Check the logs for memory-related errors
2. Consider increasing the instance size in Render
3. Reduce the batch size for memory-intensive jobs
4. Implement more aggressive memory cleanup in the job code

#### API Communication Issues

If there are issues with API communication between the main application and the fetcher service:

1. Check if the fetcher service is accessible from the main application
2. Verify the `FETCHER_SERVICE_URL` environment variable is set correctly
3. Check for network issues or firewall rules that might be blocking communication

## Emergency Fallback

In case the fetcher service is unavailable, you can temporarily run fetcher jobs on the main application:

1. Go to the admin dashboard at `/admin/good_job`
2. When running a job, check the "Emergency Override: Allow fetcher jobs to run on the main app" option
3. Be aware that this may cause memory issues on the main application

## Monitoring

### Memory Usage

Monitor the memory usage of the fetcher service to ensure it's not approaching the limits of the instance:

1. Check the Render dashboard for memory usage metrics
2. Implement memory monitoring in the job code to log memory usage during execution
3. Set up alerts for high memory usage

### Job Queue

Monitor the job queue to ensure jobs are being processed in a timely manner:

1. Check the admin dashboard at `/admin/fetcher_service` for the current job queue
2. Set up alerts for long job queues or jobs that have been waiting for a long time

## Best Practices

### Memory Management

To minimize memory usage in fetcher jobs:

1. Process data in small batches
2. Release references to large objects when they're no longer needed
3. Call the garbage collector explicitly after processing large batches
4. Use streaming APIs when possible to avoid loading large datasets into memory

### Error Handling

Implement robust error handling in fetcher jobs:

1. Catch and log all exceptions
2. Implement retries with exponential backoff for transient errors
3. Notify administrators of persistent errors
4. Gracefully degrade functionality when services are unavailable 
