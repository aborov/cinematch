# Cinematch Deployment Guide for Render

This guide explains how to deploy the Cinematch application on Render using the dual-runtime architecture with a separate fetcher service.

## Architecture Overview

Cinematch uses a dual-runtime architecture:

1. **Main Application**: Handles web requests, user authentication, and lightweight background jobs
2. **Fetcher Service**: Handles memory-intensive background jobs like content fetching and recommendation generation

This architecture provides several benefits:

- **Memory Isolation**: Memory-intensive jobs run in a separate process, preventing them from affecting the main application's performance
- **Scalability**: Each service can be scaled independently based on its specific resource needs
- **Resilience**: If a memory-intensive job crashes, it doesn't affect the main application

## Prerequisites

- A Render account
- Access to the Cinematch GitHub repository
- A PostgreSQL database on Render or another provider
- A Redis instance (optional, but recommended for production)

## Deploying with Render Blueprint

Cinematch uses a Render Blueprint (render.yaml) to define the infrastructure. This makes deployment simple and consistent.

### Steps to Deploy

1. Log in to your Render dashboard
2. Click "New" and select "Blueprint"
3. Connect your GitHub repository
4. Render will automatically detect the `render.yaml` file and show you the resources that will be created
5. Review the resources and click "Apply"
6. Render will create all the necessary resources and deploy the application

### Environment Variables

The blueprint includes most of the necessary environment variables, but you'll need to set a few sensitive ones manually:

1. After the blueprint is applied, go to the Cinematch web service
2. Click on "Environment" in the left sidebar
3. Add the following environment variables:
   - `THEMOVIEDB_KEY`: Your TMDB API key
   - `SMTP_USERNAME`: Your SMTP username for email delivery
   - `SMTP_PASSWORD`: Your SMTP password for email delivery
4. Click "Save Changes"

## Testing the Deployment

1. Access the main application at `https://cinematch.onrender.com` (or your actual URL)
2. Log in as an admin user
3. Go to the admin dashboard at `/admin/fetcher_service`
4. Check the fetcher service status
5. Run a test job to verify that the fetcher service is working correctly

## Monitoring and Troubleshooting

### Monitoring

- Check the logs for both services in the Render dashboard
- Use the admin dashboard at `/admin/fetcher_service` to monitor the fetcher service status
- Use the admin dashboard at `/admin/good_job` to monitor background jobs

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

## Maintenance

### Updating the Application

1. Push changes to your GitHub repository
2. Render will automatically deploy the changes to both services

### Database Migrations

Database migrations will be run automatically when the main application is deployed. The fetcher service uses the same database, so you don't need to run migrations separately.

### Scaling

If you need to scale the application:

1. Go to the service settings in Render
2. Increase the instance size or number of instances
3. You can scale the main application and fetcher service independently based on their specific needs 
