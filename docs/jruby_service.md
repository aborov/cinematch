# JRuby Service Guide

> **Note:** This is a technical troubleshooting guide for the JRuby service. For information about the architecture, deployment process, and rationale behind using JRuby, see [JRuby Render Setup Guide](jruby_render_setup.md).

This document provides information about the JRuby service, how it works, and how to troubleshoot common issues.

## Overview

The application uses a separate JRuby service to handle memory-intensive jobs. This service runs on JRuby, which has better memory management for large datasets compared to MRI Ruby.

Key components:
- **Main Application**: Runs on MRI Ruby and handles most of the application logic
- **JRuby Service**: Runs on JRuby and handles memory-intensive jobs

## How Job Routing Works

1. Jobs that should run on JRuby are marked with the `JrubyJobConcern` module
2. The `JobRoutingService` determines if a job should be routed to JRuby
3. Jobs are enqueued with a specific queue name
4. The main application is configured to NOT process JRuby queues
5. The JRuby service is configured to ONLY process JRuby queues

## Common Issues

### Jobs Running on MRI Instead of JRuby

If you see jobs that should be running on JRuby running on MRI instead, check:

1. **Job Configuration**: Make sure the job class includes `JrubyJobConcern` and is listed in `JobRoutingService::JRUBY_JOBS`
2. **Queue Configuration**: Verify the job is using a queue listed in `JobRoutingService::JRUBY_QUEUES`
3. **GoodJob Configuration**: Check that the main app excludes JRuby queues and the JRuby service only processes JRuby queues
4. **JRuby Service Status**: Ensure the JRuby service is running and awake

### JRuby Service Not Processing Jobs

If the JRuby service is running but not processing jobs:

1. **Check Service Status**: Use `rake jruby_service:status` to check the service status
2. **Check Queue Configuration**: Verify the JRuby service is configured to process the correct queues
3. **Check Logs**: Look for errors in the JRuby service logs
4. **Restart Service**: Try restarting the JRuby service

### Memory Issues

If you're experiencing memory issues:

1. **Check Memory Usage**: Use `rake jruby_service:status` to check memory usage
2. **Adjust Memory Settings**: Update the JRuby service memory settings in `render.yaml`
3. **Optimize Jobs**: Review memory-intensive jobs for optimization opportunities

## Debugging Tools

The application includes several rake tasks to help debug JRuby service issues:

```bash
# Check JRuby service status
rake jruby_service:status

# Wake up the JRuby service
rake jruby_service:wake

# List all jobs configured to run on JRuby
rake jruby_service:list_jobs

# Check if a specific job is configured to run on JRuby
rake jruby_service:check_job[FetchContentJob]

# Debug job routing for a specific job
rake jruby_service:debug_routing[FetchContentJob]

# Enqueue a test job to run on JRuby
rake jruby_service:test_job
```

## Configuration Files

The JRuby service configuration is spread across several files:

1. **config/initializers/jruby_service.rb**: Main configuration for the JRuby service
2. **config/initializers/good_job.rb**: GoodJob configuration
3. **app/services/job_routing_service.rb**: Job routing logic
4. **app/models/concerns/jruby_job_concern.rb**: Concern for marking jobs to run on JRuby
5. **render.yaml**: Service configuration for Render

## Render Deployment

The JRuby service is deployed as a separate service on Render. The configuration is in `render.yaml`.

Key settings:
- **Environment Variables**: Make sure `RUBY_VERSION` is set to `jruby-9.4.3.0`
- **Build Command**: Should include `bundle install`
- **Start Command**: Should start the JRuby service with the correct configuration

## Testing JRuby Jobs Locally

To test JRuby jobs locally:

1. Install JRuby: `rbenv install jruby-9.4.3.0`
2. Set up the JRuby environment: `RUBY_VERSION=jruby-9.4.3.0 bundle install`
3. Start the JRuby service: `RUBY_VERSION=jruby-9.4.3.0 SIMULATE_JRUBY_SERVICE=true bundle exec rails server -p 3001`
4. In another terminal, start the main app: `bundle exec rails server`
5. Enqueue a test job: `rake jruby_service:test_job`

## Troubleshooting Checklist

If you're experiencing issues with the JRuby service, follow this checklist:

1. **Verify Configuration**:
   - Check `config/initializers/jruby_service.rb`
   - Check `config/initializers/good_job.rb`
   - Check `app/services/job_routing_service.rb`

2. **Check Service Status**:
   - Run `rake jruby_service:status`
   - Check if the service is running on JRuby
   - Check if the service is processing the correct queues

3. **Test Job Routing**:
   - Run `rake jruby_service:debug_routing[FetchContentJob]`
   - Verify the job is configured correctly

4. **Check Logs**:
   - Look for errors in the JRuby service logs
   - Check for wake-up attempts in the main app logs

5. **Restart Services**:
   - Restart the JRuby service
   - If necessary, restart the main app

## Additional Resources

- [JRuby Documentation](https://www.jruby.org/documentation)
- [GoodJob Documentation](https://github.com/bensheldon/good_job)
- [Render Documentation](https://render.com/docs) 
