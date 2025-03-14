#!/bin/bash

set -e

if [[ -z "$ORG_NAME" || -z "$GITHUB_TOKEN" || -z "$S3_BUCKET" ]]; then
    echo "Missing required environment variables. Please set ORG_NAME, GITHUB_TOKEN, and S3_BUCKET."
    exit 1
fi

DATE_FOLDER=$(date +%Y-%m-%d)
WORK_DIR=$(mktemp -d)
BACKUP_DIR="$WORK_DIR/$DATE_FOLDER"
mkdir -p "$BACKUP_DIR"

PAGE=1
REPO_LIST=()

while :; do
    RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/orgs/$ORG_NAME/repos?per_page=100&page=$PAGE")

    REPOS=$(echo "$RESPONSE" | jq -r '.[].clone_url')

    if [[ -z "$REPOS" || "$REPOS" == "null" ]]; then
        break
    fi

    REPO_LIST+=($REPOS)
    ((PAGE++))
done

if [[ ${#REPO_LIST[@]} -eq 0 ]]; then
    echo "No repositories found or invalid credentials."
    exit 1
fi

for REPO in "${REPO_LIST[@]}"; do
    REPO_NAME=$(basename -s .git "$REPO")
    git clone "https://$GITHUB_TOKEN@${REPO#https://}" "$BACKUP_DIR/$REPO_NAME"
    zip -r "$BACKUP_DIR/$REPO_NAME.zip" "$BACKUP_DIR/$REPO_NAME"
    rm -rf "$BACKUP_DIR/$REPO_NAME"
done

aws --endpoint-url="$AWS_ENDPOINT_URL" s3 cp "$BACKUP_DIR" "s3://$S3_BUCKET/$DATE_FOLDER/" --recursive

rm -rf "$WORK_DIR"

echo "Backup completed successfully!"