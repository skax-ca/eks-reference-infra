# ⛔ 이 블록은 비어 있어야 한다(partial backend configuration). 버킷명은 git에 두지 않는다
#    (근거는 networking 루트의 backend.tf와 같다).
#
# 주입 경로는 둘 다 git 밖이다:
#   CI   : GitHub repo 변수 → tofu init -backend-config="bucket=${{ vars.DEV_TF_STATE_BUCKET }}" ...
#   로컬 : gitignore된 backend.hcl → tofu init -backend-config=backend.hcl
#
# ⚠️ state 키는 networking과 다르다(dev/eks.tfstate). 같은 버킷 안에서 키로만 갈리고, 이 키
#    분리가 "vpc와 eks를 독립적으로 배포·파기"의 물리적 근거다. 두 루트는 서로의 state를 읽지
#    않는다(결합은 Name/SubnetGroup 태그 data source로만).
# ⚠️ init 실패는 버그가 아니라 -backend-config를 빠뜨렸다는 신호다.
terraform {
  backend "s3" {}
}
