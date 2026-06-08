#!/bin/bash

# Exit script if any command fails
set -e

echo "======================================================"
echo "      GAM Automation Interactive Deployment Script"
echo "======================================================"
echo ""
echo "This script will build your GAM Docker container,"
echo "securely upload your credentials to Secret Manager,"
echo "and deploy it to Google Cloud Run Jobs."
echo ""

# Ask for details interactively
read -p "Enter your GCP Project ID: " PROJECT_ID
read -p "Enter the GCP Region (e.g., us-central1): " REGION
read -p "Enter Artifact Registry Repo Name [gam-automation-repo]: " REPO
REPO=${REPO:-gam-automation-repo}
read -p "Enter Cloud Run Job Name [gam-daily-job]: " JOB_NAME
JOB_NAME=${JOB_NAME:-gam-daily-job}

echo ""
echo "Setting GCP project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID" --quiet

echo ""
echo "------------------------------------------------------"
echo "0. Enabling Required GCP APIs..."
echo "------------------------------------------------------"
echo "This might take a minute if they are not already enabled."
gcloud services enable artifactregistry.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    cloudscheduler.googleapis.com \
    secretmanager.googleapis.com --quiet

# Google Cloud APIs can take a few seconds to propagate after being enabled.
echo "Waiting 15 seconds for API enablement to propagate..."
sleep 15

echo ""
echo "------------------------------------------------------"
echo "1. Checking Artifact Registry..."
echo "------------------------------------------------------"
if ! gcloud artifacts repositories describe "$REPO" --location="$REGION" --quiet >/dev/null 2>&1; then
    echo "Repository '$REPO' not found. Creating it now in $REGION..."
    gcloud artifacts repositories create "$REPO" \
        --repository-format=docker \
        --location="$REGION" \
        --description="Docker repository for GAM automation" \
        --quiet
else
    echo "Repository '$REPO' already exists."
fi

echo ""
echo "------------------------------------------------------"
echo "2. Setting up Secret Manager..."
echo "------------------------------------------------------"
echo "We need to securely store your GAM credentials in Google Cloud Secret Manager."

if [[ ! -f "client_secrets.json" ]]; then
    echo "Error: client_secrets.json not found in the current directory!"
    exit 1
fi

if [[ ! -f "oauth2.txt" ]] && [[ ! -f "oauth2service.json" ]]; then
    echo "Error: Neither oauth2.txt nor oauth2service.json were found. You must provide at least one!"
    exit 1
fi

# Create or update client_secrets.json
if ! gcloud secrets describe gam-client-secrets --quiet >/dev/null 2>&1; then
    echo "Creating secret 'gam-client-secrets'..."
    gcloud secrets create gam-client-secrets --replication-policy="automatic" --quiet
    gcloud secrets versions add gam-client-secrets --data-file="client_secrets.json" --quiet
else
    echo "Secret 'gam-client-secrets' already exists. Updating with local file..."
    gcloud secrets versions add gam-client-secrets --data-file="client_secrets.json" --quiet
fi

# Create or update oauth2.txt if it exists
if [[ -f "oauth2.txt" ]]; then
    if ! gcloud secrets describe gam-oauth-token --quiet >/dev/null 2>&1; then
        echo "Creating secret 'gam-oauth-token'..."
        gcloud secrets create gam-oauth-token --replication-policy="automatic" --quiet
        gcloud secrets versions add gam-oauth-token --data-file="oauth2.txt" --quiet
    else
        echo "Secret 'gam-oauth-token' already exists. Updating with local file..."
        gcloud secrets versions add gam-oauth-token --data-file="oauth2.txt" --quiet
    fi
fi

# Create or update oauth2service.json if it exists
if [[ -f "oauth2service.json" ]]; then
    if ! gcloud secrets describe gam-oauth-service --quiet >/dev/null 2>&1; then
        echo "Creating secret 'gam-oauth-service'..."
        gcloud secrets create gam-oauth-service --replication-policy="automatic" --quiet
        gcloud secrets versions add gam-oauth-service --data-file="oauth2service.json" --quiet
    else
        echo "Secret 'gam-oauth-service' already exists. Updating with local file..."
        gcloud secrets versions add gam-oauth-service --data-file="oauth2service.json" --quiet
    fi
fi

# Grant compute service account access
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "Granting secretAccessor role to $SA_EMAIL..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet >/dev/null

echo "Granting Cloud Build necessary permissions to $SA_EMAIL..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/cloudbuild.builds.builder" \
    --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/artifactregistry.writer" \
    --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/logging.logWriter" \
    --quiet >/dev/null

# Wait 10 seconds for IAM roles to propagate
echo "Waiting 10 seconds for IAM permissions to propagate..."
sleep 10

echo ""
echo "------------------------------------------------------"
echo "3. Building and Pushing Docker Image..."
echo "------------------------------------------------------"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${JOB_NAME}-image:latest"
gcloud builds submit --tag "$IMAGE_URI" . --quiet

echo ""
echo "------------------------------------------------------"
echo "4. Creating Cloud Run Job..."
echo "------------------------------------------------------"
# Build the secret arguments string dynamically based on what files we have
SECRET_ARGS="/secret_client/client_secrets.json=gam-client-secrets:latest"
if [[ -f "oauth2.txt" ]]; then
    SECRET_ARGS="${SECRET_ARGS},/secret_oauth/oauth2.txt=gam-oauth-token:latest"
fi
if [[ -f "oauth2service.json" ]]; then
    SECRET_ARGS="${SECRET_ARGS},/secret_service/oauth2service.json=gam-oauth-service:latest"
fi

# Check if job exists to determine if we create or update
if gcloud run jobs describe "$JOB_NAME" --region "$REGION" --quiet >/dev/null 2>&1; then
    echo "Updating existing Cloud Run Job..."
    gcloud run jobs update "$JOB_NAME" \
      --image "$IMAGE_URI" \
      --region "$REGION" \
      --task-timeout 10m \
      --max-retries 0 \
      --set-secrets="$SECRET_ARGS" \
      --quiet
else
    echo "Creating new Cloud Run Job..."
    gcloud run jobs create "$JOB_NAME" \
      --image "$IMAGE_URI" \
      --region "$REGION" \
      --task-timeout 10m \
      --max-retries 0 \
      --set-secrets="$SECRET_ARGS" \
      --quiet
fi

echo ""
echo "------------------------------------------------------"
echo "5. Job Scheduling..."
echo "------------------------------------------------------"
read -p "Do you want to schedule this job to run automatically? (y/n): " SCHEDULE_CHOICE
if [[ "$SCHEDULE_CHOICE" == "y" || "$SCHEDULE_CHOICE" == "Y" ]]; then
    read -p "Enter Cron Schedule (e.g., '0 8 * * *' for 8 AM daily): " CRON_SCHEDULE
    read -p "Enter Scheduler Job Name [gam-daily-schedule]: " SCHEDULER_NAME
    SCHEDULER_NAME=${SCHEDULER_NAME:-gam-daily-schedule}
    
    echo "Creating/Updating Cloud Scheduler trigger..."
    if gcloud scheduler jobs describe "$SCHEDULER_NAME" --location="$REGION" --quiet >/dev/null 2>&1; then
        gcloud scheduler jobs update http "$SCHEDULER_NAME" \
          --location "$REGION" \
          --schedule "$CRON_SCHEDULE" \
          --uri "https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" \
          --http-method POST \
          --oauth-service-account-email "$SA_EMAIL" \
          --quiet
    else
        gcloud scheduler jobs create http "$SCHEDULER_NAME" \
          --location "$REGION" \
          --schedule "$CRON_SCHEDULE" \
          --uri "https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" \
          --http-method POST \
          --oauth-service-account-email "$SA_EMAIL" \
          --quiet
    fi
    echo "Schedule configured successfully."
fi

echo ""
echo "======================================================"
echo "                 Deployment Complete!"
echo "======================================================"
echo "You can manually test the job by running:"
echo "  gcloud run jobs execute $JOB_NAME --region $REGION"
echo "======================================================"
