# GAM Automation via Cloud Run Jobs

> [!IMPORTANT]
> **IMPORTANT DISCLAIMER:** This solution offers a recommended approach that is not exhaustive and is not intended as a final enterprise-ready solution. Customers should consult their Dev, security, and networking teams before deployment.

This guide provides step-by-step instructions for taking an existing, manually run GAM command from Cloud Shell and automating it using Google Cloud Run Jobs and Cloud Scheduler.

## How the Deployment Script (`deploy.sh`) Works
The provided `deploy.sh` script fully automates the creation of a secure, serverless architecture in Google Cloud. When executed, it performs the following steps:
1. **Enables APIs:** Turns on all required Google Cloud APIs (Cloud Run, Cloud Build, Secret Manager, Cloud Scheduler, Artifact Registry).
2. **Creates Secrets:** Uploads your local GAM credential files into Google Cloud Secret Manager so they are never hardcoded in the codebase.
3. **Provisions IAM Permissions:** Grants the necessary `secretAccessor` and build permissions to the compute service account.
4. **Builds the Container:** Uses Cloud Build to package the GAM installation into a Docker image and pushes it to Artifact Registry.
5. **Deploys Cloud Run:** Creates or updates a Cloud Run Job, configuring it to securely mount the Secret Manager credentials into the container's memory at runtime.
6. **Schedules the Job:** Creates a Cloud Scheduler HTTP trigger to automatically wake up the Cloud Run Job at a recurring schedule (e.g., every morning).

## What You Should Edit
Before deploying, you must customize a few lines of code to fit your specific use case.

### 1. Customize Your GAM Command (`run.sh`)
Open the `run.sh` file. This script is what will be executed **inside** the cloud container every day.
- Locate the line containing `gam info domain` at the bottom.
- Replace this with the exact command your team runs manually every day (e.g., `gam print users > users.csv`, or your license assignment script).

### 2. Configure the Execution Timeout (`deploy.sh`)
To protect against infinite loops consuming your cloud budget, the Cloud Run Job is configured with a strict execution time limit.
- Open `deploy.sh`.
- Locate the `--task-timeout 10m` parameter in the Cloud Run deployment command.
- If your GAM script takes longer than 10 minutes to run, increase this limit (e.g., `30m` or `1h`).

---

## Prerequisites
- A Google Cloud Project with Billing enabled.
- The **Cloud Run Admin**, **Cloud Build Editor**, **Cloud Scheduler Admin**, and **Secret Manager Admin** roles assigned to your user account.
- Your existing working GAM setup in Cloud Shell.
- **Execution Environment:** You can run this deployment process directly in **Google Cloud Shell** (by uploading this folder to it) OR on your **local machine**, provided you have the Google Cloud CLI (`gcloud`) installed and authenticated. 
- **Automated CLI:** All required `gcloud` infrastructure commands have been fully encapsulated and automated inside the `deploy.sh` script, so you do not need to run them manually.

---

## Step 1: Extract Existing GAM Credentials
Since GAM is already working in your Cloud Shell, we do not need to re-authorize GAM or create a new GCP project for it. We will simply use your existing credentials.

You will need to locate up to three files depending on your GAM setup (usually in `~/.gam`):
1. `client_secrets.json`: The API project credentials.
2. `oauth2.txt`: The Client authorization tokens.
3. `oauth2service.json`: The Service Account authorization tokens.

**Action:** Download these files from your Cloud Shell to your local machine, and place them securely in the same directory as this guide. 
*(Note: These files will **not** be baked into the Docker image. The deployment script will securely upload them to Google Cloud Secret Manager).*

---

## Step 2: Deploy the Automation
1. Open your terminal in this directory.
2. Make the deployment script executable:
   ```bash
   chmod +x deploy.sh
   ```
3. Run the script:
   ```bash
   ./deploy.sh
   ```
4. Follow the on-screen prompts. The script will ask for your Project ID, preferred region, and scheduling details.

---

## Architecture Security
- **Secret Manager:** Your credentials are automatically uploaded to Google Cloud Secret Manager and securely mounted into the Cloud Run Job at runtime. They are never stored in the Docker image.
- **In-Memory Execution:** The secrets are mounted into an ephemeral, temporary folder inside the container and are destroyed the millisecond the execution finishes.
- **Enterprise-Grade Tip:** By default, this setup uses the Compute Engine Default Service Account. For ultimate enterprise-grade security and adherence to the Principle of Least Privilege, you can manually create a Custom Service Account specifically for this automation, grant it only the `secretAccessor` role, and specify it using `--service-account` in the `gcloud run jobs create` command.

---

## Cost & Free Tier Analysis

> [!TIP]
> **IMPORTANT COST DISCLAIMER:** While this automation is designed to fit entirely within Google Cloud's free tier, you should always oversee your billing dashboard and consult with your Cloud FinOps or Dev team to monitor usage.

Google Cloud Run Jobs features a generous perpetual free tier that includes **180,000 vCPU-seconds** and **360,000 GB-seconds** per month.

Since this architecture provisions exactly 1 vCPU and 512MB of RAM, the primary bottleneck is the vCPU limit. Mathematically, 180,000 seconds per month allows your job to execute for approximately **6,000 seconds (1 hour and 40 minutes) every single day** without incurring any compute charges. As long as your GAM command takes less than 1 hour and 40 minutes to finish daily, your compute cost will be $0.00.
