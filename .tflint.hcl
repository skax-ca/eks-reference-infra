# tflint 설정 — 컨벤션·provider 오류 정적 검사 (로컬 게이트 + CI)
# 실행: tflint --init (플러그인 설치) → tflint --recursive
#
# ⚠️ 버전 핀을 iac-module-library 와 **같게 유지한다**(aws 0.48.0).
# 다르면 같은 코드에서 다른 지적이 나와 "모듈 repo는 통과했는데 여기서 막힌다"가 된다.

plugin "terraform" {
  enabled = true
  preset  = "recommended" # 미사용 선언·deprecated 문법·네이밍 컨벤션 등
}

plugin "aws" {
  enabled = true
  version = "0.48.0" # 정확 핀 (CLAUDE.md 버전 핀 규칙)
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
