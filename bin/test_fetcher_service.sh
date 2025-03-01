#!/bin/bash

# Script to test the fetcher service

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "curl is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed
JQ_AVAILABLE=true
if ! command -v jq &> /dev/null; then
    echo "Warning: jq is not installed. JSON output will not be formatted."
    JQ_AVAILABLE=false
fi

# Function to format JSON output
format_json() {
    if [ "$JQ_AVAILABLE" = true ]; then
        jq .
    else
        cat
    fi
}

# Default values
FETCHER_URL=${FETCHER_SERVICE_URL:-"http://localhost:3001"}
PROVIDER=${1:-"tmdb"}
BATCH_SIZE=${2:-5}

# Function to display help
function display_help {
    echo "Usage: $0 [provider] [batch_size]"
    echo ""
    echo "Arguments:"
    echo "  provider    The provider to fetch from (tmdb or omdb). Default: tmdb"
    echo "  batch_size  The number of items to fetch. Default: 5"
    echo ""
    echo "Environment Variables:"
    echo "  FETCHER_SERVICE_URL  The URL of the fetcher service. Default: http://localhost:3001"
    echo ""
    echo "Examples:"
    echo "  $0                   Test with default values (tmdb, 5)"
    echo "  $0 omdb              Test with omdb provider and default batch size"
    echo "  $0 tmdb 10           Test with tmdb provider and batch size 10"
    echo "  FETCHER_SERVICE_URL=https://cinematch-fetcher.onrender.com $0  Test with custom URL"
    exit 0
}

# Check for help flag
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    display_help
fi

echo "Testing fetcher service at $FETCHER_URL"
echo "Provider: $PROVIDER"
echo "Batch size: $BATCH_SIZE"
echo ""

# Test ping endpoint
echo "Testing ping endpoint..."
curl -s "$FETCHER_URL/fetcher/ping" | format_json
echo ""

# Test status endpoint
echo "Testing status endpoint..."
curl -s "$FETCHER_URL/fetcher/status" | format_json
echo ""

# Test fetch endpoint
echo "Testing fetch endpoint with provider $PROVIDER and batch size $BATCH_SIZE..."
curl -s -X POST "$FETCHER_URL/fetcher/fetch" \
    -d "provider=$PROVIDER" \
    -d "batch_size=$BATCH_SIZE" | format_json
echo ""

echo "Done!"
exit 0 
