# Use a lightweight python image
FROM python:3.11-slim

# Install necessary tools
RUN apt-get update && apt-get install -y curl bash xz-utils

# Set working directory
WORKDIR /app

# Download and install GAM
# We use the official installer script
RUN bash -c "bash <(curl -s -S -L https://gam-shortn.appspot.com/gam-install) -l -d /app" && mv /app/gam* /app/gam

# Add GAM to the system PATH so we can call it easily
ENV PATH="/app/gam:$PATH"

# Copy the execution script
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

# Run the script when the container starts
ENTRYPOINT ["/app/run.sh"]
