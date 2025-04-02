#!/usr/bin/env bash
# Script to set up environment variables on Render

# Generate a random secret for job runner authentication
JOB_RUNNER_SECRET=$(openssl rand -hex 16)

echo "Generated JOB_RUNNER_SECRET: $JOB_RUNNER_SECRET"
echo ""
echo "Please add this environment variable to BOTH your main app and job runner services on Render:"
echo ""
echo "JOB_RUNNER_SECRET=$JOB_RUNNER_SECRET"
echo ""
echo "Instructions:"
echo "1. Go to the Render dashboard: https://dashboard.render.com/"
echo "2. Select your main app service"
echo "3. Go to Environment -> Environment Variables"
echo "4. Add the JOB_RUNNER_SECRET variable with the value above"
echo "5. Repeat steps 2-4 for your job runner service"
echo "6. Redeploy both services"
echo ""
echo "This will ensure both services use the same secret for authentication." 
