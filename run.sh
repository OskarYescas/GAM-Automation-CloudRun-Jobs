#!/bin/bash
set -e

echo "Starting GAM Automation Job..."

# Stage credentials from memory mounts to GAM's expected path
echo "Loading credentials from Secret Manager..."
mkdir -p /root/.gam
cp /secret_client/client_secrets.json /root/.gam/client_secrets.json

if [ -f /secret_oauth/oauth2.txt ]; then
    cp /secret_oauth/oauth2.txt /root/.gam/oauth2.txt
fi

if [ -f /secret_service/oauth2service.json ]; then
    cp /secret_service/oauth2service.json /root/.gam/oauth2service.json
fi

gam version

echo "------------------------------------------------------"
echo "Executing daily GAM task..."
echo "------------------------------------------------------"

gam info domain

echo "GAM Automation Job completed successfully."
