# provider 설정은 live/hub/networking과 같은 셋이다(2단 체인, 거버넌스 태그, 계정 자동 태거
# 방어). 각 항목의 근거는 그 디렉토리의 providers.tf가 갖는다.

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
