#!/usr/bin/env bash
# 부트스트랩 (D21 — IaC 밖). state 버킷 · OIDC provider · 2단 Role 을 만든다.
#
# 멱등: 항목마다 먼저 검사하고 **다를 때만** 적용한다. 두 번째 실행은 changed=0 이어야 한다.
#       그것이 D21 완화책 1의 수용 기준이고, 스크립트가 `apply` 의 수렴 성질을 흉내내는 방식이다.
#
# ⛔ AWSAFTExecution 을 건드리지 않는다(D27-1). update-assume-role-policy 가
#    이 파일에 등장하면 안 된다 — 공용 계정(F13)에서 남의 Role 을 덮어쓰는 일이다.
#
# 사용법:  ./bootstrap.sh          (AWS_PROFILE 기본 team)
#          AWS_PROFILE=other ./bootstrap.sh

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./config.sh

CHANGES=0

# ⚠️ IAM --description 은 tab/LF/CR + U+0020~U+007E + U+00A1~U+00FF 만 받는다(실측).
#    한글을 넣으면 ValidationError 다 — 주석은 한글이어도 description 은 **영문으로 쓴다**.
tag_args_iam() {
  printf 'Key=Name,Value=%s Key=Workload,Value=%s Key=Environment,Value=%s ' \
    "$1" "$TAG_WORKLOAD" "$TAG_ENV"
  printf 'Key=ManagedBy,Value=%s Key=Owner,Value=%s Key=CostCenter,Value=%s' \
    "$TAG_MANAGED_BY" "$TAG_OWNER" "$TAG_COST_CENTER"
}

# ⚠️ IAM 은 eventual consistency 다. 방금 만든 Role 이 다른 신뢰 정책의 principal 로
#    인정되기까지 수 초 걸린다 — 실측: 입구 Role 생성 **직후** 실행 Role 을 만들면
#    "Invalid principal in policy" 가 난다. 존재하는데도 안 보이는 구간이 있다.
#    이 재시도가 없으면 첫 실행은 반드시 실패하고, 두 번째 실행에서만 성공한다
#    (= 멱등성이 실패를 가려주는 상태). 그건 수렴이 아니라 운이다.
create_role_with_retry() {
  local role="$1" trust="$2" desc="$3" attempt=0 err
  while :; do
    if err="$(aws_ iam create-role --role-name "$role" \
                --assume-role-policy-document "$trust" --description "$desc" \
                --tags $(tag_args_iam "$role") 2>&1 >/dev/null)"; then
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

echo "=== 부트스트랩 (profile=$AWS_PROFILE region=$REGION) ==="
assert_account
echo "계정 확인: $EXPECTED_ACCOUNT"
echo

# ── 1. state 버킷 ───────────────────────────────────────────────────────────
BUCKET="$(find_bucket)"
if [[ -z "$BUCKET" ]]; then
  # ⚠️ 버킷명은 git 에 없다(D25). 여기서 생성하고 **출력으로만** 알린다.
  #    AWS 는 예측 불가능한 버킷명을 권장한다(F12).
  BUCKET="${BUCKET_PREFIX}$(openssl rand -hex 6)"
  aws_ s3api create-bucket --bucket "$BUCKET" \
    --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  changed "버킷 생성: $BUCKET"
else
  ok "버킷 존재: $BUCKET"
fi

if [[ "$(check_versioning "$BUCKET")" != ok ]]; then
  aws_ s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  changed "버저닝 활성화"
else ok "버저닝"; fi

if [[ "$(check_encryption "$BUCKET")" != ok ]]; then
  aws_ s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
  changed "SSE(AES256) 설정"
else ok "SSE"; fi

if [[ "$(check_public_access_block "$BUCKET")" != ok ]]; then
  aws_ s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
  changed "퍼블릭 액세스 차단"
else ok "퍼블릭 차단"; fi

# D29 — 버저닝 + use_lockfile 이 lock 객체 버전을 폭증시킨다(F8). 이것이 방어책이다.
if [[ "$(check_lifecycle "$BUCKET")" != ok ]]; then
  aws_ s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
    --lifecycle-configuration "$(lifecycle_config)" >/dev/null
  changed "lifecycle 설정 (비현행 ${NONCURRENT_DAYS}일 · MPU ${ABORT_MPU_DAYS}일)"
else ok "lifecycle"; fi

# 태그는 전체 교체 API 라 매번 같은 값이면 변화가 없다. 조회 비교 없이 적용한다.
aws_ s3api put-bucket-tagging --bucket "$BUCKET" --tagging "TagSet=[
  {Key=Name,Value=$BUCKET},{Key=Workload,Value=$TAG_WORKLOAD},
  {Key=Environment,Value=$TAG_ENV},{Key=ManagedBy,Value=$TAG_MANAGED_BY},
  {Key=Owner,Value=$TAG_OWNER},{Key=CostCenter,Value=$TAG_COST_CENTER}]"
ok "버킷 태그"

# ── 2. OIDC provider ────────────────────────────────────────────────────────
# --thumbprint-list 는 선택이다(CLI 스키마 실측). AWS 는 2023년부터 GitHub 등
# 알려진 IdP 의 인증서를 자체 신뢰 저장소로 검증한다 — 지문을 박아두면 오히려 만료 부채가 된다.
case "$(check_oidc_provider)" in
  absent)
    aws_ iam create-open-id-connect-provider \
      --url "https://${OIDC_URL}" --client-id-list "$OIDC_AUD" \
      --tags $(tag_args_iam "$OIDC_NAME") >/dev/null
    changed "OIDC provider 생성: $OIDC_URL"
    ;;
  drift) die "OIDC provider 의 client-id 가 다르다. 다른 용도일 수 있으니 사람이 확인한다: $(oidc_arn)" ;;
  ok)    ok "OIDC provider" ;;
esac

# ── 3. 입구 Role — 실행 Role 보다 **먼저** 만든다 ───────────────────────────
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
      "GitHub Actions OIDC entry role. Sole permission is assuming the exec role."
    changed "입구 Role 생성: $ENTRY_ROLE"
    ;;
  drift)
    aws_ iam update-assume-role-policy --role-name "$ENTRY_ROLE" \
      --policy-document "$(entry_trust_policy)"
    changed "입구 Role 신뢰 정책 갱신 (sub 3패턴)"
    ;;
  ok) ok "입구 Role 신뢰 정책" ;;
esac

# ── 4. 실행 Role (신설 — D27-1) ─────────────────────────────────────────────
case "$(check_role_trust "$EXEC_ROLE" "$(exec_trust_policy)")" in
  absent)
    create_role_with_retry "$EXEC_ROLE" "$(exec_trust_policy)" \
      "GitHub Actions execution role (D27-1). Replaces AWSAFTExecution for this repo."
    changed "실행 Role 생성: $EXEC_ROLE"
    ;;
  drift)
    aws_ iam update-assume-role-policy --role-name "$EXEC_ROLE" \
      --policy-document "$(exec_trust_policy)"
    changed "실행 Role 신뢰 정책 갱신"
    ;;
  ok) ok "실행 Role 신뢰 정책" ;;
esac

if [[ "$(check_exec_admin_attached)" != ok ]]; then
  aws_ iam attach-role-policy --role-name "$EXEC_ROLE" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
  changed "실행 Role 에 AdministratorAccess 부착"
else ok "실행 Role 권한"; fi

# ── 5. 입구 Role 의 권한 (실행 Role 이 존재한 뒤) ───────────────────────────
if [[ "$(check_entry_inline_policy)" != ok ]]; then
  aws_ iam put-role-policy --role-name "$ENTRY_ROLE" \
    --policy-name "$ENTRY_POLICY" --policy-document "$(entry_permission_policy)"
  changed "입구 Role inline 정책 (실행 Role assume 하나)"
else ok "입구 Role 권한"; fi

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

  GitHub repo 변수  TF_STATE_BUCKET   = $BUCKET
  GitHub repo 변수  AWS_ENTRY_ROLE_ARN = $(role_arn "$ENTRY_ROLE")
  GitHub repo 변수  AWS_EXEC_ROLE_ARN  = $(role_arn "$EXEC_ROLE")

  로컬 backend.hcl (gitignore 됨):
    bucket       = "$BUCKET"
    key          = "dev/networking.tfstate"
    region       = "$REGION"
    use_lockfile = true

  변수 등록:
    gh variable set TF_STATE_BUCKET    -R skax-ca/iac-reference-infra -b '$BUCKET'
    gh variable set AWS_ENTRY_ROLE_ARN -R skax-ca/iac-reference-infra -b '$(role_arn "$ENTRY_ROLE")'
    gh variable set AWS_EXEC_ROLE_ARN  -R skax-ca/iac-reference-infra -b '$(role_arn "$EXEC_ROLE")'

  검증:  ./verify.sh
OUT
