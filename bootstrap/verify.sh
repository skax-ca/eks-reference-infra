#!/usr/bin/env bash
# drift 감지(read-only). 아무것도 만들거나 고치지 않는다. 부트스트랩이 IaC 밖이라 tofu plan이
# 없고 이 스크립트가 그 역할을 대신한다. 기대 상태는 config.sh가 bootstrap.sh와 공유한다.
#
# exit 0 = 기대 상태와 일치 / exit 1 = drift / exit 2 = 실행 불가(자격증명·계정 불일치)
#
# ⚠️ 이 스크립트는 음성 테스트로 증명해야 한다. 리소스를 일부러 어긋나게 한 뒤 exit 1이
#    나오는 것을 보지 않으면 "완화책이 있다"는 착각만 남는다. 주입·복구 절차는 README.md.
#
# bootstrap.sh와 같은 BOOTSTRAP_TARGET(hub|spoke, 기본 hub)·SPOKE_ENV(기본 dev)로 검사 대상을
# 고른다. hub·spoke는 서로 다른 계정이라 한 AWS_PROFILE로는 한쪽만 볼 수 있다.

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./config.sh

readonly BOOTSTRAP_TARGET="${BOOTSTRAP_TARGET:-hub}"
case "$BOOTSTRAP_TARGET" in
  hub|spoke) ;;
  *) die "BOOTSTRAP_TARGET 은 hub 또는 spoke 여야 한다 (받은 값: $BOOTSTRAP_TARGET)" ;;
esac

DRIFTS=0

report() {  # report <이름> <상태>
  case "$2" in
    ok)     ok "$1" ;;
    absent) mismatch "$1: 존재하지 않는다" ;;
    drift)  mismatch "$1: 기대 상태와 다르다" ;;
  esac
}

verify_bucket() {  # verify_bucket <prefix> <label>
  local prefix="$1" label="$2" bucket
  bucket="$(find_bucket_by_prefix "$prefix")"
  if [[ -z "$bucket" ]]; then
    mismatch "[$label] state 버킷: prefix '${prefix}' 로 찾을 수 없다"
    return
  fi
  ok "[$label] state 버킷: $bucket"
  report "  [$label] 버저닝"         "$(check_versioning "$bucket")"
  report "  [$label] SSE(AES256)"    "$(check_encryption "$bucket")"
  report "  [$label] 퍼블릭 차단"    "$(check_public_access_block "$bucket")"
  report "  [$label] lifecycle" "$(check_lifecycle "$bucket")"
}

echo "=== verify (read-only · target=$BOOTSTRAP_TARGET profile=$AWS_PROFILE) ==="
assert_account

report "OIDC provider ($OIDC_URL)" "$(check_oidc_provider)"

if [[ "$BOOTSTRAP_TARGET" == hub ]]; then
  verify_bucket "$HUB_BUCKET_PREFIX" "hub"

  report "[hub] 입구 Role 신뢰 정책 ($HUB_ENTRY_ROLE)" "$(check_role_trust "$HUB_ENTRY_ROLE" "$(hub_entry_trust_policy)")"
  report "[hub] 입구 Role inline 정책"                  "$(check_hub_entry_inline_policy)"
  report "[hub] 실행 Role 신뢰 정책 ($HUB_EXEC_ROLE)"   "$(check_role_trust "$HUB_EXEC_ROLE" "$(hub_exec_trust_policy)")"
  report "[hub] 실행 Role AdministratorAccess"          "$(check_exec_admin_attached "$HUB_EXEC_ROLE")"
else
  verify_bucket "$SPOKE_BUCKET_PREFIX" "spoke:$SPOKE_ENV"

  report "[spoke:$SPOKE_ENV] 입구 Role 신뢰 정책 ($SPOKE_ENTRY_ROLE)" "$(check_role_trust "$SPOKE_ENTRY_ROLE" "$(spoke_entry_trust_policy)")"
  report "[spoke:$SPOKE_ENV] 입구 Role inline 정책"                    "$(check_spoke_entry_inline_policy)"
  report "[spoke:$SPOKE_ENV] 실행 Role 신뢰 정책 ($SPOKE_EXEC_ROLE)"  "$(check_role_trust "$SPOKE_EXEC_ROLE" "$(spoke_exec_trust_policy)")"
  report "[spoke:$SPOKE_ENV] 실행 Role AdministratorAccess"           "$(check_exec_admin_attached "$SPOKE_EXEC_ROLE")"
fi

echo
if [[ "$DRIFTS" -gt 0 ]]; then
  echo "=== drift ${DRIFTS}건. bootstrap.sh 를 실행하면 수렴한다 ===" >&2
  exit 1
fi
echo "=== drift 없음 ==="
