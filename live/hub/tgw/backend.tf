# ⛔ 이 블록은 비어 있어야 한다 — partial backend configuration이다(live/hub/networking과
# 같은 이유, 그 디렉토리의 backend.tf 주석 참조). 버킷명을 여기 적지 않는다.
#
# 주입 경로 (둘 다 git 밖):
#   CI    : GitHub repo 변수 → runner 가 backend.hcl 을 조립
#   로컬  : gitignore 된 backend.hcl → tofu init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
