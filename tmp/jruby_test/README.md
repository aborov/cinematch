# JRuby Service Testing

This directory contains scripts to test the JRuby service integration in development.

## Overview

The Cinematch application uses a separate JRuby service to handle memory-intensive jobs like content fetching. This setup allows us to:

1. Isolate memory-intensive operations to a dedicated service
2. Prevent memory issues in the main application
3. Leverage JRuby's memory management for specific tasks

## Test Scripts

### 1. JRuby Service Simulator

```bash
./simulate_jruby_service.rb
```

This script simulates a separate JRuby service. It:
- Monitors for jobs in the JRuby queues
- Processes jobs when they are enqueued
- Simulates the service going to sleep after inactivity
- Wakes up when pinged or when a job is enqueued

### 2. Job Routing Simulator

```bash
./simulate_job_routing.rb [options]
```

Options:
- `-j, --job-class JOB_CLASS`: Job class to enqueue (default: FetchContentJob)
- `-a, --args ARGS`: Job arguments as JSON string (default: {"fetch_new":true})
- `-p, --ping`: Just ping the JRuby service without enqueuing a job
- `-h, --help`: Show help message

Examples:
```bash
# Enqueue a FetchContentJob with default arguments
./simulate_job_routing.rb

# Enqueue a specific job with custom arguments
./simulate_job_routing.rb -j UpdateAllRecommendationsJob -a '{"force":true}'

# Just ping the JRuby service
./simulate_job_routing.rb -p
```

### 3. Ping Job Simulator

```bash
./simulate_ping_job.rb
```

This script simulates the periodic `PingJrubyServiceJob` that runs every 10 minutes in production. For testing purposes, it pings every 10 seconds instead.

## Testing Scenarios

### Scenario 1: On-demand Awakening Only

1. Start the JRuby service simulator: `./simulate_jruby_service.rb`
2. Enqueue a job: `./simulate_job_routing.rb`
3. Observe that the service wakes up and processes the job
4. Wait for the service to go to sleep (1 minute of inactivity)
5. Enqueue another job and observe the service waking up again

### Scenario 2: With Periodic Pinging

1. Start the JRuby service simulator: `./simulate_jruby_service.rb`
2. Start the ping job simulator: `./simulate_ping_job.rb`
3. Observe the service being pinged every 10 seconds
4. Enqueue a job: `./simulate_job_routing.rb`
5. Observe the job being processed

### Scenario 3: Testing the Smart Pinging Logic

The updated `PingJrubyServiceJob` now only pings when:
- There are pending jobs in JRuby queues
- It's been more than 30 minutes since the last ping

To test this:
1. Start the JRuby service simulator: `./simulate_jruby_service.rb`
2. Start the ping job simulator: `./simulate_ping_job.rb`
3. Observe that pings only happen when there are pending jobs
4. Enqueue a job but don't let it be processed (e.g., stop the JRuby service)
5. Observe that the ping job detects the pending job and attempts to wake the service

## Logs

The test scripts create several log files:
- `tmp/jruby_test/jruby_wakeups.log`: Records when the JRuby service wakes up, goes to sleep, and processes jobs
- `tmp/jruby_test/ping_job.log`: Records when the ping job executes and whether it found pending jobs

## Conclusion

These test scripts help verify that:
1. The JRuby service awakens when jobs are enqueued
2. Jobs are properly routed to the JRuby service
3. The ping job only wakes the service when necessary
4. Memory-intensive jobs run exclusively on the JRuby service 
