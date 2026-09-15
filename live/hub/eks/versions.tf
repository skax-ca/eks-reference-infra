# 배포 루트는 상한을 건다. 모듈은 하한만 선언하고(aws >= 6.0), 상한은 루트가
# .terraform.lock.hcl과 함께 통제한다(iac-module-library docs/conventions.md 「버전」).
terraform {
  # 하한 1.12.0은 이 repo의 표준 툴체인 바닥이다(CI TOFU_VERSION과 lock 파일이 그 버전). eks-cluster
  # 모듈 자체의 요구는 더 낮지만, 이 배포 루트는 leaf라 남이 소비하지 않으므로 vpc 루트와 같은
  # 바닥에 맞춰 "왜 이 루트만 다르냐"를 없앤다.
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
