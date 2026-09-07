#!/usr/bin/env bash
# 부트스트랩 기대 상태 — bootstrap.sh 와 verify.sh 가 공유한다.
#
# ⚠️ 이 파일이 "기대 상태"의 코드 측면이고, README.md 의 표가 문서 측면이다.
#    둘이 어긋나면 README 를 고친다 — 사람이 읽는 쪽이 SSOT 다.
#
# ⛔ AWSAFTExecution 은 이 파일 어디에도 등장하지 않는다. 실행 Role 이
#    신설로 바뀌었고, 공용 계정에서 남의 Role 을 건드리지 않기로 했다.
#
# ── hub-spoke 토폴로지 확정 ──────────────────────────────────────────────────
# 이 계정(team) 은 hub 의 영구 거처다(단일, 고정). dev 는 team 계정을 완전히 떠나
# 별도 계정(asset)으로 옮기며, "spoke" 토폴로지의 **첫 인스턴스**가 된다 — spoke 는
# 새 네이밍 토큰이 아니라 **역할**(허브가 아닌 클러스터군)이고, 그 아래 여러 환경/서비스가
# 붙을 수 있어야 한다. 그래서 spoke 쪽 네이밍은 고정 상수가 아니라 `SPOKE_ENV`(기본값
# "dev")로 매개변수화한다 — 다음 spoke 인스턴스(예: stage, 서비스별 env)를 추가할 때
# 이 파일을 다시 고치지 않고 `SPOKE_ENV=<이름>`만 바꿔 같은 스크립트를 재사용한다.
#
# hub 는 계정마다 정확히 하나뿐이라는 성격상(team 계정의 영구 거처) 고정 상수로 남긴다 —
# spoke 처럼 여러 인스턴스가 필요하지 않다.
#
# team 계정에 남아 있던 옛 dev Role/버킷(iamr-demo-dev-an2-gha-*, s3-demo-dev-an2-tfstate-*)은
# 대상이 사라진 채 orphan 으로 남아 있었다 — bootstrap 스크립트가 아니라 사람이
# 1회성 수동 조치로 정리했다.

set -euo pipefail

# ⚠️ bash 전용이다 — 아래 배열 인덱싱이 0-based 를 전제한다(zsh 는 1-based).
#    사람이 zsh 에서 `source ./config.sh` 하면 find_bucket 이 조용히 깨진다(실측).
[[ -n "${BASH_VERSION:-}" ]] || {
  echo "ERROR: bash 로 실행해야 한다 (현재 셸은 bash 가 아니다). 예: bash -c 'source ./config.sh; ...'" >&2
  return 1 2>/dev/null || exit 1
}

# ── 대상 ────────────────────────────────────────────────────────────────────
export AWS_PROFILE="${AWS_PROFILE:-team}"
readonly REGION="ap-northeast-2"

# ⛔ 계정 ID 는 git 에 두지 않는다(계정 식별 정보 일반).
#    ⚠️ 기본값을 주지 않는 것이 핵심이다. 미설정이면 여기서 **즉시 중단**한다:
#      · 안전장치가 유지된다 — assert_account 가 실제 계정과 대조한다
#      · ARN 조립도 유지된다 — oidc_arn()·role_arn() 이 이 값을 소비한다
#      · 부수 효과로 실행자가 **어느 계정에 도는지 매번 명시**하게 된다.
#        공용 계정에서는 그 자체가 방어다 — 조용히 다른 계정을 치지 않는다.
#
#    ⛔ "해시로 저장해 비교하면 되지 않나"는 **이미 기각된 안**이다.
#       계정 ID 공간이 10^12 뿐이라 노트북으로도 전수 해싱이 가능하다 —
#       해시가 보호가 되지 않는다. 남는 해법은 "값을 밖에서 받는다" 하나다.
#
#    사용: EXPECTED_ACCOUNT=<12자리> bash bootstrap/bootstrap.sh
#          값은 AWS 계정 관리자에게 확인한다.
#
# ⚠️ `: "${VAR:?msg}"` 를 쓰지 않는다. 그 형식은 bash 기본 **exit 1** 을 내는데,
#    verify.sh 의 계약은 `0=일치 / 1=drift / 2=실행 불가` 다 —
#    미설정은 drift 가 아니라 **실행 불가**이므로 2로 끝나야 한다.
#    (실측: `:?` 로 두었더니 exit 1 이 나와 CI 가 "drift 있음"으로 오판할 수 있었다.)
[[ -n "${EXPECTED_ACCOUNT:-}" ]] || {
  echo "ERROR: EXPECTED_ACCOUNT 가 설정되지 않았다 — 어느 계정에 부트스트랩할지 명시할 것." >&2
  echo "       예: EXPECTED_ACCOUNT=123456789012 bash bootstrap/bootstrap.sh" >&2
  echo "       공용 계정이므로 기본값을 두지 않는다. 값은 AWS 계정 관리자에게 확인한다." >&2
  exit 2
}

# 형식 검증 — 오타로 엉뚱한 계정을 기대하게 되는 것을 조기에 잡는다.
[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] || {
  echo "ERROR: EXPECTED_ACCOUNT 는 12자리 숫자여야 한다 (받은 값의 길이: ${#EXPECTED_ACCOUNT})" >&2
  exit 2
}
readonly EXPECTED_ACCOUNT

# ── 네이밍 토큰 (모듈 repo architecture/02) ─────────────────────────────────
readonly WORKLOAD="demo"
readonly REGION_CODE="an2"

# ── hub (단일, 고정 — team 계정의 영구 거처) ────────────────────────────────
readonly HUB_ENV="hub"
readonly HUB_BUCKET_PREFIX="s3-${WORKLOAD}-${HUB_ENV}-${REGION_CODE}-tfstate-"
readonly HUB_ENTRY_ROLE="iamr-${WORKLOAD}-${HUB_ENV}-${REGION_CODE}-gha-entry-01"
readonly HUB_EXEC_ROLE="iamr-${WORKLOAD}-${HUB_ENV}-${REGION_CODE}-gha-exec-01"
readonly HUB_ENTRY_POLICY="${HUB_ENTRY_ROLE}-policy"

# ── spoke (다수 — SPOKE_ENV 로 인스턴스를 고른다, 기본값 "dev") ────────────
# ⚠️ 이 값이 곧 그 spoke 인스턴스의 계정 안에서 쓰일 env 토큰이다. 새 spoke(예: stage,
#    서비스별 env)를 부트스트랩할 때는 이 파일을 고치지 말고 SPOKE_ENV=<이름>으로 넘긴다.
readonly SPOKE_ENV="${SPOKE_ENV:-dev}"
readonly SPOKE_BUCKET_PREFIX="s3-${WORKLOAD}-${SPOKE_ENV}-${REGION_CODE}-tfstate-"
readonly SPOKE_ENTRY_ROLE="iamr-${WORKLOAD}-${SPOKE_ENV}-${REGION_CODE}-gha-entry-01"
readonly SPOKE_EXEC_ROLE="iamr-${WORKLOAD}-${SPOKE_ENV}-${REGION_CODE}-gha-exec-01"
readonly SPOKE_ENTRY_POLICY="${SPOKE_ENTRY_ROLE}-policy"

# OIDC provider 는 URL 당 계정에 1개만 허용된다(AWS 제약). hub(team)·spoke(각자 별도 계정)는
# 서로 다른 계정이라 공유가 애초에 불가능하지도 필요하지도 않다 — 각 계정 안에서 각자 만든다.
readonly OIDC_NAME="iamoidc-${WORKLOAD}-${REGION_CODE}-gha"

# ── OIDC ─────────────────────────────────────────────────────────────────────
readonly OIDC_URL="token.actions.githubusercontent.com"
readonly OIDC_AUD="sts.amazonaws.com"
readonly GH_ORG_ID="310520211"
readonly GH_REPO_ID="1316830050"
readonly SUB_BASE="repo:skax-ca@${GH_ORG_ID}/eks-reference-infra@${GH_REPO_ID}"

# ⛔ 와일드카드로 뭉치지 않는다 — org 내 다른 repo 가 assume 할 수 있게 된다.
# 두 패턴만 쓴다(pull_request 없음) — 이 repo 워크플로는 애초에 PR 트리거가 없다.
# SUB_MAIN 은 hub·spoke 가 **값이 같다**(같은 repo·브랜치 — sub 는 env 가 아니라 ref 로 갈린다).
readonly SUB_MAIN="${SUB_BASE}:ref:refs/heads/main"
readonly SUB_ENV_HUB="${SUB_BASE}:environment:${HUB_ENV}"
readonly SUB_ENV_SPOKE="${SUB_BASE}:environment:${SPOKE_ENV}"

# ── lock 객체 버전 폭증 방어 ─────────────────────────────────────────────────
readonly NONCURRENT_DAYS=7
readonly ABORT_MPU_DAYS=7

# ── 거버넌스 태그 ────────────────────────────────────────────────────────────
# 이 리소스들은 IaC 밖이라 provider default_tags 가 없다 → 스크립트가 직접 붙인다.
# ManagedBy=bootstrap.sh 가 "이건 tofu 가 관리하지 않는다"는 표시다.
# ⚠️ Environment 태그값은 고정 상수가 아니라 bootstrap.sh 가 호출부에서 넘긴다
#    (hub 실행이면 HUB_ENV, spoke 실행이면 SPOKE_ENV) — 대상마다 다르기 때문이다.
readonly TAG_WORKLOAD="$WORKLOAD"
readonly TAG_MANAGED_BY="bootstrap.sh"
readonly TAG_OWNER="cloud-architect"
readonly TAG_COST_CENTER="internal-poc"

# ── 출력 헬퍼 ───────────────────────────────────────────────────────────────
readonly C_OK=$'\033[32m'; readonly C_CHG=$'\033[33m'
readonly C_ERR=$'\033[31m'; readonly C_OFF=$'\033[0m'

# ⚠️ stderr로 보낸다 — mismatch()·die()와 통일. converge_bucket() 처럼 "로그를 찍으면서
#    값도 $(...)로 반환"하는 함수가 생기면, stdout에 섞이는 순간 반환값이 로그와 뒤섞여
#    깨진다(hub 버킷 부트스트랩 때 $BUCKET에 로그 텍스트가 섞여 들어간 전례가 있다).
ok()      { printf '%s  ok%s      %s\n' "$C_OK" "$C_OFF" "$*" >&2; }
changed() { printf '%s changed%s  %s\n' "$C_CHG" "$C_OFF" "$*" >&2; CHANGES=$((CHANGES + 1)); }
mismatch(){ printf '%s  DRIFT%s   %s\n' "$C_ERR" "$C_OFF" "$*" >&2; DRIFTS=$((DRIFTS + 1)); }
die()     { printf '%s  ERROR%s   %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 2; }

# ── 공통 확인 ───────────────────────────────────────────────────────────────
aws_() { aws --profile "$AWS_PROFILE" --region "$REGION" "$@"; }

assert_account() {
  local actual
  actual="$(aws_ sts get-caller-identity --query Account --output text)" \
    || die "자격증명 없음. AWS_PROFILE=$AWS_PROFILE 확인 (기본값 team)"
  [[ "$actual" == "$EXPECTED_ACCOUNT" ]] \
    || die "계정 불일치: 기대 $EXPECTED_ACCOUNT, 실제 $actual — 공용 계정이므로 중단한다"
}

# state 버킷을 prefix 로 찾는다(hub·spoke 공용 헬퍼 — prefix 만 다르게 넘긴다).
# ⚠️ 버킷명은 git 에 없다. 그래서 "이름을 아는 것"이 아니라 "찾는 것"이 멱등성의 기반이다.
find_bucket_by_prefix() {
  local prefix="$1" found
  found="$(aws_ s3api list-buckets \
    --query "Buckets[?starts_with(Name, \`${prefix}\`)].Name" --output text)"
  local -a names=($found)
  case "${#names[@]}" in
    0) echo "" ;;
    1) echo "${names[0]}" ;;
    *) die "prefix '${prefix}' 버킷이 ${#names[@]}개다: ${names[*]} — 사람이 정리해야 한다" ;;
  esac
}
find_hub_bucket()   { find_bucket_by_prefix "$HUB_BUCKET_PREFIX"; }
find_spoke_bucket() { find_bucket_by_prefix "$SPOKE_BUCKET_PREFIX"; }

account_id() { echo "$EXPECTED_ACCOUNT"; }
oidc_arn()   { echo "arn:aws:iam::${EXPECTED_ACCOUNT}:oidc-provider/${OIDC_URL}"; }
role_arn()   { echo "arn:aws:iam::${EXPECTED_ACCOUNT}:role/$1"; }

# ── 기대 정책 문서 (생성·비교 양쪽이 같은 것을 쓴다) — hub·spoke 같은 형태다 ─
hub_entry_trust_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "$(oidc_arn)" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "${OIDC_URL}:aud": "${OIDC_AUD}" },
        "StringLike": {
          "${OIDC_URL}:sub": [
            "${SUB_MAIN}",
            "${SUB_ENV_HUB}"
          ]
        }
      }
    }
  ]
}
JSON
}

hub_exec_trust_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "$(role_arn "$HUB_ENTRY_ROLE")" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
}

# 입구 Role 의 권한은 "실행 Role assume" 하나뿐이다. 넓히지 않는다.
hub_entry_permission_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "$(role_arn "$HUB_EXEC_ROLE")"
    }
  ]
}
JSON
}

spoke_entry_trust_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "$(oidc_arn)" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "${OIDC_URL}:aud": "${OIDC_AUD}" },
        "StringLike": {
          "${OIDC_URL}:sub": [
            "${SUB_MAIN}",
            "${SUB_ENV_SPOKE}"
          ]
        }
      }
    }
  ]
}
JSON
}

spoke_exec_trust_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "$(role_arn "$SPOKE_ENTRY_ROLE")" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
}

spoke_entry_permission_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "$(role_arn "$SPOKE_EXEC_ROLE")"
    }
  ]
}
JSON
}

lifecycle_config() {
  cat <<JSON
{
  "Rules": [
    {
      "ID": "expire-noncurrent-and-abort-mpu",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "NoncurrentVersionExpiration": { "NoncurrentDays": ${NONCURRENT_DAYS} },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": ${ABORT_MPU_DAYS} }
    }
  ]
}
JSON
}

# JSON 의미 비교 — 키 순서·공백 차이로 가짜 drift 가 나지 않게 정규화한다.
json_eq() { [[ "$(jq -cS . <<<"$1")" == "$(jq -cS . <<<"$2")" ]]; }

# ─────────────────────────────────────────────────────────────────────────────
# 상태 검사 — bootstrap.sh(적용 판단)와 verify.sh(drift 감지)가 **같은 함수**를 쓴다.
# 두 스크립트가 각자 기준을 가지면 "bootstrap 은 ok 인데 verify 는 실패"가 생기고,
# 그러면 verify.sh 는 완화책이 아니라 소음이 된다.
#
# 각 check_* 는 stdout 에 absent | ok | drift 중 하나를 낸다.
# ─────────────────────────────────────────────────────────────────────────────

check_versioning() {
  local b="$1" v
  v="$(aws_ s3api get-bucket-versioning --bucket "$b" --query Status --output text 2>/dev/null || echo None)"
  [[ "$v" == "Enabled" ]] && echo ok || echo drift
}

check_encryption() {
  local b="$1" alg
  alg="$(aws_ s3api get-bucket-encryption --bucket "$b" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text 2>/dev/null || echo None)"
  [[ "$alg" == "AES256" ]] && echo ok || echo drift
}

check_public_access_block() {
  local b="$1" cfg
  cfg="$(aws_ s3api get-public-access-block --bucket "$b" \
    --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
    --output text 2>/dev/null || echo none)"
  [[ "$cfg" == $'True\tTrue\tTrue\tTrue' ]] && echo ok || echo drift
}

# 이것이 없으면 lock 객체 버전이 무한히 쌓인다(S3 공식 문서가 경고하는 동작이다).
check_lifecycle() {
  local b="$1" nd ad
  nd="$(aws_ s3api get-bucket-lifecycle-configuration --bucket "$b" \
    --query 'Rules[?Status==`Enabled`].NoncurrentVersionExpiration.NoncurrentDays|[0]' \
    --output text 2>/dev/null || echo None)"
  ad="$(aws_ s3api get-bucket-lifecycle-configuration --bucket "$b" \
    --query 'Rules[?Status==`Enabled`].AbortIncompleteMultipartUpload.DaysAfterInitiation|[0]' \
    --output text 2>/dev/null || echo None)"
  [[ "$nd" == "$NONCURRENT_DAYS" && "$ad" == "$ABORT_MPU_DAYS" ]] && echo ok || echo drift
}

check_oidc_provider() {
  local auds
  auds="$(aws_ iam get-open-id-connect-provider --open-id-connect-provider-arn "$(oidc_arn)" \
    --query 'ClientIDList' --output text 2>/dev/null)" || { echo absent; return; }
  [[ "$auds" == "$OIDC_AUD" ]] && echo ok || echo drift
}

check_role_trust() {
  local role="$1" expected="$2" actual
  actual="$(aws_ iam get-role --role-name "$role" \
    --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null)" || { echo absent; return; }
  json_eq "$actual" "$expected" && echo ok || echo drift
}

check_hub_entry_inline_policy() {
  local actual
  actual="$(aws_ iam get-role-policy --role-name "$HUB_ENTRY_ROLE" --policy-name "$HUB_ENTRY_POLICY" \
    --query 'PolicyDocument' --output json 2>/dev/null)" || { echo absent; return; }
  json_eq "$actual" "$(hub_entry_permission_policy)" && echo ok || echo drift
}

check_spoke_entry_inline_policy() {
  local actual
  actual="$(aws_ iam get-role-policy --role-name "$SPOKE_ENTRY_ROLE" --policy-name "$SPOKE_ENTRY_POLICY" \
    --query 'PolicyDocument' --output json 2>/dev/null)" || { echo absent; return; }
  json_eq "$actual" "$(spoke_entry_permission_policy)" && echo ok || echo drift
}

check_exec_admin_attached() {
  local role="$1" arns
  arns="$(aws_ iam list-attached-role-policies --role-name "$role" \
    --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null)" || { echo absent; return; }
  [[ "$arns" == *"arn:aws:iam::aws:policy/AdministratorAccess"* ]] && echo ok || echo drift
}
