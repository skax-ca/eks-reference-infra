#!/usr/bin/env bash
# argocd-tunnel-connect 로 연 hub ArgoCD 터널을 해제한다 — 로컬 watchdog·SSM 세션·
# 원격 kubectl port-forward watchdog 을 전부 정리한다.
set -uo pipefail

AWS_PROFILE_NAME="team"
REGION="ap-northeast-2"

# connect.sh가 쓴 상태 폴더를 그대로 읽는다(짝 스킬 argocd-tunnel-connect 밑의 .state/,
# 전용 상태 폴더를 쓰는 이유는 connect.sh 쪽 주석 참고).
STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/argocd-tunnel-connect/.state"
PID_FILE="$STATE_DIR/local-watchdog.pid"
INSTANCE_FILE="$STATE_DIR/instance-id.txt"
PORT_FILE="$STATE_DIR/local-port.txt"

if [[ ! -f "$PID_FILE" ]]; then
  echo "NOT_CONNECTED (state 없음 — 이미 해제됐거나 이 스킬로 연 적이 없다)"
  exit 0
fi

LOCAL_PID=$(cat "$PID_FILE")
INSTANCE_ID=$(cat "$INSTANCE_FILE" 2>/dev/null || echo "")
LOCAL_PORT=$(cat "$PORT_FILE" 2>/dev/null || echo "8080")

# ── 1) 로컬 watchdog(+ 그 자식 aws ssm start-session) 종료 ──
if kill -0 "$LOCAL_PID" 2>/dev/null; then
  pkill -P "$LOCAL_PID" 2>/dev/null || true
  kill "$LOCAL_PID" 2>/dev/null || true
fi
# 고아로 남았을 수 있는 세션도 포트 기준으로 정리
pkill -f "localPortNumber.*$LOCAL_PORT" 2>/dev/null || true

# ── 2) 원격 kubectl port-forward watchdog 종료 ──
# pkill -f 패턴이 kubectl 프로세스뿐 아니라, 같은 문자열을 argv 에 담고 있는
# 바깥 watchdog(while 루프) bash 프로세스까지 함께 잡는다 — 별도 마커가 필요 없다.
if [[ -n "$INSTANCE_ID" ]]; then
  if ! aws ssm send-command --profile "$AWS_PROFILE_NAME" --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["pkill -f \"kubectl port-forward -n argocd svc/argocd-server\" 2>/dev/null; echo STOPPED"]' \
    --query 'Command.CommandId' --output text > /dev/null 2>&1; then
    echo "WARNING: 원격 정리 명령 전송 실패 (인스턴스가 이미 종료됐을 수 있다)" >&2
  fi
fi

rm -f "$PID_FILE" "$INSTANCE_FILE" "$PORT_FILE"

sleep 1
if curl -sk -o /dev/null --max-time 3 "https://localhost:$LOCAL_PORT/" 2>/dev/null; then
  echo "WARNING: 로컬 포트 $LOCAL_PORT 가 여전히 응답한다 — 수동 확인: lsof -i :$LOCAL_PORT" >&2
fi

echo "DISCONNECTED port=$LOCAL_PORT instance=$INSTANCE_ID"
