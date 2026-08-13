# 이 루트의 변수는 두 종류다(networking 과 같은 분류다):
#   ① 코드에 기본값이 있는 것  — 노출돼도 무해하고 고객사가 바꿀 토큰(workload·env·region)
#   ② 기본값이 **없는** 것      — 계정/운영자 식별 정보라 git 에 두지 않는다.
#                                CI 는 repo 변수, 로컬은 TF_VAR_* 로 주입한다
#
# ⚠️ tflint terraform_unused_declarations 는 미사용 변수를 exit 2 로 잡는다.
#    변수를 추가할 때는 소비하는 코드를 같은 커밋에 넣는다.

variable "aws_region" {
  description = "리소스를 만들 리전. region_code 와 짝이 맞아야 한다(an2 ↔ ap-northeast-2)."
  type        = string
  default     = "ap-northeast-2"
}

variable "workload" {
  description = <<-EOT
    워크로드 코드. Name 태그의 2번째 토큰이자 거버넌스 태그 Workload 의 값이다.
    ⚠️ 공용 개발 계정에서 **우리 자산을 식별하는 유일한 기준**이다(CLAUDE.md 참조).
    ⚠️ VPC 를 조회하는 data source 필터의 일부이기도 하다 — networking 루트의 workload 와
       반드시 같아야 클러스터가 우리 VPC 를 찾는다(아래 main.tf).
  EOT
  type        = string
  default     = "demo"
}

variable "env" {
  description = "환경 코드. 이 배포 루트는 dev 하나만 채운다 — 계정이 하나라 stg/prd 는 표현할 수 없다."
  type        = string
  default     = "dev"
}

variable "region_code" {
  description = "Name 태그에 쓰는 리전 약어. 모듈이 리소스 타입 약어와 조합한다."
  type        = string
  default     = "an2"
}

variable "repository" {
  description = "거버넌스 태그 Repository 값. 리소스에서 이 repo 로 역추적하는 경로다."
  type        = string
  default     = "skax-ca/iac-reference-infra"
}

variable "execution_role_arn" {
  description = <<-EOT
    provider 가 체인 assume 할 **실행 Role** ARN — 2단 체인의 2단째다.

    ⛔ 기본값을 두지 않는다. ARN 에 계정 ID 가 들어 있어 "계정 식별 정보를 git 에 두지
       않는다"는 요건에 걸린다. 주입 경로는 둘 다 git 밖이다:
         CI   : repo 변수 AWS_EXEC_ROLE_ARN → env: TF_VAR_execution_role_arn
         로컬 : export TF_VAR_execution_role_arn=...

    ⚠️ 이 Role 의 신뢰 정책은 **입구 Role 하나만** 허용한다. 개인 IAM user 로는 assume 되지
       않아 **로컬 plan/apply 는 성립하지 않는다.** 로컬은 init -backend=false + validate 까지다.
  EOT
  type        = string
}

# ⛔ **`public_access_cidrs` 는 삭제됐다**(private-only 전환).
#    public 엔드포인트가 꺼지면 EKS 가 이 값을 무시한다 — 남겨 두면 *"좁혀 두었다"* 는 착시만
#    만드는 죽은 설정이다. 되살리는 것은 설계 목적(모듈 repo의 워크벤치 설계 문서)을 되돌리는
#    결정이므로 그때 명시적으로 판단한다.
#    ⚠️ tflint `terraform_unused_declarations` 가 미사용 변수를 exit 2 로 잡으므로 소비 지점
#       (main.tf)을 지우는 커밋과 **같은 커밋**에서 지워야 한다.
#    ⚠️ CI repo 변수 `EKS_PUBLIC_ACCESS_CIDRS` 와 워크플로의 `TF_VAR_public_access_cidrs` 도
#       함께 걷어낸다 — 코드가 안 읽으면 죽은 설정이다.
