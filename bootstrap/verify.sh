#!/usr/bin/env bash
# drift 감지 (D21 완화책 3) — **read-only**. 아무것도 만들거나 고치지 않는다.
#
# 부트스트랩이 IaC 밖이라 `tofu plan` 이 없다. 이 스크립트가 그 역할을 대신한다.
# 기대 상태는 config.sh 가 bootstrap.sh 와 **공유**한다 — 기준이 갈리면 소음이 된다.
#
# exit 0 = 기대 상태와 일치 / exit 1 = drift / exit 2 = 실행 불가(자격증명·계정 불일치)
#
# ⚠️ 이 스크립트는 **음성 테스트로 증명해야 한다.** 리소스를 일부러 어긋나게 한 뒤
#    exit 1 이 나오는 것을 보지 않으면, "완화책이 있다"는 착각만 남는다.
#    증명 절차는 README.md §4 에 있다.

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./config.sh

DRIFTS=0

report() {  # report <이름> <상태>
  case "$2" in
    ok)     ok "$1" ;;
    absent) mismatch "$1 — 존재하지 않는다" ;;
    drift)  mismatch "$1 — 기대 상태와 다르다" ;;
  esac
}

echo "=== verify (read-only · profile=$AWS_PROFILE) ==="
assert_account

BUCKET="$(find_bucket)"
if [[ -z "$BUCKET" ]]; then
  mismatch "state 버킷 — prefix '${BUCKET_PREFIX}' 로 찾을 수 없다"
else
  ok "state 버킷: $BUCKET"
  report "  버저닝"        "$(check_versioning "$BUCKET")"
  report "  SSE(AES256)"   "$(check_encryption "$BUCKET")"
  report "  퍼블릭 차단"   "$(check_public_access_block "$BUCKET")"
  report "  lifecycle(D29)" "$(check_lifecycle "$BUCKET")"
fi

report "OIDC provider ($OIDC_URL)" "$(check_oidc_provider)"
report "입구 Role 신뢰 정책 ($ENTRY_ROLE)" "$(check_role_trust "$ENTRY_ROLE" "$(entry_trust_policy)")"
report "입구 Role inline 정책"              "$(check_entry_inline_policy)"
report "실행 Role 신뢰 정책 ($EXEC_ROLE)"   "$(check_role_trust "$EXEC_ROLE" "$(exec_trust_policy)")"
report "실행 Role AdministratorAccess"      "$(check_exec_admin_attached)"

echo
if [[ "$DRIFTS" -gt 0 ]]; then
  echo "=== drift ${DRIFTS}건 — bootstrap.sh 를 실행하면 수렴한다 ===" >&2
  exit 1
fi
echo "=== drift 없음 ==="
