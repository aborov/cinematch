# Fetcher Service Setup Guide

## Overview

CineMatch uses a dual-runtime architecture with a separate fetcher service for memory-intensive background jobs. This guide explains how to set up and deploy the fetcher service.

## Architecture

The CineMatch application is split into two services:

1. **Main Application**: Handles web requests, user authentication, and lightweight background jobs
2. **Fetcher Service**: Handles memory-intensive background jobs like content fetching and recommendation generation

This architecture provides several benefits:

- **Memory Isolation**: Memory-intensive jobs run in a separate process, preventing them from affecting the main application's performance
- **Scalability**: Each service can be scaled independently based on its specific resource needs
- **Resilience**: If a memory-intensive job crashes, it doesn't affect the main application

## Deployment on Render

### Prerequisites

- A Render account
- Access to the CineMatch GitHub repository

### Steps to Deploy the Fetcher Service

1. Log in to your Render dashboard
2. Click "New" and select "Web Service"
3. Connect your GitHub repository
4. Configure the service with the following settings:
   - **Name**: cinematch-fetcher
   - **Environment**: Docker
   - **Dockerfile Path**: Dockerfile.fetcher
   - **Branch**: main (or your deployment branch)
   - **Region**: Choose the region closest to your users
   - **Instance Type**: Standard (1x CPU, 2GB RAM)
   - **Health Check Path**: /health
   - **Auto-Deploy**: Yes

5. Add the following environment variables:
   - `RAILS_ENV=production`
   - `RAILS_MASTER_KEY=[your-master-key]`
   - `DATABASE_URL=[your-database-url]`
   - `REDIS_URL=[your-redis-url]`
   - `THEMOVIEDB_KEY=[your-tmdb-api-key]`
   - `SIMULATE_FETCHER=true`

6. Click "Create Web Service"

### Configuring the Main Application

After deploying the fetcher service, you need to configure the main application to use it:

1. Go to your main application's environment variables in Render
2. Add the following environment variable:
   - `FETCHER_SERVICE_URL=https://cinematch-fetcher.onrender.com`

## Local Development

To run the application with the fetcher service locally:

1. Start the fetcher service:
```bash
# In one terminal
SIMULATE_FETCHER=true bundle exec rails server -p 3001
```

2. Start the main application:
```bash
# In another terminal
FETCHER_SERVICE_URL=http://localhost:3001 bundle exec rails server -p 3000
```

## Monitoring and Troubleshooting

### Monitoring

- Check the fetcher service logs in the Render dashboard
- Use the admin dashboard at `/admin/fetcher_service` to monitor the service status and job queue

### Troubleshooting

If jobs are not being processed by the fetcher service:

1. Check if the fetcher service is running
2. Verify the `FETCHER_SERVICE_URL` environment variable is set correctly
3. Check the fetcher service logs for errors
4. Try restarting the fetcher service

If the fetcher service is crashing:

1. Check the logs for memory-related errors
2. Consider increasing the instance size in Render
3. Reduce the batch size for memory-intensive jobs

## Emergency Fallback

In case the fetcher service is unavailable, you can temporarily run fetcher jobs on the main application:

1. Go to the admin dashboard at `/admin/good_job`
2. When running a job, check the "Emergency Override: Allow fetcher jobs to run on the main app" option
3. Be aware that this may cause memory issues on the main application 
