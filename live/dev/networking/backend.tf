# ⛔ 이 블록은 **비어 있어야 한다** — partial backend configuration (design/50 D25).
#
# 버킷명이 git 에 존재하지 않는 것이 D25 의 요구사항이다. 근거 셋:
#   ① AWS 공식이 **예측 불가능한 버킷명**을 권장한다 (스쿼팅 방지)
#   ② AWS 공식이 버킷명에 민감정보를 넣지 말라고 한다 (URL 에 노출된다)
#   ③ 이 파일은 **고객사에 복사해 줄 템플릿**이다 → "private 이라 안 보인다"가 성립하지 않는다
#
# 주입 경로 (둘 다 git 밖):
#   CI    : GitHub repo 변수 → tofu init -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" ...
#   로컬  : gitignore 된 backend.hcl → tofu init -backend-config=backend.hcl
#
# ⚠️ `bucket = "..."` 를 여기 추가하면 그 순간 D25 가 무너진다. init 실패는 버그가 아니라
#    -backend-config 를 빠뜨렸다는 신호다. 자세한 것은 이 디렉토리의 README.md 를 읽는다.
terraform {
  backend "s3" {}
}
