# 배포 루트는 **상한을 건다**. 모듈은 하한만 선언하고(aws >= 6.0), 상한은 루트가
# .terraform.lock.hcl 과 함께 통제한다 — 이 규약은 모듈 repo의 docs/가 소유한다.
terraform {
  # 하한 1.12.0 의 근거는 모듈이 요구하는 값 그대로다(modules/vpc/versions.tf) —
  # 동적 prevent_destroy 가 lifecycle 에서 입력 변수를 참조하는 데 필요하다.
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
