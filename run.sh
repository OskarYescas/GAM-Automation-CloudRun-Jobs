#!/bin/bash

# Exit script if any command fails
set -e

echo "Starting GAM Automation Job..."

# Copy secrets from Secret Manager mount to GAM directory
# This allows GAM to read the static credentials, and temporarily 
# update the oauth token if it needs to refresh it during the run.
echo "Loading credentials from Secret Manager..."
cp /secret_client/client_secrets.json /root/.gam/client_secrets.json

if [ -f /secret_oauth/oauth2.txt ]; then
    cp /secret_oauth/oauth2.txt /root/.gam/oauth2.txt
fi

if [ -f /secret_service/oauth2service.json ]; then
    cp /secret_service/oauth2service.json /root/.gam/oauth2service.json
fi

# Print the GAM version to verify installation
gam version

echo "------------------------------------------------------"
echo "Executing daily GAM task..."
echo "------------------------------------------------------"

# REPLACE THIS with your actual command
gam info domain

echo "GAM Automation Job completed successfully."
