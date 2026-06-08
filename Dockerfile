FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl bash xz-utils

WORKDIR /app

# Fetch and install GAM binaries
RUN bash -c "bash <(curl -s -S -L https://gam-shortn.appspot.com/gam-install) -l -d /app" && mv /app/gam* /app/gam

ENV PATH="/app/gam:$PATH"

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

ENTRYPOINT ["/app/run.sh"]
