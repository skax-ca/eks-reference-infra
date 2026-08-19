# provider 설정에 이 루트의 규약 셋이 모여 있다: 2단 체인 · 거버넌스 태그 · 자동 태거 방어.

provider "aws" {
  region = var.aws_region

  # ── OIDC 2단 체인의 **2단째** ────────────────────────────────────────────────
  # 1단: GitHub Actions OIDC → 입구 Role(iamr-demo-dev-an2-gha-entry-01).
  #      configure-aws-credentials 가 워크플로에서 수행한다. 입구 Role 의 권한은 이 assume 하나뿐이다.
  # 2단: 입구 Role → 실행 Role(iamr-demo-dev-an2-gha-exec-01, AdministratorAccess). 여기.
  #
  # 신뢰 경계를 좁힌 것이 이 체인의 핵심이다 — 실행 Role 은 계정 루트가 아니라 입구 Role 만 믿는다.
  # ⚠️ 역할 체인 세션은 **최대 1시간**이고 연장할 수 없다(AWS 제약). apply job 이 다시 인증하므로
  #    승인 지연 자체는 문제없다. 그 사이 state 가 바뀌면 apply 가 거부하는데 그건 정상 동작이다.
  assume_role {
    role_arn = var.execution_role_arn
    # CloudTrail 에서 누가 무엇을 했는지 이 이름으로 갈린다. 배포 루트마다 다르게 둔다.
    session_name = "tofu-live-hub-networking"
  }

  # ── 거버넌스 태그는 **루트가 100% 담당**한다(모듈 repo 규약) ─────────────────
  # 모듈은 Name 태그만 조합하고 거버넌스 태그를 모른다. 이 분리가 규약의 핵심이라,
  # 개별 리소스나 모듈 인자로 이 태그들을 반복하지 않는다.
  default_tags {
    tags = {
      Environment = var.env
      Workload    = var.workload
      RegionCode  = var.region_code
      ManagedBy   = "opentofu"
      Repository  = var.repository
    }
  }

  # ── 계정 자동 태거 방어 — 추정이 아니라 실측이다 ──────────────────────────────
  #
  # 이 계정(공용 개발 계정)에는 계정 전역 자동 태거가 돌고 있다. 생성 주체와 무관하게
  # (CloudFormation·Terraform·콘솔 전부) 아래 키가 붙는 것을 실측했다:
  #
  #     리소스      전체    자동 태그가 붙은 것
  #     VPC          23      22   (나머지 1개는 태거 도입 전 default VPC)
  #     Subnet       82      78
  #     IGW          17      16
  #
  #     붙는 키: CreationTime · Creator · cz-org · cz-owner · cz-ext1 · cz-ext2 · cz-ext3
  #     (구세대 6건은 cz-owner · cz-project · cz-stage — 태거가 한 번 개정된 흔적)
  #
  # 이 키들은 우리 state 에 없다. ignore_tags 가 없으면 두 번째 apply 에서 전 리소스에
  # **"태그 7개 제거" 가짜 diff**가 생기고, 실제로 지우면 남의 거버넌스 태거와 싸우게 된다.
  #
  # 판정 기준: **두 번째 apply 가 No changes 를 내는가.** 그것이 이 블록이 맞는지의 유일한 증거다.
  ignore_tags {
    keys         = ["CreationTime", "Creator"]
    key_prefixes = ["cz-"]
  }
}
