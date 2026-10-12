#!/bin/sh
# Publishes docs/privacy and docs/support (and the root page, if tools/site/index.html exists)
# to https://toret.deepdive.dev.br: a private S3 bucket behind CloudFront. Uses the default AWS
# profile; the bucket and distribution are looked up by name/alias, nothing account-specific is stored.
set -eu
cd "$(dirname "$0")/../.."
REGION=eu-south-1
ACC=$(aws sts get-caller-identity --query Account --output text)
BUCKET="toret-site-$ACC-$REGION"
DIST=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items!=null && contains(Aliases.Items,'toret.deepdive.dev.br')].Id | [0]" --output text)
[ -n "$DIST" ] && [ "$DIST" != "None" ] || { echo "no CloudFront distribution for toret.deepdive.dev.br" >&2; exit 1; }
for page in privacy support; do
  aws s3 cp "docs/$page/index.html" "s3://$BUCKET/$page/index.html" --region "$REGION" \
    --content-type "text/html; charset=utf-8" --cache-control "public, max-age=300"
done
[ -f tools/site/index.html ] && aws s3 cp tools/site/index.html "s3://$BUCKET/index.html" --region "$REGION" \
    --content-type "text/html; charset=utf-8" --cache-control "public, max-age=300"
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" --query Invalidation.Status --output text
