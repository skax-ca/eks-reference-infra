# provider 설정에 이 루트의 규약 셋이 모여 있다: 2단 체인, 거버넌스 태그, 계정 자동 태거 방어.

provider "aws" {
  region = var.aws_region

  # OIDC 2단 체인의 2단째. 1단(GitHub Actions OIDC → 입구 Role iamr-demo-hub-an2-gha-entry-01)은
  # configure-aws-credentials가 워크플로에서 수행하고, 입구 Role의 권한은 이 assume 하나뿐이다.
  # 2단은 입구 Role → 실행 Role(iamr-demo-hub-an2-gha-exec-01, AdministratorAccess)이다.
  # 실행 Role은 계정 루트가 아니라 입구 Role만 믿는다. 그 좁힌 신뢰 경계가 이 체인의 핵심이다.
  # ⚠️ 역할 체인 세션은 최대 1시간이고 연장할 수 없다. apply job이 다시 인증하므로 승인 지연
  #    자체는 문제없고, 그 사이 state가 바뀌면 apply가 거부하는데 그것은 정상 동작이다.
  assume_role {
    role_arn = var.execution_role_arn
    # CloudTrail에서 누가 무엇을 했는지 이 이름으로 갈린다. 배포 루트마다 다르게 둔다.
    session_name = "tofu-live-hub-networking"
  }

  # 거버넌스 태그는 루트가 100% 담당한다. 모듈은 Name 태그만 조합하고 거버넌스 태그를 모른다.
  # 개별 리소스나 모듈 인자로 이 태그들을 반복하지 않는다.
  default_tags {
    tags = {
      Environment = var.env
      Workload    = var.workload
      RegionCode  = var.region_code
      ManagedBy   = "opentofu"
      Repository  = var.repository
    }
  }

  # 계정 자동 태거 방어. 이 공용 개발 계정에는 계정 전역 자동 태거가 돌아, 생성 주체와 무관하게
  # (CloudFormation·Terraform·콘솔 전부) CreationTime·Creator·cz-org·cz-owner·cz-ext1~3 키를
  # 붙인다. 이 키들은 우리 state에 없으므로 ignore_tags가 없으면 두 번째 apply에서 전 리소스에
  # "태그 제거" 가짜 diff가 생기고, 실제로 지우면 남의 거버넌스 태거와 싸우게 된다.
  # ⚠️ 이 블록이 맞는지의 유일한 증거는 두 번째 apply가 No changes를 내는가이다.
  ignore_tags {
    keys         = ["CreationTime", "Creator"]
    key_prefixes = ["cz-"]
  }
}
