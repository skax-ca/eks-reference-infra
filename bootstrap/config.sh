#!/usr/bin/env bash
# 부트스트랩 기대 상태 (D21) — bootstrap.sh 와 verify.sh 가 공유한다.
#
# ⚠️ 이 파일이 "기대 상태"의 코드 측면이고, README.md 의 표가 문서 측면이다.
#    둘이 어긋나면 README 를 고친다 — 사람이 읽는 쪽이 SSOT 다(D21 완화책 2).
#
# ⛔ AWSAFTExecution 은 이 파일 어디에도 등장하지 않는다. D27-1 로 실행 Role 이
#    신설로 바뀌었고, 공용 계정(F13)에서 남의 Role 을 건드리지 않기로 했다.

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
readonly EXPECTED_ACCOUNT="533616270150"

# ── 네이밍 토큰 (모듈 repo architecture/02) ─────────────────────────────────
readonly WORKLOAD="ref"       # D24
readonly ENV="dev"
readonly REGION_CODE="an2"

readonly BUCKET_PREFIX="s3-${WORKLOAD}-${ENV}-${REGION_CODE}-tfstate-"
readonly OIDC_NAME="iamoidc-${WORKLOAD}-${ENV}-${REGION_CODE}-gha"
readonly ENTRY_ROLE="iamr-${WORKLOAD}-${ENV}-${REGION_CODE}-gha-entry-01"
readonly EXEC_ROLE="iamr-${WORKLOAD}-${ENV}-${REGION_CODE}-gha-exec-01"
# 종속 객체는 약어를 새로 만들지 않고 부모 이름을 상속한다.
# ⚠️ inline 정책은 tags 미지원 → 이것은 Name 태그가 아니라 name 인자(=식별자)다.
readonly ENTRY_POLICY="${ENTRY_ROLE}-policy"

# ── OIDC (Phase 2 실측 — docs/deployment-facts.md §3) ───────────────────────
readonly OIDC_URL="token.actions.githubusercontent.com"
readonly OIDC_AUD="sts.amazonaws.com"
readonly GH_ORG_ID="310520211"
readonly GH_REPO_ID="1316830050"
readonly SUB_BASE="repo:skax-ca@${GH_ORG_ID}/iac-reference-infra@${GH_REPO_ID}"

# ⚠️ 3패턴이다. environment 를 선언한 job 만 :environment: 를 받는다(D28, 실측).
#    ⛔ 와일드카드로 뭉치지 않는다 — org 내 다른 repo 가 assume 할 수 있게 된다.
readonly SUB_PR="${SUB_BASE}:pull_request"
readonly SUB_MAIN="${SUB_BASE}:ref:refs/heads/main"
readonly SUB_ENV="${SUB_BASE}:environment:dev"

# ── D29: lock 객체 버전 폭증 방어 ───────────────────────────────────────────
readonly NONCURRENT_DAYS=7
readonly ABORT_MPU_DAYS=7

# ── 거버넌스 태그 (architecture/02 §1.1) ────────────────────────────────────
# 이 리소스들은 IaC 밖이라 provider default_tags 가 없다 → 스크립트가 직접 붙인다.
# ManagedBy=bootstrap.sh 가 "이건 tofu 가 관리하지 않는다"는 표시다.
readonly TAG_WORKLOAD="$WORKLOAD"
readonly TAG_ENV="$ENV"
readonly TAG_MANAGED_BY="bootstrap.sh"
readonly TAG_OWNER="cloud-architect"
readonly TAG_COST_CENTER="internal-poc"

# ── 출력 헬퍼 ───────────────────────────────────────────────────────────────
readonly C_OK=$'\033[32m'; readonly C_CHG=$'\033[33m'
readonly C_ERR=$'\033[31m'; readonly C_OFF=$'\033[0m'

ok()      { printf '%s  ok%s      %s\n' "$C_OK" "$C_OFF" "$*"; }
changed() { printf '%s changed%s  %s\n' "$C_CHG" "$C_OFF" "$*"; CHANGES=$((CHANGES + 1)); }
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

# state 버킷을 prefix 로 찾는다.
# ⚠️ 버킷명은 git 에 없다(D25). 그래서 "이름을 아는 것"이 아니라 "찾는 것"이 멱등성의 기반이다.
find_bucket() {
  local found
  found="$(aws_ s3api list-buckets \
    --query "Buckets[?starts_with(Name, \`${BUCKET_PREFIX}\`)].Name" --output text)"
  local -a names=($found)
  case "${#names[@]}" in
    0) echo "" ;;
    1) echo "${names[0]}" ;;
    *) die "prefix '${BUCKET_PREFIX}' 버킷이 ${#names[@]}개다: ${names[*]} — 사람이 정리해야 한다" ;;
  esac
}

account_id() { echo "$EXPECTED_ACCOUNT"; }
oidc_arn()   { echo "arn:aws:iam::${EXPECTED_ACCOUNT}:oidc-provider/${OIDC_URL}"; }
role_arn()   { echo "arn:aws:iam::${EXPECTED_ACCOUNT}:role/$1"; }

# ── 기대 정책 문서 (생성·비교 양쪽이 같은 것을 쓴다) ────────────────────────
entry_trust_policy() {
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
            "${SUB_PR}",
            "${SUB_MAIN}",
            "${SUB_ENV}"
          ]
        }
      }
    }
  ]
}
JSON
}

exec_trust_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "$(role_arn "$ENTRY_ROLE")" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
}

# 입구 Role 의 권한은 "실행 Role assume" 하나뿐이다. 넓히지 않는다.
entry_permission_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "$(role_arn "$EXEC_ROLE")"
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
# 그러면 verify.sh 는 완화책이 아니라 소음이 된다(D21).
#
# 각 check_* 는 stdout 에 absent | ok | drift 중 하나를 낸다.
# ─────────────────────────────────────────────────────────────────────────────

check_bucket_exists() {
  [[ -n "$(find_bucket)" ]] && echo ok || echo absent
}

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

# D29 — 이것이 없으면 lock 객체 버전이 무한히 쌓인다(F8, 공식 경고).
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

check_entry_inline_policy() {
  local actual
  actual="$(aws_ iam get-role-policy --role-name "$ENTRY_ROLE" --policy-name "$ENTRY_POLICY" \
    --query 'PolicyDocument' --output json 2>/dev/null)" || { echo absent; return; }
  json_eq "$actual" "$(entry_permission_policy)" && echo ok || echo drift
}

check_exec_admin_attached() {
  local arns
  arns="$(aws_ iam list-attached-role-policies --role-name "$EXEC_ROLE" \
    --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null)" || { echo absent; return; }
  [[ "$arns" == *"arn:aws:iam::aws:policy/AdministratorAccess"* ]] && echo ok || echo drift
}
