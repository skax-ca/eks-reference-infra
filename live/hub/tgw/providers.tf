# provider 설정은 live/hub/networking과 동일한 규약 셋이다: 2단 체인 · 거버넌스 태그 · 자동
# 태거 방어. 그 디렉토리의 providers.tf 주석이 각 항목의 근거를 자세히 설명한다 — 여기 다시
# 적지 않는다.

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = var.execution_role_arn
    session_name = "tofu-live-hub-tgw"
  }

  default_tags {
    tags = {
      Environment = var.env
      Workload    = var.workload
      RegionCode  = var.region_code
      ManagedBy   = "opentofu"
      Repository  = var.repository
    }
  }

  ignore_tags {
    keys         = ["CreationTime", "Creator"]
    key_prefixes = ["cz-"]
  }
}
