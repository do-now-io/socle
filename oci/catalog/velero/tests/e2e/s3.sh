# Sourced by the `script` steps of chainsaw-test.yaml: what the cluster
# cannot see, the bucket in floci's S3. Needs AWS_ENDPOINT_URL and BUCKET.

# bucket_settings — the bucket exists, versioned, AES256 by default, every
# public access switch on, its lifecycle rule expiring noncurrent versions.
bucket_settings() {
  aws s3api head-bucket --bucket "$BUCKET" || { echo "bucket $BUCKET absent"; return 1; }
  v="$(aws s3api get-bucket-versioning --bucket "$BUCKET" --query Status --output text)"
  [ "$v" = Enabled ] || { echo "versioning is '$v'"; return 1; }
  e="$(aws s3api get-bucket-encryption --bucket "$BUCKET" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
  [ "$e" = AES256 ] || { echo "default encryption is '$e'"; return 1; }
  p="$(aws s3api get-public-access-block --bucket "$BUCKET" \
    --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text)"
  [ "$(echo "$p" | tr -s '[:space:]' ' ' | sed 's/ $//')" = "True True True True" ] || { echo "public access block is '$p'"; return 1; }
  n="$(aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" \
    --query 'Rules[0].NoncurrentVersionExpiration.NoncurrentDays' --output text)"
  [ "$n" = 30 ] || { echo "noncurrent versions expire after '$n' days"; return 1; }
  echo "bucket $BUCKET: versioned, AES256, public access blocked, noncurrent versions expire after 30 days"
}

# bucket_survives — polls 30 s: the bucket must still be there, with what it
# held. Turning the module off never deletes it.
bucket_survives() {
  for _ in $(seq 1 6); do
    aws s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1 || { echo "bucket $BUCKET is gone"; return 1; }
    sleep 5
  done
  echo "bucket $BUCKET still there: $(aws s3api list-objects-v2 --bucket "$BUCKET" --query 'KeyCount' --output text) objects"
}
