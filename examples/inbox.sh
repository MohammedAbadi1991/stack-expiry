#!/usr/bin/env bash
# Read stack-expiry notices without an email subscription.
#   ./examples/inbox.sh setup   create a queue and subscribe it to the topic
#   ./examples/inbox.sh         print the notices received so far
set -euo pipefail
STACK="${STACK_EXPIRY_STACK:-stack-expiry}"
QUEUE="${STACK}-inbox"

if [ "${1:-}" = "setup" ]; then
  topic=$(aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='TopicArn'].OutputValue" --output text)
  url=$(aws sqs create-queue --queue-name "$QUEUE" --query QueueUrl --output text)
  arn=$(aws sqs get-queue-attributes --queue-url "$url" --attribute-names QueueArn \
    --query Attributes.QueueArn --output text)
  policy="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"$arn\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"$topic\"}}}]}"
  aws sqs set-queue-attributes --queue-url "$url" \
    --attributes "{\"Policy\":\"${policy//\"/\\\"}\"}"
  aws sns subscribe --topic-arn "$topic" --protocol sqs --notification-endpoint "$arn" \
    --attributes RawMessageDelivery=true --query SubscriptionArn --output text
  exit 0
fi

url=$(aws sqs get-queue-url --queue-name "$QUEUE" --query QueueUrl --output text)
for _ in 1 2 3; do
  aws sqs receive-message --queue-url "$url" --max-number-of-messages 10 --wait-time-seconds 1 \
    --visibility-timeout 5 --attribute-names SentTimestamp \
    --query "Messages[].[Attributes.SentTimestamp,Body]" --output text
done | grep -v "^None" | sort -u | cut -f2- | sed "s/^/- /"
