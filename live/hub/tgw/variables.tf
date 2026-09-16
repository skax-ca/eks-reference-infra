# 변수는 두 종류다: 네이밍·태깅 입력(기본값 있음)과 git에 두지 않는 계정 식별 값(기본값 없음).
# ⚠️ tflint terraform_unused_declarations가 미사용 변수를 exit 2로 잡는다. 변수를 추가할 때는
#    소비하는 코드를 같은 커밋에 넣는다.

variable "aws_region" {
  description = "리소스를 만들 리전. region_code 와 짝이 맞아야 한다(an2 ↔ ap-northeast-2)."
  type        = string
  default     = "ap-northeast-2"
  nullable    = false
}

variable "workload" {
  description = <<-EOT
    워크로드 코드. Name 태그의 2번째 토큰이자 거버넌스 태그 Workload 의 값이다.
    ⚠️ 이 값이 공용 개발 계정에서 우리 자산을 식별하는 유일한 기준이다(CLAUDE.md 참조).
  EOT
  type        = string
  default     = "demo"
  nullable    = false
}

variable "env" {
  description = "환경 코드. 이 루트는 env=\"hub\"로 논리적 환경을 가른다(team 계정)."
  type        = string
  default     = "hub"
  nullable    = false
}

variable "region_code" {
  description = "Name 태그에 쓰는 리전 약어. 모듈이 리소스 타입 약어와 조합한다."
  type        = string
  default     = "an2"
  nullable    = false
}

variable "repository" {
  description = "거버넌스 태그 Repository 값. 리소스에서 이 repo 로 역추적하는 경로다."
  type        = string
  default     = "skax-ca/eks-reference-infra"
  nullable    = false
}

variable "execution_role_arn" {
  description = <<-EOT
    provider가 체인 assume할 실행 Role ARN(2단 체인의 2단째).

    ⛔ 기본값을 두지 않는다. ARN에 계정 ID가 들어 있어 "계정 식별 정보를 git에 두지
       않는다"는 요건에 걸린다. 주입 경로는 둘 다 git 밖이다:
         CI   : repo 변수 HUB_AWS_EXEC_ROLE_ARN → env: TF_VAR_execution_role_arn
         로컬 : export TF_VAR_execution_role_arn=...
  EOT
  type        = string
  nullable    = false
}

variable "spoke_account_id" {
  description = <<-EOT
    spoke(dev, asset 계정)의 12자리 계정 ID. Transit Gateway RAM 공유(aws_ram_principal_association의
    principal)에만 쓴다.

    ⛔ 기본값을 두지 않는다(계정 ID는 git에 두지 않는다). 주입 경로: CI는 repo 변수
       DEV_ACCOUNT_ID → TF_VAR_spoke_account_id, 로컬은 export TF_VAR_spoke_account_id=...
  EOT
  type        = string
  nullable    = false
}
