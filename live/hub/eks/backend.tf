# ⛔ 이 블록은 **비어 있어야 한다** — partial backend configuration이다.
#
# 버킷명이 git 에 존재하지 않는 것이 요구사항이다. 근거는 networking 루트의 backend.tf 와
# 동일하다(AWS 공식의 예측 불가능한 버킷명 권장 · 민감정보 비노출 · 이 파일은 고객사 복사 템플릿).
#
# 주입 경로 (둘 다 git 밖):
#   CI    : GitHub repo 변수 → tofu init -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" ...
#   로컬  : gitignore 된 backend.hcl → tofu init -backend-config=backend.hcl
#
# 🔑 **state 키는 networking 과 다르다** — `dev/eks.tfstate`. 같은 버킷 안에서 키로만 갈린다.
#    이 키 분리가 "vpc 와 eks 를 독립적으로 배포·파기"의 물리적 근거다. 두 루트는 서로의 state 를
#    읽지 않는다(결합은 Name/SubnetGroup 태그 data source 로만 — 아래 main.tf).
#
# ⚠️ `bucket = "..."` 를 여기 추가하면 그 순간 위 요구사항이 무너진다. init 실패는 버그가 아니라
#    -backend-config 를 빠뜨렸다는 신호다. 자세한 것은 이 디렉토리의 README.md 를 읽는다.
terraform {
  backend "s3" {}
}
