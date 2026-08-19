#!/usr/bin/env bash
# 부트스트랩 (D21 — IaC 밖). state 버킷 · OIDC provider · 2단 Role 을 만든다.
#
# 멱등: 항목마다 먼저 검사하고 **다를 때만** 적용한다. 두 번째 실행은 changed=0 이어야 한다.
#       그것이 D21 완화책 1의 수용 기준이고, 스크립트가 `apply` 의 수렴 성질을 흉내내는 방식이다.
#
# ⛔ AWSAFTExecution 을 건드리지 않는다(D27-1). update-assume-role-policy 가
#    이 파일에 등장하면 안 된다 — 공용 계정(F13)에서 남의 Role 을 덮어쓰는 일이다.
#
# ── 2026-08-19: hub 신설 후 정정 ────────────────────────────────────────────
# dev·hub 는 **별도 소유**다(bucket·entry·exec Role 전부 각자). OIDC provider 만 AWS 제약
# (URL 당 계정에 1개)으로 공유 — 그래서 Name 태그에서 env 토큰을 뺐다(config.sh 참조).
# dev 입구 Role 신뢰 정책에 hub 패턴을 얹었던 이전 시도는 이번 실행으로 되돌아간다.
#
# 사용법:  ./bootstrap.sh          (AWS_PROFILE 기본 team)
#          AWS_PROFILE=other ./bootstrap.sh

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./config.sh

CHANGES=0

# ⚠️ IAM --description 은 tab/LF/CR + U+0020~U+007E + U+00A1~U+00FF 만 받는다(실측).
#    한글을 넣으면 ValidationError 다 — 주석은 한글이어도 description 은 **영문으로 쓴다**.
# env 는 태그 인자다 — dev/hub 자원을 같은 함수로 만들되 Environment 태그는 각자 값을 받는다.
tag_args_iam() {
  local name="$1" env="${2:-$TAG_ENV}"
  printf 'Key=Name,Value=%s Key=Workload,Value=%s Key=Environment,Value=%s ' \
    "$name" "$TAG_WORKLOAD" "$env"
  printf 'Key=ManagedBy,Value=%s Key=Owner,Value=%s Key=CostCenter,Value=%s' \
    "$TAG_MANAGED_BY" "$TAG_OWNER" "$TAG_COST_CENTER"
}

# ⚠️ IAM 은 eventual consistency 다. 방금 만든 Role 이 다른 신뢰 정책의 principal 로
#    인정되기까지 수 초 걸린다 — 실측: 입구 Role 생성 **직후** 실행 Role 을 만들면
#    "Invalid principal in policy" 가 난다. 존재하는데도 안 보이는 구간이 있다.
#    이 재시도가 없으면 첫 실행은 반드시 실패하고, 두 번째 실행에서만 성공한다
#    (= 멱등성이 실패를 가려주는 상태). 그건 수렴이 아니라 운이다.
create_role_with_retry() {
  local role="$1" trust="$2" desc="$3" env="${4:-$TAG_ENV}" attempt=0 err
  while :; do
    if err="$(aws_ iam create-role --role-name "$role" \
                --assume-role-policy-document "$trust" --description "$desc" \
                --tags $(tag_args_iam "$role" "$env") 2>&1 >/dev/null)"; then
      return 0
    fi
    attempt=$((attempt + 1))
    if [[ "$err" != *"Invalid principal"* ]] || (( attempt >= 10 )); then
      die "create-role $role 실패: $err"
    fi
    printf '            … principal 전파 대기 (%d/10)\n' "$attempt"
    sleep 5
  done
}

# state 버킷 하나를 기대 상태로 수렴시킨다(dev·hub 공용 — prefix·env 태그만 다르게 받는다).
converge_bucket() {
  local prefix="$1" env="$2" label="$3" bucket
  bucket="$(find_bucket_by_prefix "$prefix")"
  if [[ -z "$bucket" ]]; then
    # ⚠️ 버킷명은 git 에 없다(D25). 여기서 생성하고 **출력으로만** 알린다.
    #    AWS 는 예측 불가능한 버킷명을 권장한다(F12).
    bucket="${prefix}$(openssl rand -hex 6)"
    aws_ s3api create-bucket --bucket "$bucket" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
    changed "[$label] 버킷 생성: $bucket"
  else
    ok "[$label] 버킷 존재: $bucket"
  fi

  if [[ "$(check_versioning "$bucket")" != ok ]]; then
    aws_ s3api put-bucket-versioning --bucket "$bucket" \
      --versioning-configuration Status=Enabled
    changed "[$label] 버저닝 활성화"
  else ok "[$label] 버저닝"; fi

  if [[ "$(check_encryption "$bucket")" != ok ]]; then
    aws_ s3api put-bucket-encryption --bucket "$bucket" \
      --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
    changed "[$label] SSE(AES256) 설정"
  else ok "[$label] SSE"; fi

  if [[ "$(check_public_access_block "$bucket")" != ok ]]; then
    aws_ s3api put-public-access-block --bucket "$bucket" \
      --public-access-block-configuration \
      'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
    changed "[$label] 퍼블릭 액세스 차단"
  else ok "[$label] 퍼블릭 차단"; fi

  # D29 — 버저닝 + use_lockfile 이 lock 객체 버전을 폭증시킨다(F8). 이것이 방어책이다.
  if [[ "$(check_lifecycle "$bucket")" != ok ]]; then
    aws_ s3api put-bucket-lifecycle-configuration --bucket "$bucket" \
      --lifecycle-configuration "$(lifecycle_config)" >/dev/null
    changed "[$label] lifecycle 설정 (비현행 ${NONCURRENT_DAYS}일 · MPU ${ABORT_MPU_DAYS}일)"
  else ok "[$label] lifecycle"; fi

  # 태그는 전체 교체 API 라 매번 같은 값이면 변화가 없다. 조회 비교 없이 적용한다.
  aws_ s3api put-bucket-tagging --bucket "$bucket" --tagging "TagSet=[
    {Key=Name,Value=$bucket},{Key=Workload,Value=$TAG_WORKLOAD},
    {Key=Environment,Value=$env},{Key=ManagedBy,Value=$TAG_MANAGED_BY},
    {Key=Owner,Value=$TAG_OWNER},{Key=CostCenter,Value=$TAG_COST_CENTER}]"
  ok "[$label] 버킷 태그"

  echo "$bucket"
}

echo "=== 부트스트랩 (profile=$AWS_PROFILE region=$REGION) ==="
assert_account
echo "계정 확인: $EXPECTED_ACCOUNT"
echo

# ── 1. state 버킷 — dev·hub 각자 ────────────────────────────────────────────
BUCKET="$(converge_bucket "$BUCKET_PREFIX" "$TAG_ENV" "dev")"
HUB_BUCKET="$(converge_bucket "$HUB_BUCKET_PREFIX" "$HUB_ENV" "hub")"

# ── 2. OIDC provider — **계정에 1개, dev·hub 공유**(AWS 제약, config.sh 참조) ─
# --thumbprint-list 는 선택이다(CLI 스키마 실측). AWS 는 2023년부터 GitHub 등
# 알려진 IdP 의 인증서를 자체 신뢰 저장소로 검증한다 — 지문을 박아두면 오히려 만료 부채가 된다.
case "$(check_oidc_provider)" in
  absent)
    aws_ iam create-open-id-connect-provider \
      --url "https://${OIDC_URL}" --client-id-list "$OIDC_AUD" \
      --tags $(tag_args_iam "$OIDC_NAME" "shared") >/dev/null
    changed "OIDC provider 생성: $OIDC_URL"
    ;;
  drift) die "OIDC provider 의 client-id 가 다르다. 다른 용도일 수 있으니 사람이 확인한다: $(oidc_arn)" ;;
  ok)    ok "OIDC provider" ;;
esac
# Name 태그는 client-id 와 달리 drift 판정 대상이 아니다(check_oidc_provider 는 aud 만 본다) —
# 매번 갱신해도 무해하다. 2026-08-19: iamoidc-demo-dev-an2-gha → iamoidc-demo-an2-gha(env 토큰 제거).
aws_ iam tag-open-id-connect-provider --open-id-connect-provider-arn "$(oidc_arn)" \
  --tags $(tag_args_iam "$OIDC_NAME" "shared")
ok "OIDC provider 태그(Name=$OIDC_NAME)"

# ── 3. dev 입구/실행 Role ────────────────────────────────────────────────────
# ⚠️ 순서가 자유롭지 않다. IAM 은 신뢰 정책의 principal 이 **실제로 존재하는지 검증**한다
#    (실측: MalformedPolicyDocument "Invalid principal in policy"). ARN 이 결정적이어도
#    아직 없는 Role 을 principal 로 쓸 수 없다 — 계산으로 끊을 수 있다는 가정은 **틀렸다**.
#
# 닭-달걀은 대신 **의존 방향이 한쪽뿐인 3단계**로 푼다:
#    ① 입구 Role   신뢰 = OIDC provider (§2 에서 이미 만들었다)
#    ② 실행 Role   신뢰 = 입구 Role     (①이 존재하므로 통과)
#    ③ 입구 inline 정책  Resource = 실행 Role ARN
#       → Resource 는 principal 이 아니라서 **존재 검증을 받지 않는다.** 그래서 마지막이어도 된다.
case "$(check_role_trust "$ENTRY_ROLE" "$(entry_trust_policy)")" in
  absent)
    create_role_with_retry "$ENTRY_ROLE" "$(entry_trust_policy)" \
      "GitHub Actions OIDC entry role (dev). Sole permission is assuming the exec role." "$TAG_ENV"
    changed "[dev] 입구 Role 생성: $ENTRY_ROLE"
    ;;
  drift)
    aws_ iam update-assume-role-policy --role-name "$ENTRY_ROLE" \
      --policy-document "$(entry_trust_policy)"
    changed "[dev] 입구 Role 신뢰 정책 갱신 (sub 3패턴으로 복원 — hub 패턴 제거)"
    ;;
  ok) ok "[dev] 입구 Role 신뢰 정책" ;;
esac

case "$(check_role_trust "$EXEC_ROLE" "$(exec_trust_policy)")" in
  absent)
    create_role_with_retry "$EXEC_ROLE" "$(exec_trust_policy)" \
      "GitHub Actions execution role (dev, D27-1). Replaces AWSAFTExecution for this repo." "$TAG_ENV"
    changed "[dev] 실행 Role 생성: $EXEC_ROLE"
    ;;
  drift)
    aws_ iam update-assume-role-policy --role-name "$EXEC_ROLE" \
      --policy-document "$(exec_trust_policy)"
    changed "[dev] 실행 Role 신뢰 정책 갱신"
    ;;
  ok) ok "[dev] 실행 Role 신뢰 정책" ;;
esac

if [[ "$(check_exec_admin_attached "$EXEC_ROLE")" != ok ]]; then
  aws_ iam attach-role-policy --role-name "$EXEC_ROLE" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
  changed "[dev] 실행 Role 에 AdministratorAccess 부착"
else ok "[dev] 실행 Role 권한"; fi

if [[ "$(check_entry_inline_policy)" != ok ]]; then
  aws_ iam put-role-policy --role-name "$ENTRY_ROLE" \
    --policy-name "$ENTRY_POLICY" --policy-document "$(entry_permission_policy)"
  changed "[dev] 입구 Role inline 정책 (실행 Role assume 하나)"
else ok "[dev] 입구 Role 권한"; fi

# ── 4. hub 입구/실행 Role (2026-08-19 신설) — dev 와 완전히 별도 ────────────
case "$(check_role_trust "$HUB_ENTRY_ROLE" "$(hub_entry_trust_policy)")" in
  absent)
    create_role_with_retry "$HUB_ENTRY_ROLE" "$(hub_entry_trust_policy)" \
      "GitHub Actions OIDC entry role (hub). Sole permission is assuming the hub exec role." "$HUB_ENV"
    changed "[hub] 입구 Role 생성: $HUB_ENTRY_ROLE"
    ;;
  drift)
    aws_ iam update-assume-role-policy --role-name "$HUB_ENTRY_ROLE" \
      --policy-document "$(hub_entry_trust_policy)"
    changed "[hub] 입구 Role 신뢰 정책 갱신"
    ;;
  ok) ok "[hub] 입구 Role 신뢰 정책" ;;
esac

case "$(check_role_trust "$HUB_EXEC_ROLE" "$(hub_exec_trust_policy)")" in
  absent)
    create_role_with_retry "$HUB_EXEC_ROLE" "$(hub_exec_trust_policy)" \
      "GitHub Actions execution role (hub, D27-1 pattern)." "$HUB_ENV"
    changed "[hub] 실행 Role 생성: $HUB_EXEC_ROLE"
    ;;
  drift)
    aws_ iam update-assume-role-policy --role-name "$HUB_EXEC_ROLE" \
      --policy-document "$(hub_exec_trust_policy)"
    changed "[hub] 실행 Role 신뢰 정책 갱신"
    ;;
  ok) ok "[hub] 실행 Role 신뢰 정책" ;;
esac

if [[ "$(check_exec_admin_attached "$HUB_EXEC_ROLE")" != ok ]]; then
  aws_ iam attach-role-policy --role-name "$HUB_EXEC_ROLE" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
  changed "[hub] 실행 Role 에 AdministratorAccess 부착"
else ok "[hub] 실행 Role 권한"; fi

if [[ "$(check_hub_entry_inline_policy)" != ok ]]; then
  aws_ iam put-role-policy --role-name "$HUB_ENTRY_ROLE" \
    --policy-name "$HUB_ENTRY_POLICY" --policy-document "$(hub_entry_permission_policy)"
  changed "[hub] 입구 Role inline 정책 (hub 실행 Role assume 하나)"
else ok "[hub] 입구 Role 권한"; fi

# ── 결과 ────────────────────────────────────────────────────────────────────
echo
echo "=== 변경 ${CHANGES}건 ==="
if [[ "$CHANGES" -eq 0 ]]; then
  echo "이미 기대 상태다 (멱등 확인)."
fi

cat <<OUT

── 다음 단계에 필요한 값 ────────────────────────────────────────────────────
⚠️ 아래 값은 git 에 커밋하지 않는다(D25 — 계정 식별 정보 일반으로 확장).
   GitHub repo 변수/시크릿과 gitignore 된 backend.hcl 에만 둔다.

  [dev]  GitHub repo 변수  TF_STATE_BUCKET     = $BUCKET
  [dev]  GitHub repo 변수  AWS_ENTRY_ROLE_ARN  = $(role_arn "$ENTRY_ROLE")
  [dev]  GitHub repo 변수  AWS_EXEC_ROLE_ARN   = $(role_arn "$EXEC_ROLE")

  [hub]  GitHub repo 변수  HUB_TF_STATE_BUCKET     = $HUB_BUCKET
  [hub]  GitHub repo 변수  HUB_AWS_ENTRY_ROLE_ARN  = $(role_arn "$HUB_ENTRY_ROLE")
  [hub]  GitHub repo 변수  HUB_AWS_EXEC_ROLE_ARN   = $(role_arn "$HUB_EXEC_ROLE")

  로컬 backend.hcl (각 루트 디렉토리, gitignore 됨):
    live/dev/*      bucket = "$BUCKET"      key = "dev/<root>.tfstate"
    live/hub/*      bucket = "$HUB_BUCKET"  key = "hub/<root>.tfstate"
    region = "$REGION"   use_lockfile = true

  변수 등록:
    gh variable set TF_STATE_BUCKET        -R skax-ca/iac-reference-infra -b '$BUCKET'
    gh variable set AWS_ENTRY_ROLE_ARN     -R skax-ca/iac-reference-infra -b '$(role_arn "$ENTRY_ROLE")'
    gh variable set AWS_EXEC_ROLE_ARN      -R skax-ca/iac-reference-infra -b '$(role_arn "$EXEC_ROLE")'
    gh variable set HUB_TF_STATE_BUCKET    -R skax-ca/iac-reference-infra -b '$HUB_BUCKET'
    gh variable set HUB_AWS_ENTRY_ROLE_ARN -R skax-ca/iac-reference-infra -b '$(role_arn "$HUB_ENTRY_ROLE")'
    gh variable set HUB_AWS_EXEC_ROLE_ARN  -R skax-ca/iac-reference-infra -b '$(role_arn "$HUB_EXEC_ROLE")'

  검증:  ./verify.sh

  ⚠️ hub state 마이그레이션은 이 스크립트의 범위 밖이다 — 기존 버킷의 hub/*.tfstate 를
     새 hub 버킷으로 옮기는 것은 'tofu init -migrate-state' 로 수동 수행한다(README.md 참조).
OUT
