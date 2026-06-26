FROM docker:29.6.1-cli@sha256:862099ada15c669000bef53aa4cb9d821262829f45b0dda2159ccb276443043b

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
