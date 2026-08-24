#!/usr/bin/env bash
#
# teardown-verify.sh — 철수 후 잔존물 검사 (read-only)
#
# 설계 SSOT: docs/hub-lifecycle.md · docs/spoke-lifecycle.md 「4단계 — 잔존물 검증」(이 repo)
#
# 삭제는 사람이 한다(tofu destroy). 이 스크립트는 지우지 않는다 — 남은 것을 찾을 뿐이다.
#   bootstrap.sh 는 만드는 스크립트라 멱등성이 안전망이지만, teardown 은 그렇지 않다.
#   두 번 돌려도 안전한 게 아니라 한 번만 잘못 돌려도 끝이다. 공용 계정에서는 특히.
#
# 대상 계정이 공용일 수 있으므로 모든 조회를 workload/env 태그로 좁힌다.
#   이름을 눈으로 보고 판단하지 않는다 — 비슷한 이름이 남의 것일 수 있다.
#
# 종료 코드: 0 = 잔존물 없음 / 1 = 잔존물 있음 / 2 = 실행 불가
#
# bash 3.2 호환으로 쓴다(macOS 기본 bash). 연상배열·mapfile 을 쓰지 않는다.

set -Eeuo pipefail

WORKLOAD="${WORKLOAD:-}"
ENVIRONMENT="${ENVIRONMENT:-}"
REGION="${AWS_REGION:-ap-northeast-2}"
PROFILE="${AWS_PROFILE:-}"

usage() {
  cat <<'USAGE'
사용법: WORKLOAD=<code> ENVIRONMENT=<env> [AWS_REGION=..] [AWS_PROFILE=..] ./teardown-verify.sh

  WORKLOAD      워크로드 코드 (예: ref, demo)      필수
  ENVIRONMENT   환경 (예: dev, stg, prd)           필수
  AWS_REGION    기본 ap-northeast-2
  AWS_PROFILE   미지정 시 기본 자격증명

비용이 계속 나는 것부터 순서대로 검사한다. 아무것도 지우지 않는다.
USAGE
}

if [ -z "$WORKLOAD" ] || [ -z "$ENVIRONMENT" ]; then
  usage
  exit 2
fi

command -v aws >/dev/null 2>&1 || { echo "aws CLI 가 없다"; exit 2; }

AWS=(aws --region "$REGION")
[ -n "$PROFILE" ] && AWS=(aws --profile "$PROFILE" --region "$REGION")

if ! "${AWS[@]}" sts get-caller-identity >/dev/null 2>&1; then
  echo "AWS 자격증명으로 호출할 수 없다"
  exit 2
fi

ACCOUNT=$("${AWS[@]}" sts get-caller-identity --query Account --output text)
PATTERN="*${WORKLOAD}-${ENVIRONMENT}*"

echo "계정 ${ACCOUNT} · 리전 ${REGION} · 대상 태그 ${PATTERN}"
echo

FOUND=0

# $1=순위 $2=설명 $3=조회 결과
report() {
  if [ -n "$3" ]; then
    FOUND=1
    printf '  [%s] 남아 있음 — %s\n' "$1" "$2"
    printf '%s\n' "$3" | sed 's/^/        /'
  else
    printf '  [%s] 없음 — %s\n' "$1" "$2"
  fi
}

echo "== 비용이 계속 나는 것 =="

report 1 "NAT Gateway" "$("${AWS[@]}" ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" "Name=tag:Name,Values=$PATTERN" \
  --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || true)"

report 2 "EC2 인스턴스 (Karpenter 고아 노드 포함)" "$("${AWS[@]}" ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running,stopped" "Name=tag:Name,Values=$PATTERN" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType]' --output text 2>/dev/null || true)"

report 3 "EBS 볼륨 (available — 붙어 있지 않아도 과금)" "$("${AWS[@]}" ec2 describe-volumes \
  --filters "Name=status,Values=available" "Name=tag:Name,Values=$PATTERN" \
  --query 'Volumes[].[VolumeId,Size]' --output text 2>/dev/null || true)"

report 4 "Elastic IP (미연결)" "$("${AWS[@]}" ec2 describe-addresses \
  --filters "Name=tag:Name,Values=$PATTERN" \
  --query 'Addresses[?AssociationId==null].PublicIp' --output text 2>/dev/null || true)"

report 5 "로드밸런서" "$("${AWS[@]}" elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, '${WORKLOAD}-${ENVIRONMENT}')].LoadBalancerName" \
  --output text 2>/dev/null || true)"

report 6 "EKS 클러스터 (노드 0대여도 컨트롤 플레인 과금)" "$("${AWS[@]}" eks list-clusters \
  --query "clusters[?contains(@, '${WORKLOAD}-${ENVIRONMENT}')]" --output text 2>/dev/null || true)"

echo
echo "== 과금은 없으나 다음 삭제를 막는 것 =="

report 7 "ENI (available — VPC 삭제를 막는다)" "$("${AWS[@]}" ec2 describe-network-interfaces \
  --filters "Name=status,Values=available" "Name=tag:Name,Values=$PATTERN" \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,Description]' --output text 2>/dev/null || true)"

report 8 "VPC" "$("${AWS[@]}" ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$PATTERN" \
  --query 'Vpcs[].[VpcId,CidrBlock]' --output text 2>/dev/null || true)"

echo
echo "== 보존 요건을 먼저 확인할 것 =="

report 9 "CloudWatch 로그 그룹" "$("${AWS[@]}" logs describe-log-groups \
  --query "logGroups[?contains(logGroupName, '${WORKLOAD}-${ENVIRONMENT}')].logGroupName" \
  --output text 2>/dev/null || true)"

echo
if [ "$FOUND" -eq 0 ]; then
  echo "잔존물 없음."
  exit 0
fi

cat <<'NEXT'

잔존물이 있다. docs/hub-lifecycle.md 또는 docs/spoke-lifecycle.md의 「자주 막히는 지점」을 본다.

주의:
  - Karpenter 가 만든 노드는 NodePool 을 먼저 지웠어야 회수된다.
  - ALB 가 남았다면 ALBC 가 먼저 죽은 것이다. elbv2.k8s.aws/cluster 태그로 특정한다.
  - 태그가 없는 자원은 이 스크립트가 찾지 못한다. 콘솔에서 VPC 기준으로 한 번 더 본다.
NEXT
exit 1
