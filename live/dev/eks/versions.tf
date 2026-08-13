# 배포 루트는 **상한을 건다**. 모듈은 하한만 선언하고(aws >= 6.0), 상한은 루트가
# .terraform.lock.hcl 과 함께 통제한다 — 이 규약은 모듈 repo의 docs/가 소유한다.
terraform {
  # 하한 1.12.0 은 **이 repo 의 표준 툴체인 바닥**이다(CI TOFU_VERSION = 1.12.5, lock 이 그 버전으로
  # 생성된다). eks-cluster 모듈 자체의 요구는 >= 1.9.0 이지만(그 모듈은 동적 prevent_destroy 를
  # 쓰지 않아 vpc 보다 낮다), 이 배포 루트는 leaf 라 남이 소비하지 않으므로 두 루트를 같은 바닥에
  # 맞춰 "왜 이 루트만 다르냐"를 없앤다. 근거 없는 상향이 소비자를 배제하는 것은 **모듈** 이야기다.
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
