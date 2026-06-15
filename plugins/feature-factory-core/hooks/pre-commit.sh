#!/usr/bin/env bash
# Block commits that would include sensitive files.

if git diff --cached --name-only \
   | grep -qE '\.(env|key|pem|keystore|jks|p8|p12|mobileprovision)$|secrets\.json|creds\.md|google-services\.json|GoogleService-Info\.plist'; then
  echo "BLOCKED: attempt to commit sensitive files"
  exit 1
fi
