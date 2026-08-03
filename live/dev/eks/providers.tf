# provider 설정에 이 루트의 규약 셋이 모여 있다: 2단 체인 · 거버넌스 태그 · 자동 태거 방어.
# networking 루트의 providers.tf 와 **의도적으로 동일한 규약**이다 — session_name 만 다르다.

provider "aws" {
  region = var.aws_region

  # ── OIDC 2단 체인의 **2단째** (design/50 §3) ────────────────────────────────
  # 1단: GitHub Actions OIDC → 입구 Role. 2단: 입구 Role → 실행 Role(AdministratorAccess). 여기.
  # 신뢰 경계를 좁힌 것이 D27-1 의 핵심이다 — 실행 Role 은 입구 Role 만 믿는다.
  # ⚠️ 역할 체인 세션은 최대 1시간(연장 불가). apply job 이 다시 인증하므로 승인 지연은 무해하다.
  assume_role {
    role_arn = var.execution_role_arn
    # CloudTrail 에서 누가 무엇을 했는지 이 이름으로 갈린다. **배포 루트마다 다르게** 둔다 —
    # networking 은 tofu-live-dev-networking, 여기는 eks. 같은 계정에서 두 루트의 행위를 구분한다.
    session_name = "tofu-live-dev-eks"
  }

  # ── 거버넌스 태그는 **루트가 100% 담당**한다 (모듈 repo 02 §1.1) ──────────────
  # 모듈은 Name 태그만 조합하고 거버넌스 태그를 모른다. EKS 가 만드는 전 리소스(클러스터·노드그룹·
  # SG·IAM role·OIDC provider·SQS)에 이 태그가 default_tags 로 자동 부착된다.
  default_tags {
    tags = {
      Environment = var.env
      Workload    = var.workload
      RegionCode  = var.region_code
      ManagedBy   = "opentofu"
      Repository  = var.repository
    }
  }

  # ── 계정 자동 태거 방어 — networking 에서 실측된 것과 동일 (2026-07-31) ────────
  # 공용 계정(F13)의 전역 자동 태거는 생성 주체·리소스 타입과 무관하게 아래 키를 붙인다.
  # EKS 가 만드는 서브넷-부착 리소스·ENI 에도 붙으므로 같은 ignore_tags 가 필요하다.
  # 없으면 두 번째 apply 에서 "태그 제거" 가짜 diff 가 생긴다. 판정 기준: 두 번째 apply 가 No changes.
  ignore_tags {
    keys         = ["CreationTime", "Creator"]
    key_prefixes = ["cz-"]
  }
}
