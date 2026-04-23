#!/bin/bash -
#title          :entrypoint.sh
#description    :This script build image with multiple option and push the image to Google Container Registry.
#author         :step-security
#date           :20200703
#version        :2.0.1
#usage          :./entrypoint.sh
#notes          :Required env values are: INPUT_REGISTRY,INPUT_PROJECT_ID,INPUT_IMAGE_NAME
#                Optional env values are: INPUT_GCLOUD_SERVICE_KEY,INPUT_IMAGE_TAG,INPUT_DOCKERFILE,INPUT_TARGET,INPUT_CONTEXT,INPUT_BUILD_ARGS
#bash_version   :5.0.17(1)-release
###################################################

REPO_PRIVATE=$(jq -r '.repository.private | tostring' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
UPSTREAM="RafikFarhad/push-to-gcr-github-action"
ACTION_REPO="${GITHUB_ACTION_REPOSITORY:-}"
DOCS_URL="https://docs.stepsecurity.io/actions/stepsecurity-maintained-actions"

echo ""
echo -e "\033[1;36mStepSecurity Maintained Action\033[0m"
echo "Secure drop-in replacement for $UPSTREAM"
if [ "$REPO_PRIVATE" = "false" ]; then
  echo -e "\033[32m✓ Free for public repositories\033[0m"
fi
echo -e "\033[36mLearn more:\033[0m $DOCS_URL"
echo ""

if [ "$REPO_PRIVATE" != "false" ]; then
  SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"

  if [ "$SERVER_URL" != "https://github.com" ]; then
    BODY=$(printf '{"action":"%s","ghes_server":"%s"}' "$ACTION_REPO" "$SERVER_URL")
  else
    BODY=$(printf '{"action":"%s"}' "$ACTION_REPO")
  fi

  API_URL="https://agent.api.stepsecurity.io/v1/github/$GITHUB_REPOSITORY/actions/maintained-actions-subscription"

  RESPONSE=$(curl --max-time 3 -s -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$API_URL" -o /dev/null) && CURL_EXIT_CODE=0 || CURL_EXIT_CODE=$?

  if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "Timeout or API not reachable. Continuing to next step."
  elif [ "$RESPONSE" = "403" ]; then
    echo -e "::error::\033[1;31mThis action requires a StepSecurity subscription for private repositories.\033[0m"
    echo -e "::error::\033[31mLearn how to enable a subscription: $DOCS_URL\033[0m"
    exit 1
  fi
fi

ALL_IMAGE_TAG=()

# detect service_account json flavour
if [ "$GOOGLE_APPLICATION_CREDENTIALS" ] && ls "$GOOGLE_APPLICATION_CREDENTIALS"; then
    # workload identity
    echo "Workload identity found ..."
    cp $GOOGLE_APPLICATION_CREDENTIALS /tmp/key.json
else
    if [ -z "$INPUT_GCLOUD_SERVICE_KEY" ]; then
        echo "GCLOUD_SERVICE_KEY is a required field when workload identity is not used. Exiting ..."
        exit 1
    fi
    # parsing service account json
    if echo "$INPUT_GCLOUD_SERVICE_KEY" | python3 -m base64 -d >/tmp/key.json 2>/dev/null && python3 -m json.tool /tmp/key.json >/dev/null 2>&1; then
        echo "Successfully decoded from base64"
    elif echo "$INPUT_GCLOUD_SERVICE_KEY" >/tmp/key.json && python3 -m json.tool /tmp/key.json >/dev/null 2>&1; then
        echo "Using plain text service account JSON"
    else
        echo "Failed to get gcloud_service_key. It must be valid JSON, either plain text or base64 encoded"
        exit 1
    fi
fi

if ! gcloud auth login --cred-file=/tmp/key.json --quiet; then
    echo "Unable to login to gcloud. Exiting ..."
    exit 1
fi

if gcloud auth configure-docker $INPUT_REGISTRY --quiet; then
    echo "Authentication successful to $INPUT_REGISTRY ..."
else
    echo "Docker login failed. Exiting ..."
    exit 1
fi

# split -> trim -> compact -> uniq -> bash array
ALL_IMAGE_TAG=($(python3 -c "print(' '.join(list(set([v for v in [v.strip() for v in '$INPUT_IMAGE_TAG'.split(',')] if v]))))"))

# default to 'latest' when $ALL_IMAGE_TAG is empty
if [ ${#ALL_IMAGE_TAG[@]} -eq 0 ] ; then
    echo "INPUT_IMAGE_TAG tag is not parsable. Using latest by default"
    ALL_IMAGE_TAG=(latest)
fi

TEMP_IMAGE_NAME="$INPUT_IMAGE_NAME:temporary"

if [ "$INPUT_PUSH_ONLY" = true ]; then
    echo "Skipping image build ..."
    TEMP_IMAGE_NAME="$INPUT_REGISTRY/$INPUT_PROJECT_ID/$INPUT_IMAGE_NAME:$ALL_IMAGE_TAG[0]"
else
    echo "Building image ..."
    [ -z $INPUT_TARGET ] && TARGET_ARG="" || TARGET_ARG="--target $INPUT_TARGET"
    [ -z $INPUT_DOCKERFILE ] && FILE_ARG="" || FILE_ARG="--file $INPUT_DOCKERFILE"

    if [ ! -z "$INPUT_BUILD_ARGS" ]; then
        for ARG in $(echo "$INPUT_BUILD_ARGS" | tr ',' '\n'); do
            BUILD_PARAMS="$BUILD_PARAMS --build-arg ${ARG}"
        done
    fi

    echo "docker build $BUILD_PARAMS $TARGET_ARG -t $TEMP_IMAGE_NAME $FILE_ARG $INPUT_CONTEXT"

    if docker build $BUILD_PARAMS $TARGET_ARG -t $TEMP_IMAGE_NAME $FILE_ARG $INPUT_CONTEXT; then
        echo "Image built ..."
    else
        echo "Image building failed. Exiting ..."
        exit 1
    fi
fi

for IMAGE_TAG in ${ALL_IMAGE_TAG[@]}; do

    IMAGE_NAME="$INPUT_REGISTRY/$INPUT_PROJECT_ID/$INPUT_IMAGE_NAME:$IMAGE_TAG"

    echo "Fully qualified image name: $IMAGE_NAME"

    echo "Creating docker tag ..."

    docker tag $TEMP_IMAGE_NAME $IMAGE_NAME

    echo "Pushing image $IMAGE_NAME ..."

    if ! docker push $IMAGE_NAME; then
        echo "Pushing failed. Exiting ..."
        exit 1
    else
        echo "Image pushed."
    fi
done

echo "Process complete."
