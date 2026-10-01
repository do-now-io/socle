# Sourced by the `script` steps of chainsaw-test.yaml: the SQS queue in floci
# the scaler watches — what the cluster's objects do not show. Needs
# AWS_ENDPOINT_URL (floci from the runner) and QUEUE.
url="http://localhost:4566/000000000000/$QUEUE"
queue_create() { aws sqs create-queue --queue-name "$QUEUE" > /dev/null; echo "queue $QUEUE created"; }
queue_fill() {  # queue_fill <n>
  for i in $(seq 1 "$1"); do aws sqs send-message --queue-url "$url" --message-body "job-$i" > /dev/null; done
  echo "$1 messages sent; ApproximateNumberOfMessages=$(aws sqs get-queue-attributes --queue-url "$url" \
    --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)"
}
queue_purge() { aws sqs purge-queue --queue-url "$url"; echo "queue $QUEUE purged"; }
queue_delete() { aws sqs delete-queue --queue-url "$url"; echo "queue $QUEUE deleted"; }
