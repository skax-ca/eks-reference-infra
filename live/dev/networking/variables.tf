# 이 루트의 변수는 두 종류다. 섞어 두면 "왜 이건 코드에 있고 저건 없나"가 흐려진다.
#
#   ① 코드에 기본값이 있는 것  — 노출돼도 무해하고, 고객사가 바꿀 토큰이다(workload·env·region)
#   ② 기본값이 **없는** 것      — 계정 식별 정보라 git 에 두지 않는다. CI 는 repo 변수,
#                                로컬은 TF_VAR_* 환경변수로 주입한다
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
    ⚠️ 이 값이 공용 개발 계정에서 **우리 자산을 식별하는 유일한 기준**이다(CLAUDE.md 참조).
    이름으로 판단하지 않는다 — Workload=demo 태그로 판단한다.
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

    ⚠️ 이 Role 의 신뢰 정책은 **입구 Role 하나만** 허용한다. 따라서 개인 IAM user 로는
       assume 되지 않고 **로컬 plan/apply 는 성립하지 않는다.** 의도된 제약이다 —
       로컬에서 가능한 것은 init -backend=false 와 validate 까지다(README.md 참조).
  EOT
  type        = string
}

variable "hub_transit_gateway_id" {
  description = <<-EOT
    hub(team 계정)가 소유한 Transit Gateway ID. spoke 의 attachment 를 이 TGW 에 붙인다
    (모듈 repo docs/02-choose-your-path.md 「네트워크 경로」 절).

    ⛔ 기본값을 두지 않는다 — 결정적 합성이 불가능한 AWS 무작위 값이다(hub apply 후에만
       나온다). 주입 경로: CI 는 repo 변수 HUB_TRANSIT_GATEWAY_ID → TF_VAR_hub_transit_gateway_id,
       로컬은 export TF_VAR_hub_transit_gateway_id=...
  EOT
  type        = string
}

variable "hub_tgw_resource_share_arn" {
  description = <<-EOT
    hub 가 TGW 를 공유하는 RAM resource share ARN. allow_external_principals = true 설계라
    spoke 가 aws_ram_resource_share_accepter 로 명시적으로 초대를 수락해야 attachment 를
    만들 수 있다 — 조직 내부 공유(초대 없음)는 조직 관리 계정 권한이 없어 쓸 수 없다
    (2026-08-20 실측, 모듈 repo docs/02-choose-your-path.md 참조).

    ⛔ 기본값을 두지 않는다 — ARN 에 hub 계정 ID 가 들어 있다. 주입 경로: CI 는 repo 변수
       HUB_TGW_RESOURCE_SHARE_ARN → TF_VAR_hub_tgw_resource_share_arn, 로컬은
       export TF_VAR_hub_tgw_resource_share_arn=...
  EOT
  type        = string
}
