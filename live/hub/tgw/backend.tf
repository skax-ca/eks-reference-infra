# ⛔ 이 블록은 비어 있어야 한다(partial backend configuration). 버킷명은 계정 식별 정보라
#    git에 두지 않는다. 주입 경로는 둘 다 git 밖이다:
#      CI   : GitHub repo 변수 → runner가 backend.hcl을 조립
#      로컬 : gitignore된 backend.hcl → tofu init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
