# 이 루트의 변수는 두 종류다(networking 과 같은 분류다):
#   ① 코드에 기본값이 있는 것  — 노출돼도 무해하고 고객사가 바꿀 토큰(workload·env·region)
#   ② 기본값이 **없는** 것      — 계정/운영자 식별 정보라 git 에 두지 않는다(D25 의 연장).
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
    워크로드 코드(D24). Name 태그의 2번째 토큰이자 거버넌스 태그 Workload 의 값이다.
    ⚠️ 공용 계정에서 **우리 자산을 식별하는 유일한 기준**이다(F13 · CLAUDE.md §4-1).
    ⚠️ VPC 를 조회하는 data source 필터의 일부이기도 하다 — networking 루트의 workload 와
       반드시 같아야 클러스터가 우리 VPC 를 찾는다(아래 main.tf).
  EOT
  type        = string
  default     = "ref"
}

variable "env" {
  description = "환경 코드. 이 배포 루트는 dev 하나만 채운다(D22 — 계정이 하나라 stg/prd 는 표현 불가)."
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
    provider 가 체인 assume 할 **실행 Role** ARN (design/50 D27-1 · §3 의 2단 체인 2단째).

    ⛔ 기본값을 두지 않는다. ARN 에 계정 ID 가 들어 있어 D25 의 "계정 식별 정보를 git 에 두지
       않는다"에 걸린다. 주입 경로는 둘 다 git 밖이다:
         CI   : repo 변수 AWS_EXEC_ROLE_ARN → env: TF_VAR_execution_role_arn
         로컬 : export TF_VAR_execution_role_arn=...

    ⚠️ 이 Role 의 신뢰 정책은 **입구 Role 하나만** 허용한다(D27-1). 개인 IAM user 로는 assume 되지
       않아 **로컬 plan/apply 는 성립하지 않는다.** 로컬은 init -backend=false + validate 까지다.
  EOT
  type        = string
}

variable "public_access_cidrs" {
  description = <<-EOT
    kube-apiserver public 엔드포인트 접근을 허용할 CIDR 목록(운영자·CI 의 출발지 IP).

    ⛔ 기본값을 두지 않는다 — 두 가지 이유가 겹친다:
      ① 운영자의 출발지 IP 는 계정/조직 식별 정보에 준한다(D25 의 연장). git 에 두지 않는다.
      ② 이 모듈은 빈 리스트를 받으면 EKS 가 0.0.0.0/0 으로 **전면 개방**한다 — 기본값 [] 는 위험하다.
         값이 없으면 apply 가 실패하는 편이 낫다(설정 누락을 조용히 통과시키지 않는다).

    주입 경로(둘 다 git 밖):
      CI   : repo 변수 EKS_PUBLIC_ACCESS_CIDRS(예: "1.2.3.4/32,5.6.7.8/32") → env: TF_VAR_public_access_cidrs
      로컬 : export TF_VAR_public_access_cidrs='["1.2.3.4/32"]'
    ⚠️ validate 는 값이 없어도 통과한다(값을 요구하는 것은 plan 이다).
  EOT
  type        = list(string)

  validation {
    # public 을 켜는 루트에서 전면 개방을 방지한다. 0.0.0.0/0 을 명시로도 넣지 못하게 막는다 —
    # "제한된 public"이 이 루트의 전제이기 때문이다(사용자 결정 2026-08-03).
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "public_access_cidrs 에 0.0.0.0/0 을 넣지 않는다. 이 루트는 제한된 public 접근이 전제다."
  }
}
