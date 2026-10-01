# Sourced by the `script` steps of chainsaw-test.yaml: what the cluster
# cannot see, a record in floci's Route 53. Needs AWS_ENDPOINT_URL and ZONE.
zone_id() {
  aws route53 list-hosted-zones-by-name --dns-name "$ZONE" \
    --query "HostedZones[?Name=='$ZONE.'].Id | [0]" --output text
}
# record <name> <type> → the first value of that record set, or empty.
record() {
  aws route53 list-resource-record-sets --hosted-zone-id "$(zone_id)" \
    --query "ResourceRecordSets[?Name=='$1.$ZONE.' && Type=='$2'].ResourceRecords[0].Value | [0]" \
    --output text | sed 's/^None$//'
}
# want <name> <type> <value|absent> — polls up to 3 minutes.
want() {
  got=""
  for _ in $(seq 1 36); do
    got="$(record "$1" "$2")"
    if [ "$3" = absent ]; then
      [ -z "$got" ] && { echo "$1.$ZONE $2: gone"; return 0; }
    else
      case "$got" in *"$3"*) echo "$1.$ZONE $2: $got"; return 0 ;; esac
    fi
    sleep 5
  done
  echo "$1.$ZONE $2 is '$got', expected $3"
  return 1
}
