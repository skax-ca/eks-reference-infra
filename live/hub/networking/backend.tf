# ⛔ 이 블록은 비어 있어야 한다(partial backend configuration). 버킷명은 git에 두지 않는다:
#    AWS 공식이 예측 불가능한 버킷명(스쿼팅 방지)과 버킷명에 민감정보 금지(URL 노출)를 권장하고,
#    이 파일은 고객사에 복사해 줄 템플릿이라 "private이라 안 보인다"가 성립하지 않는다.
#
# 주입 경로는 둘 다 git 밖이다:
#   CI   : GitHub repo 변수 → tofu init -backend-config="bucket=${{ vars.HUB_TF_STATE_BUCKET }}" ...
#   로컬 : gitignore된 backend.hcl → tofu init -backend-config=backend.hcl
#
# ⚠️ init 실패는 버그가 아니라 -backend-config를 빠뜨렸다는 신호다.
terraform {
  backend "s3" {}
}
