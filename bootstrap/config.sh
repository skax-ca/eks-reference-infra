#!/usr/bin/env bash
# 부트스트랩 기대 상태. bootstrap.sh와 verify.sh가 공유한다.
#
# ⚠️ 이 파일이 "기대 상태"의 코드 측면이고 README.md의 표가 문서 측면이다. 둘이 어긋나면
#    README를 고친다. 사람이 읽는 쪽이 SSOT다.
# ⛔ 실행 Role은 신설한 것만 쓴다. AWSAFTExecution 같은 남의 Role을 공용 계정에서 건드리지 않는다.
#
# hub-spoke 토폴로지: team 계정은 hub의 영구 거처다(단일, 고정). spoke는 새 네이밍 토큰이 아니라
# 역할(허브가 아닌 클러스터군)이고 그 아래 여러 환경/서비스가 붙을 수 있어야 하므로, spoke 쪽
# 네이밍은 고정 상수가 아니라 SPOKE_ENV(기본값 "dev")로 매개변수화한다. 다음 spoke 인스턴스(예:
# stage)를 추가할 때 이 파일을 고치지 않고 SPOKE_ENV=<이름>만 바꿔 같은 스크립트를 재사용한다.
# hub는 계정마다 정확히 하나뿐이라 고정 상수로 남긴다.

# 이 파일은 source 되는 설정이다. 여기서 정의한 값을 쓰는 쪽은 bootstrap.sh·verify.sh 이고
# 검사기는 한 파일만 보므로 전부 미사용으로 보인다. export 로 바꿔 회피하지 않는다.
# shellcheck disable=SC2034

set -euo pipefail

# ⚠️ bash 전용이다. 아래 배열 인덱싱이 0-based를 전제한다(zsh는 1-based). zsh에서
#    source ./config.sh 하면 find_bucket이 조용히 깨진다.
# source 된 경우 return 이, 직접 실행이면 exit 이 쓰인다. 둘 중 하나는 늘 도달하지 않는다.
# shellcheck disable=SC2317
[[ -n "${BASH_VERSION:-}" ]] || {
  echo "ERROR: bash 로 실행해야 한다 (현재 셸은 bash 가 아니다). 예: bash -c 'source ./config.sh; ...'" >&2
  return 1 2>/dev/null || exit 1
}

# 대상
export AWS_PROFILE="${AWS_PROFILE:-team}"
readonly REGION="ap-northeast-2"

# ⛔ 계정 ID는 git에 두지 않는다. 기본값을 주지 않는 것이 핵심이다. 미설정이면 여기서 즉시
#    중단하므로 assert_account의 대조와 oidc_arn()·role_arn()의 ARN 조립이 유지되고, 실행자가
#    어느 계정에 도는지 매번 명시하게 된다. 공용 계정에서는 그 자체가 방어다.
# ⛔ 해시로 저장해 비교하지 않는다. 계정 ID 공간이 10^12뿐이라 노트북으로도 전수 해싱이
#    가능해 해시가 보호가 되지 않는다.
#    사용: EXPECTED_ACCOUNT=<12자리> bash bootstrap/bootstrap.sh (값은 AWS 계정 관리자에게 확인)
# ⚠️ : "${VAR:?msg}"를 쓰지 않는다. 그 형식은 bash 기본 exit 1을 내는데 verify.sh의 계약은
#    0=일치 / 1=drift / 2=실행 불가다. 미설정은 drift가 아니라 실행 불가이므로 2로 끝나야 한다.
#    exit 1이 나면 CI가 "drift 있음"으로 오판한다.
[[ -n "${EXPECTED_ACCOUNT:-}" ]] || {
  echo "ERROR: EXPECTED_ACCOUNT 가 설정되지 않았다. 어느 계정에 부트스트랩할지 명시할 것." >&2
  echo "       예: EXPECTED_ACCOUNT=123456789012 bash bootstrap/bootstrap.sh" >&2
  echo "       공용 계정이므로 기본값을 두지 않는다. 값은 AWS 계정 관리자에게 확인한다." >&2
  exit 2
}

# 오타로 엉뚱한 계정을 기대하게 되는 것을 조기에 잡는다.
[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] || {
  echo "ERROR: EXPECTED_ACCOUNT 는 12자리 숫자여야 한다 (받은 값의 길이: ${#EXPECTED_ACCOUNT})" >&2
  exit 2
}
readonly EXPECTED_ACCOUNT

# 네이밍 토큰(iac-module-library docs/conventions.md 「네이밍과 태깅」)
readonly WORKLOAD="demo"
readonly REGION_CODE="an2"

# hub(단일, 고정)
readonly HUB_ENV="hub"
readonly HUB_BUCKET_PREFIX="s3-${WORKLOAD}-${HUB_ENV}-${REGION_CODE}-tfstate-"
readonly HUB_ENTRY_ROLE="iamr-${WORKLOAD}-${HUB_ENV}-${REGION_CODE}-gha-entry-01"
readonly HUB_EXEC_ROLE="iamr-${WORKLOAD}-${HUB_ENV}-${REGION_CODE}-gha-exec-01"
readonly HUB_ENTRY_POLICY="${HUB_ENTRY_ROLE}-policy"

# spoke(다수). SPOKE_ENV로 인스턴스를 고른다.
# ⚠️ 이 값이 곧 그 spoke 인스턴스의 계정 안에서 쓰일 env 토큰이다. 새 spoke를 부트스트랩할
#    때는 이 파일을 고치지 말고 SPOKE_ENV=<이름>으로 넘긴다.
readonly SPOKE_ENV="${SPOKE_ENV:-dev}"
readonly SPOKE_BUCKET_PREFIX="s3-${WORKLOAD}-${SPOKE_ENV}-${REGION_CODE}-tfstate-"
readonly SPOKE_ENTRY_ROLE="iamr-${WORKLOAD}-${SPOKE_ENV}-${REGION_CODE}-gha-entry-01"
readonly SPOKE_EXEC_ROLE="iamr-${WORKLOAD}-${SPOKE_ENV}-${REGION_CODE}-gha-exec-01"
readonly SPOKE_ENTRY_POLICY="${SPOKE_ENTRY_ROLE}-policy"

# Role description. 정책 문서처럼 생성(create-role)과 비교(check_role_description) 양쪽이 같은
# 문자열을 쓴다. create-role은 description을 생성 시점에만 받으므로, 여기 값을 바꾸면 이미 있는
# Role은 bootstrap.sh의 update-role 수렴 단계가 따라잡는다.
# ⚠️ IAM --description은 tab/LF/CR + U+0020~U+007E + U+00A1~U+00FF만 받는다. 한글을 넣으면
#    ValidationError다. 주석은 한글이어도 description은 영문으로 쓴다.
readonly HUB_ENTRY_DESC="GitHub Actions OIDC entry role (hub). Sole permission is assuming the hub exec role."
readonly HUB_EXEC_DESC="GitHub Actions execution role (hub). Trusts only the entry role, never the OIDC provider directly."
readonly SPOKE_ENTRY_DESC="GitHub Actions OIDC entry role (spoke:${SPOKE_ENV}). Sole permission is assuming the exec role."
readonly SPOKE_EXEC_DESC="GitHub Actions execution role (spoke:${SPOKE_ENV}). Trusts only the entry role, never the OIDC provider directly."

# OIDC provider는 URL당 계정에 1개만 허용된다. hub(team)·spoke(각자 별도 계정)는 서로 다른
# 계정이라 각 계정 안에서 각자 만든다.
readonly OIDC_NAME="iamoidc-${WORKLOAD}-${REGION_CODE}-gha"

# OIDC
readonly OIDC_URL="token.actions.githubusercontent.com"
readonly OIDC_AUD="sts.amazonaws.com"
readonly GH_ORG_ID="310520211"
readonly GH_REPO_ID="1316830050"
readonly SUB_BASE="repo:skax-ca@${GH_ORG_ID}/eks-reference-infra@${GH_REPO_ID}"

# ⛔ 와일드카드로 뭉치지 않는다. org 내 다른 repo가 assume할 수 있게 된다.
# 두 패턴만 쓴다(이 repo 워크플로는 PR 트리거가 없다). SUB_MAIN은 hub·spoke가 값이 같다
# (같은 repo·브랜치. sub는 env가 아니라 ref로 갈린다).
readonly SUB_MAIN="${SUB_BASE}:ref:refs/heads/main"
readonly SUB_ENV_HUB="${SUB_BASE}:environment:${HUB_ENV}"
readonly SUB_ENV_SPOKE="${SUB_BASE}:environment:${SPOKE_ENV}"

# lock 객체 버전 폭증 방어
readonly NONCURRENT_DAYS=7
readonly ABORT_MPU_DAYS=7

# 거버넌스 태그. 이 리소스들은 IaC 밖이라 provider default_tags가 없으므로 스크립트가 직접
# 붙인다. ManagedBy=bootstrap.sh가 "이건 tofu가 관리하지 않는다"는 표시다.
# ⚠️ Environment 태그값은 고정 상수가 아니라 bootstrap.sh가 호출부에서 넘긴다(hub 실행이면
#    HUB_ENV, spoke 실행이면 SPOKE_ENV).
readonly TAG_WORKLOAD="$WORKLOAD"
readonly TAG_MANAGED_BY="bootstrap.sh"
readonly TAG_OWNER="cloud-architect"
readonly TAG_COST_CENTER="internal-poc"

# 출력 헬퍼
readonly C_OK=$'\033[32m'; readonly C_CHG=$'\033[33m'
readonly C_ERR=$'\033[31m'; readonly C_OFF=$'\033[0m'

# ⚠️ 전부 stderr로 보낸다. "로그를 찍으면서 값도 $(...)로 반환"하는 함수(converge_bucket 등)가
#    stdout에 로그를 섞으면 반환값이 로그와 뒤섞여 깨진다.
ok()      { printf '%s  ok%s      %s\n' "$C_OK" "$C_OFF" "$*" >&2; }
changed() { printf '%s changed%s  %s\n' "$C_CHG" "$C_OFF" "$*" >&2; CHANGES=$((CHANGES + 1)); }
mismatch(){ printf '%s  DRIFT%s   %s\n' "$C_ERR" "$C_OFF" "$*" >&2; DRIFTS=$((DRIFTS + 1)); }
die()     { printf '%s  ERROR%s   %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 2; }

# 공통 확인
aws_() { aws --profile "$AWS_PROFILE" --region "$REGION" "$@"; }

assert_account() {
  local actual
  actual="$(aws_ sts get-caller-identity --query Account --output text)" \
    || die "자격증명 없음. AWS_PROFILE=$AWS_PROFILE 확인 (기본값 team)"
  [[ "$actual" == "$EXPECTED_ACCOUNT" ]] \
    || die "계정 불일치: 기대 $EXPECTED_ACCOUNT, 실제 $actual. 공용 계정이므로 중단한다"
}

# state 버킷을 prefix로 찾는다(hub·spoke 공용 헬퍼).
# ⚠️ 버킷명은 git에 없다. "이름을 아는 것"이 아니라 "찾는 것"이 멱등성의 기반이다.
find_bucket_by_prefix() {
  local prefix="$1" found
  found="$(aws_ s3api list-buckets \
    --query "Buckets[?starts_with(Name, \`${prefix}\`)].Name" --output text)"
  # --output text 는 값을 탭으로 흘리므로 단어 분리가 목적이다. 인용하면 버킷 여러 개가
  # 원소 하나로 뭉쳐 아래 개수 판정이 항상 1이 된다.
  # shellcheck disable=SC2206
  local -a names=($found)
  case "${#names[@]}" in
    0) echo "" ;;
    1) echo "${names[0]}" ;;
    *) die "prefix '${prefix}' 버킷이 ${#names[@]}개다: ${names[*]}. 사람이 정리해야 한다" ;;
  esac
}
find_hub_bucket()   { find_bucket_by_prefix "$HUB_BUCKET_PREFIX"; }
find_spoke_bucket() { find_bucket_by_prefix "$SPOKE_BUCKET_PREFIX"; }

account_id() { echo "$EXPECTED_ACCOUNT"; }
oidc_arn()   { echo "arn:aws:iam::${EXPECTED_ACCOUNT}:oidc-provider/${OIDC_URL}"; }
role_arn()   { echo "arn:aws:iam::${EXPECTED_ACCOUNT}:role/$1"; }

# 기대 정책 문서. 생성·비교 양쪽이 같은 것을 쓴다. hub·spoke 같은 형태다.
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

# 입구 Role의 권한은 "실행 Role assume" 하나뿐이다. 넓히지 않는다.
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

# JSON 의미 비교. 키 순서·공백 차이로 가짜 drift가 나지 않게 정규화한다.
json_eq() { [[ "$(jq -cS . <<<"$1")" == "$(jq -cS . <<<"$2")" ]]; }

# 상태 검사. bootstrap.sh(적용 판단)와 verify.sh(drift 감지)가 같은 함수를 쓴다. 두 스크립트가
# 각자 기준을 가지면 "bootstrap은 ok인데 verify는 실패"가 생기고 verify.sh는 소음이 된다.
# 각 check_*는 stdout에 absent | ok | drift 중 하나를 낸다.

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

# 이것이 없으면 lock 객체 버전이 무한히 쌓인다.
check_lifecycle() {
  local b="$1" nd ad
  # JMESPath 식이라 셸이 확장하면 안 된다. 작은따옴표가 목적이다.
  # shellcheck disable=SC2016
  nd="$(aws_ s3api get-bucket-lifecycle-configuration --bucket "$b" \
    --query 'Rules[?Status==`Enabled`].NoncurrentVersionExpiration.NoncurrentDays|[0]' \
    --output text 2>/dev/null || echo None)"
  # shellcheck disable=SC2016  # 위와 같은 이유(JMESPath)
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

# description이 없는 Role은 --output text가 "None"을 내므로 기대값과 달라 drift로 잡힌다.
check_role_description() {
  local role="$1" expected="$2" actual
  actual="$(aws_ iam get-role --role-name "$role" \
    --query 'Role.Description' --output text 2>/dev/null)" || { echo absent; return; }
  [[ "$actual" == "$expected" ]] && echo ok || echo drift
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
