#!/usr/bin/env bash
# converge-check.sh: apply 직후 읽기 전용 재-plan으로 수렴을 판정한다. EKS 루트의 apply job이
# 루트 디렉토리에서 부른다.
#
# apply의 exit 0은 실제 반영을 보장하지 않으므로 재-plan의 종료 코드로 수렴을 증명한다. 다만 EKS
# 루트는 workbench 볼륨이 새로 생길 때마다 계정 자동 태거가 볼륨 Name을 인스턴스 Name으로
# 덮어써서, 첫 apply 직후 재-plan에 volume_tags.Name diff가 반드시 한 건 남는다(근거는
# live/<env>/eks/providers.tf의 Name 주석). 다음 apply가 되돌리고 태거는 다시 덮어쓰지 않는다.
# 그 한 건만 경고로 통과시키고, 나머지 diff는 전부 미수렴으로 실패시킨다.
#
# ⛔ 허용 조건을 넓히지 않는다. 조건마다 이유가 있다:
#    · 변경 리소스가 workbench 인스턴스 하나뿐이고 동작이 update다. 다른 변경이 섞이면 태거와
#      무관한 미수렴이 이 경고 뒤에 숨는다.
#    · 바뀐 속성이 volume_tags의 Name 키 하나뿐이다.
#    · 바뀌기 전 볼륨 Name이 인스턴스 Name과 같다. 이것이 태거의 흔적이다. 사람이 콘솔에서
#      이름을 잘못 바꾼 경우는 이 조건에서 걸러진다.
#    · output 변경이 없고 destroy 경로가 아니다. destroy 뒤에는 남은 diff가 하나도 없어야 한다.
# ⚠️ networking·tgw 루트는 볼륨을 만들지 않아 이 스크립트를 쓰지 않는다. 그 루트의 인라인 재-plan과
#    갈라진 것은 의도된 차이다.
#
# 사용법:
#   converge-check.sh [--destroy]         재-plan을 돌려 판정한다(TF_VAR_*는 호출자가 넘긴다)
#   converge-check.sh --judge <plan.json> tofu show -json 출력만으로 판정한다(오프라인 검증용)
#
# 종료 코드: 0 = 수렴(허용된 태거 diff 포함) / 1 = 미수렴 / 2 = 실행 불가(tofu 오류 포함)
# ⚠️ bash 3.2 호환으로 쓴다(macOS 기본 bash). --judge를 노트북에서도 돌리기 때문이다.

set -Eeuo pipefail

readonly WORKBENCH_ADDR='module.workbench.aws_instance.this[0]'

# plan JSON이 허용된 태거 diff 한 건뿐이면 0, 아니면 1.
# no-op만 뺀다. apply 중에 읽히는 data source(read)도 수렴하지 않은 신호라 변경으로 센다.
is_tagger_only_diff() {
  jq -e --arg addr "$WORKBENCH_ADDR" '
    [.resource_changes[]? | select(.change.actions != ["no-op"])] as $rc
    | [(.output_changes // {}) | to_entries[] | select(.value.actions != ["no-op"])] as $oc
    | ($oc | length) == 0
      and ($rc | length) == 1
      and $rc[0].address == $addr
      and $rc[0].change.actions == ["update"]
      and ($rc[0].change.before as $b | $rc[0].change.after as $a
           | ([$b | keys[]] + [$a | keys[]] | unique | map(select($b[.] != $a[.]))) == ["volume_tags"]
             and ($b.volume_tags | del(.Name)) == ($a.volume_tags | del(.Name))
             and $b.volume_tags.Name != null
             and $b.volume_tags.Name == $b.tags.Name)
  ' "$1" >/dev/null
}

judge() {
  local json="$1"
  if is_tagger_only_diff "$json"; then
    echo "::warning::재-plan diff가 workbench 볼륨 Name 한 건뿐이다. 계정 자동 태거가 볼륨 생성 때 덮어쓴 값이고 다음 apply가 되돌린다. 수렴으로 판정한다."
    return 0
  fi
  echo "::error::apply 직후인데 재-plan 이 여전히 변경사항을 보고한다. 일부 리소스가 반영되지 않았을 가능성이 높다. AWS 콘솔/CLI로 실물을 직접 대조할 것."
  return 1
}

command -v jq >/dev/null 2>&1 || { echo "jq 가 없다"; exit 2; }

case "${1:-}" in
  --judge)
    [ -f "${2:-}" ] || { echo "plan JSON 파일이 필요하다: --judge <plan.json>"; exit 2; }
    judge "$2" && exit 0 || exit 1
    ;;
  --destroy) DESTROY=1 ;;
  '') DESTROY=0 ;;
  *) echo "알 수 없는 인자: $1"; exit 2 ;;
esac

command -v tofu >/dev/null 2>&1 || { echo "tofu 가 없다"; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

plan_args=(-no-color -lock-timeout=5m -detailed-exitcode -refresh=true -out="$work/converge.tfplan")
[ "$DESTROY" = 1 ] && plan_args=(-destroy "${plan_args[@]}")

set +e
tofu plan "${plan_args[@]}"
code=$?
set -e

case "$code" in
  0) exit 0 ;;
  2) ;;
  *) echo "::error::재-plan 이 실패했다(종료 코드 $code)."; exit 2 ;;
esac

if [ "$DESTROY" = 1 ]; then
  echo "::error::destroy 직후인데 재-plan 이 남은 리소스를 보고한다. 잔존물을 직접 대조할 것."
  exit 1
fi

tofu show -json "$work/converge.tfplan" > "$work/converge.json"
judge "$work/converge.json" && exit 0 || exit 1
