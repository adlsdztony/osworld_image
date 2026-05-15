#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMI_ID="${1:-}"
OSWORLD_USER="${2:-user}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_INSTANCE_TYPE="${AWS_SMOKE_INSTANCE_TYPE:-g5.xlarge}"
AWS_SSH_USER="${AWS_SMOKE_SSH_USER:-user}"
SSH_PASSWORD="${AWS_SMOKE_SSH_PASSWORD:-${OSWORLD_SSH_PASSWORD:-}}"
SUBNET_ID="${AWS_SMOKE_SUBNET_ID:-}"
SECURITY_GROUP_ID="${AWS_SMOKE_SECURITY_GROUP_ID:-}"
ALLOW_TEMP_NETWORK="${AWS_SMOKE_ALLOW_TEMP_NETWORK:-false}"
BUILD_DIR="$ROOT_DIR/build/aws-smoke"

if [ -z "$AMI_ID" ]; then
  printf 'Usage: scripts/smoke-aws.sh <ami_id> [osworld_user]\n' >&2
  exit 2
fi

for bin in aws ssh scp curl; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing required command for AWS smoke test: %s\n' "$bin" >&2
    exit 1
  }
done
if [ -n "$SSH_PASSWORD" ]; then
  command -v setsid >/dev/null 2>&1 || {
    printf 'Missing required command for password SSH: setsid\n' >&2
    exit 1
  }
fi

mkdir -p "$BUILD_DIR"
resource_name="osworld-smoke-$(date +%Y%m%d%H%M%S)"
key_name=""
key_file=""
instance_id=""
created_sg=""
ASKPASS_DIR=""
ASKPASS=""

cleanup() {
  if [ -n "$instance_id" ]; then
    aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$instance_id" >/dev/null || true
    aws ec2 wait instance-terminated --region "$AWS_REGION" --instance-ids "$instance_id" >/dev/null || true
  fi
  if [ -n "$created_sg" ]; then
    aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$created_sg" >/dev/null || true
  fi
  if [ -n "$key_name" ]; then
    aws ec2 delete-key-pair --region "$AWS_REGION" --key-name "$key_name" >/dev/null 2>&1 || true
  fi
  if [ -n "$key_file" ]; then
    rm -f "$key_file"
  fi
  if [ -n "$ASKPASS_DIR" ]; then
    rm -rf "$ASKPASS_DIR"
  fi
}
trap cleanup EXIT

if [ -n "$SSH_PASSWORD" ]; then
  ASKPASS_DIR="$(mktemp -d)"
  ASKPASS="$ASKPASS_DIR/askpass.sh"
  cat > "$ASKPASS" <<EOF
#!/usr/bin/env sh
printf '%s\n' '$SSH_PASSWORD'
EOF
  chmod 0700 "$ASKPASS"
else
  key_name="$resource_name"
  key_file="$BUILD_DIR/$key_name.pem"
  aws ec2 create-key-pair \
    --region "$AWS_REGION" \
    --key-name "$key_name" \
    --query KeyMaterial \
    --output text > "$key_file"
  chmod 0600 "$key_file"
fi

ssh_cmd() {
  if [ -n "$SSH_PASSWORD" ]; then
    SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=osworld:0 setsid ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=2 \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      "$@"
  else
    ssh -i "$key_file" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=2 \
      "$@"
  fi
}

scp_cmd() {
  if [ -n "$SSH_PASSWORD" ]; then
    SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=osworld:0 setsid scp \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      "$@"
  else
    scp -i "$key_file" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$@"
  fi
}

if [ -z "$SECURITY_GROUP_ID" ]; then
  if [ "$ALLOW_TEMP_NETWORK" != "true" ]; then
    printf 'Set AWS_SMOKE_SECURITY_GROUP_ID or AWS_SMOKE_ALLOW_TEMP_NETWORK=true for smoke launch.\n' >&2
    exit 1
  fi
  if [ -n "$SUBNET_ID" ]; then
    vpc_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --subnet-ids "$SUBNET_ID" --query 'Subnets[0].VpcId' --output text)"
  else
    vpc_id="$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
  fi
  created_sg="$(aws ec2 create-security-group --region "$AWS_REGION" --group-name "$resource_name" --description "$resource_name" --vpc-id "$vpc_id" --query GroupId --output text)"
  caller_cidr="$(curl -fsS https://checkip.amazonaws.com)/32"
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$created_sg" --protocol tcp --port 22 --cidr "$caller_cidr" >/dev/null
  SECURITY_GROUP_ID="$created_sg"
fi

run_args=(
  --region "$AWS_REGION"
  --image-id "$AMI_ID"
  --instance-type "$AWS_INSTANCE_TYPE"
  --security-group-ids "$SECURITY_GROUP_ID"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$resource_name},{Key=Project,Value=osworld},{Key=Purpose,Value=smoke-test}]"
  --query 'Instances[0].InstanceId'
  --output text
)

if [ -n "$key_name" ]; then
  run_args+=(--key-name "$key_name")
fi
if [ -n "$SUBNET_ID" ]; then
  run_args+=(--subnet-id "$SUBNET_ID")
fi

instance_id="$(aws ec2 run-instances "${run_args[@]}")"
aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$instance_id"

public_ip="$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
if [ -z "$public_ip" ] || [ "$public_ip" = "None" ]; then
  public_ip="$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)"
fi

for _ in $(seq 1 120); do
  if ssh_cmd "$AWS_SSH_USER@$public_ip" true >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

scp_cmd "$ROOT_DIR/tests/smoke.sh" "$AWS_SSH_USER@$public_ip:/tmp/osworld-smoke.sh"
if [ -n "$SSH_PASSWORD" ]; then
  ssh_cmd "$AWS_SSH_USER@$public_ip" "sudo -S OSWORLD_USER='$OSWORLD_USER' bash /tmp/osworld-smoke.sh" <<<"$SSH_PASSWORD"
else
  ssh_cmd "$AWS_SSH_USER@$public_ip" "sudo OSWORLD_USER='$OSWORLD_USER' bash /tmp/osworld-smoke.sh"
fi

printf 'AWS smoke passed for %s on instance %s\n' "$AMI_ID" "$instance_id"
