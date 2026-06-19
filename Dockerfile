FROM docker:29.6.0-cli@sha256:d14410ab6f87a2b6c14b7150de787cd7b8bb012a8e900966d6d893e9f7fc49b6

LABEL maintainer="step-security"
LABEL org.opencontainers.image.source=https://github.com/step-security/push-to-gcr-github-action
LABEL org.opencontainers.image.description="A docker image that can build an docker image and push to Google Container Registry or Artifact Repository"
LABEL org.opencontainers.image.licenses=MIT

RUN apk update && \
  apk upgrade && \
  apk add --no-cache bash curl python3 jq
RUN ln -sf python3 /usr/bin/python

RUN curl -sSL https://sdk.cloud.google.com > /tmp/gcl && bash /tmp/gcl --install-dir=/root/gcloud --disable-prompts && \
  rm -rf /root/gcloud/google-cloud-sdk/platform/gsutil/third_party/urllib3/dummyserver/certs/ && \
  rm -f /tmp/gcl

ENV PATH=$PATH:/root/gcloud/google-cloud-sdk/bin

ADD entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
