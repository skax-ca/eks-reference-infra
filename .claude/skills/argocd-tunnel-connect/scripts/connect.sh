#!/usr/bin/env bash
# hub ArgoCD 콘솔 접속용 2단 SSM 터널을 연다.
#   로컬 --(SSM port forward)--> hub workbench --(kubectl port-forward)--> argocd-server
# 멱등성: 이미 같은 포트로 정상 연결돼 있으면 아무것도 하지 않고 끝난다.
#         연결이 끊겨 있으면(프로세스 죽음·curl 실패) 정리 후 새로 연결한다.
#
# 사용: scripts/connect.sh [LOCAL_PORT]  (기본 8080)
set -uo pipefail

AWS_PROFILE_NAME="team"
REGION="ap-northeast-2"
LOCAL_PORT="${1:-8080}"

# .claude/skills/argocd-tunnel-connect/scripts/connect.sh 에서 4단계 위 = repo root
STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)/.omc/state/argocd-tunnel"
mkdir -p "$STATE_DIR"
PID_FILE="$STATE_DIR/local-watchdog.pid"
INSTANCE_FILE="$STATE_DIR/instance-id.txt"
PORT_FILE="$STATE_DIR/local-port.txt"
LOG_FILE="$STATE_DIR/local-watchdog.log"

check_healthy() {
  local port="$1"
  curl -sk -o /dev/null -w '%{http_code}' "https://localhost:${port}/" --max-time 5 2>/dev/null | grep -q '^200$'
}

# ── 멱등성 판단 ──────────────────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  OLD_PORT=$(cat "$PORT_FILE" 2>/dev/null || echo "$LOCAL_PORT")
  if kill -0 "$OLD_PID" 2>/dev/null && check_healthy "$OLD_PORT"; then
    echo "ALREADY_CONNECTED port=$OLD_PORT pid=$OLD_PID"
    exit 0
  fi
  # 죽었거나 응답이 없다 — 잔여 프로세스 정리 후 재연결로 진행한다
  kill -- "-$OLD_PID" 2>/dev/null || kill "$OLD_PID" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

# ── 1) hub workbench 동적 탐색 (인스턴스 ID 하드코딩 금지 — 재부트스트랩 시 바뀐다) ──
INSTANCE_ID=$(aws ec2 describe-instances --profile "$AWS_PROFILE_NAME" --region "$REGION" \
  --filters "Name=tag:Name,Values=ec2-demo-hub-an2-workbench-*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  echo "ERROR: hub workbench 인스턴스를 찾지 못했다 (실행 중인지 확인)" >&2
  exit 1
fi

PING=$(aws ssm describe-instance-information --profile "$AWS_PROFILE_NAME" --region "$REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)
if [[ "$PING" != "Online" ]]; then
  echo "ERROR: SSM PingStatus=$PING ($INSTANCE_ID)" >&2
  exit 1
fi

# ── 2) 원격 watchdog — kubectl port-forward 가 끊기면(예: pod 재시작) 자동 재시작 ──
# 셸 안에서 --parameters 를 문자열로 직접 조립하면 REMOTE_CMD 내부의 큰따옴표가 AWS CLI
# shorthand 파서를 깨뜨린다(실측) — python3 json.dumps 로 안전하게 인코딩한다.
REMOTE_CMD='pkill -f "kubectl port-forward -n argocd svc/argocd-server" 2>/dev/null; sleep 1; setsid nohup bash -c "while true; do KUBECONFIG=/root/.kube/config kubectl port-forward -n argocd svc/argocd-server 8080:443 --address 127.0.0.1; sleep 2; done" > /root/argocd-portforward.log 2>&1 < /dev/null & disown; sleep 2; ss -ltnp | grep 8080'
REMOTE_CMD_JSON=$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$REMOTE_CMD")

CMD_ID=$(aws ssm send-command --profile "$AWS_PROFILE_NAME" --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=$REMOTE_CMD_JSON" \
  --query 'Command.CommandId' --output text)

STATUS="Pending"
for _ in $(seq 1 10); do
  sleep 2
  STATUS=$(aws ssm get-command-invocation --profile "$AWS_PROFILE_NAME" --region "$REGION" \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --query 'Status' --output text 2>/dev/null || echo "Pending")
  [[ "$STATUS" == "Success" || "$STATUS" == "Failed" ]] && break
done

if [[ "$STATUS" != "Success" ]]; then
  echo "ERROR: 원격 kubectl port-forward 기동 실패 (status=$STATUS)" >&2
  aws ssm get-command-invocation --profile "$AWS_PROFILE_NAME" --region "$REGION" \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --query 'StandardErrorContent' --output text >&2
  exit 1
fi

# ── 3) 로컬 watchdog — SSM 세션이 끊기면(네트워크·VPN 변경 등) 자동 재연결 ──
(
  while true; do
    aws ssm start-session --profile "$AWS_PROFILE_NAME" --region "$REGION" \
      --target "$INSTANCE_ID" \
      --document-name AWS-StartPortForwardingSession \
      --parameters "{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
    sleep 3
  done
) > "$LOG_FILE" 2>&1 &
LOCAL_PID=$!
disown

echo "$LOCAL_PID" > "$PID_FILE"
echo "$INSTANCE_ID" > "$INSTANCE_FILE"
echo "$LOCAL_PORT" > "$PORT_FILE"

# ── 4) 검증 ──────────────────────────────────────────────────────────────
sleep 5
if check_healthy "$LOCAL_PORT"; then
  echo "CONNECTED port=$LOCAL_PORT instance=$INSTANCE_ID pid=$LOCAL_PID"
else
  echo "WARNING: 터널은 떴지만 https://localhost:$LOCAL_PORT 응답이 아직 없다 — 몇 초 후 다시 확인할 것" >&2
  echo "CONNECTED_UNVERIFIED port=$LOCAL_PORT instance=$INSTANCE_ID pid=$LOCAL_PID"
fi
