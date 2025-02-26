# Running Memory-Intensive Jobs on JRuby with Render

This guide provides detailed instructions on how to set up and deploy the JRuby service for running memory-intensive background jobs on Render's free tier.

## Overview

The Cinematch application uses a dual-runtime architecture:
- **Main Application (MRI Ruby)**: Handles web requests and lightweight background jobs
- **JRuby Service**: Handles memory-intensive background jobs that benefit from JRuby's superior memory management

This approach allows us to leverage JRuby's memory management capabilities for specific tasks while keeping the main application on MRI Ruby.

## Why JRuby for Memory-Intensive Jobs?

JRuby offers several advantages for memory-intensive operations:

1. **Better Memory Management**: JRuby runs on the JVM, which has sophisticated garbage collection algorithms.
2. **Memory Tuning Options**: JRuby provides JVM-specific options for memory management.
3. **Concurrent Garbage Collection**: The JVM can perform garbage collection concurrently with application code.
4. **Larger Heap Space**: JRuby can utilize larger heap spaces more efficiently.

## Setup on Render

### Prerequisites

- A Render account
- A GitHub repository with your Rails application

### Deployment Plans

Our deployment uses the following Render plans:
- **Main Application**: Starter plan ($7/month) - Provides reliable performance for web requests
- **Database**: Starter plan ($7/month) - Ensures data persistence (free tier databases are deleted after 90 days)
- **JRuby Service**: Free plan - Handles memory-intensive jobs with some limitations
- **Redis**: Free plan - Used for caching and job queue

### Deployment Steps

1. **Add the necessary files to your repository**:
   - `render.yaml`: Defines both the main app and JRuby service
   - `Procfile.jruby`: Defines the processes for the JRuby service
   - `.ruby-version.jruby`: Specifies the JRuby version

2. **Push your code to GitHub**:
   ```bash
   git add .
   git commit -m "Add JRuby service configuration"
   git push origin main
   ```

3. **Connect your GitHub repository to Render**:
   - Go to the Render dashboard
   - Click "New" and select "Blueprint"
   - Connect your GitHub repository
   - Render will automatically detect the `render.yaml` file and set up the services

4. **Verify the deployment**:
   - Check that both the main application and JRuby service are deployed
   - Visit the JRuby service URL to verify it's running: `https://your-jruby-service.onrender.com/jruby/ping`

## Local Development

For local development, you'll need to run both the main application and the JRuby service:

1. **Install JRuby**:
   ```bash
   rvm install jruby-9.4.3.0
   # or
   rbenv install jruby-9.4.3.0
   ```

2. **Run the JRuby service**:
   ```bash
   # In one terminal
   ./bin/run-jruby-service.sh
   ```

3. **Run the main application**:
   ```bash
   # In another terminal
   JRUBY_SERVICE_URL=http://localhost:3001 bundle exec rails server -p 3000
   ```

## Managing the JRuby Service

### Admin Interface

The application includes an admin interface for managing the JRuby service:

1. **Access the admin interface**:
   - Go to `/admin/jruby_service` in your main application

2. **Features**:
   - View the JRuby service status
   - Wake up the JRuby service if it's sleeping
   - Run test jobs on the JRuby service
   - View job queue statistics

### Enqueuing Jobs

Use the `JobRoutingService` to enqueue jobs:

```ruby
# Enqueue a job immediately
JobRoutingService.enqueue(FetchContentJob, action: 'fetch_new_content')

# Schedule a job for later
JobRoutingService.schedule(UpdateAllRecommendationsJob, 1.day.from_now)
```

The service will automatically route the job to the JRuby service if it's in the `JRUBY_JOBS` list.

### Monitoring Jobs

1. **Good Job Dashboard**:
   - Access the Good Job dashboard in the main application to monitor all jobs
   - Go to `/good_job` in your main application

2. **JRuby Service Status**:
   - Check the JRuby service status at `/jruby/status`
   - This provides detailed information about memory usage and job statistics

## Handling Render Free Tier Limitations

Render's free tier has some limitations:

1. **Sleep after inactivity**: The service will sleep after 15 minutes of inactivity
2. **Limited resources**: 0.1 CPU and 512 MB RAM
3. **Startup time**: The service takes time to wake up

To handle these limitations:

1. **Automatic wake-up**: The `JobRoutingService` includes a `wake_jruby_service` method that is called automatically when enqueueing jobs
2. **Periodic ping**: A scheduled job (`PingJrubyServiceJob`) pings the JRuby service every 10 minutes to prevent it from sleeping
3. **Memory optimization**: The JRuby service is configured with memory optimization settings
4. **Inline job processing**: The JRuby service processes jobs inline (without a separate worker process) to stay within the free tier limitations

## Troubleshooting

### JRuby Service is Sleeping

If the JRuby service is sleeping:

1. **Check the logs**: Look for "Error waking JRuby service" messages
2. **Manually wake it up**: Visit the JRuby service URL in your browser
3. **Use the admin interface**: Go to `/admin/jruby_service` and click "Wake JRuby Service"

### Memory Issues

If you encounter memory issues:

1. **Check the memory usage**: Go to `/jruby/status` to see the current memory usage
2. **Adjust memory parameters**: Update the environment variables in `render.yaml`:
   - `MEMORY_THRESHOLD_MB`: Memory threshold for triggering cleanup
   - `MAX_BATCH_SIZE`: Maximum batch size for processing
   - `BATCH_SIZE`: Default batch size
   - `MIN_BATCH_SIZE`: Minimum batch size
   - `PROCESSING_BATCH_SIZE`: Batch size for processing items

### Job Failures

If jobs are failing:

1. **Check the Good Job dashboard**: Go to `/good_job` to see job errors
2. **Check the logs**: Look at the logs in the Render dashboard
3. **Run a test job**: Use the admin interface to run a test job with smaller parameters

## Conclusion

Using JRuby for memory-intensive background jobs allows you to leverage its superior memory management capabilities while keeping your main application on MRI Ruby. This dual-runtime architecture is particularly useful for applications running on limited resources like Render's free tier.

For more information, see the [JRuby Service documentation](JRUBY_SERVICE.md). 
