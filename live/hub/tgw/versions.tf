# 배포 루트는 상한을 건다. 모듈은 하한만 선언하고(aws >= 6.0), 상한은 루트가
# .terraform.lock.hcl과 함께 통제한다(iac-module-library docs/conventions.md 「버전」).
terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
