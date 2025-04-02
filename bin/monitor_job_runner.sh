#!/bin/bash

# Script to monitor the job runner process and restart it if memory usage exceeds threshold
# Usage: ./monitor_job_runner.sh [memory_threshold_mb] [check_interval_seconds]

# Default values
MEMORY_THRESHOLD=${1:-500}  # Default: 500 MB
CHECK_INTERVAL=${2:-300}    # Default: 300 seconds (5 minutes)
PID_FILE="tmp/pids/good_job.pid"
LOG_FILE="log/job_runner_monitor.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

restart_job_runner() {
  log "Restarting job runner due to high memory usage"
  
  # Stop the job runner
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    log "Stopping job runner process $pid"
    kill -TERM "$pid" 2>/dev/null
    
    # Wait for process to terminate
    for i in {1..30}; do
      if ! ps -p "$pid" > /dev/null; then
        break
      fi
      sleep 1
    done
    
    # Force kill if still running
    if ps -p "$pid" > /dev/null; then
      log "Force killing job runner process $pid"
      kill -9 "$pid" 2>/dev/null
    fi
  fi
  
  # Start the job runner
  log "Starting new job runner process"
  RAILS_ENV=production bundle exec good_job start >> log/good_job.log 2>&1 &
  
  log "Job runner restarted with PID: $!"
}

# Create log file if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log "Starting job runner monitor (threshold: ${MEMORY_THRESHOLD}MB, interval: ${CHECK_INTERVAL}s)"

while true; do
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    
    if ps -p "$pid" > /dev/null; then
      # Get memory usage in KB and convert to MB
      memory_usage=$(ps -o rss= -p "$pid" | awk '{print $1/1024}')
      memory_usage_rounded=$(printf "%.0f" "$memory_usage")
      
      log "Job runner (PID: $pid) memory usage: ${memory_usage_rounded}MB"
      
      if (( $(echo "$memory_usage_rounded > $MEMORY_THRESHOLD" | bc -l) )); then
        log "Memory usage exceeds threshold (${memory_usage_rounded}MB > ${MEMORY_THRESHOLD}MB)"
        restart_job_runner
      fi
    else
      log "Job runner process $pid not found, restarting"
      restart_job_runner
    fi
  else
    log "PID file not found, starting job runner"
    restart_job_runner
  fi
  
  sleep "$CHECK_INTERVAL"
done 
