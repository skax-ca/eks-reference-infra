# provider 설정에 이 루트의 규약 셋이 모여 있다: 2단 체인 · 거버넌스 태그 · 자동 태거 방어.
# networking 루트의 providers.tf 와 **의도적으로 동일한 규약**이다 — session_name 만 다르다.

provider "aws" {
  region = var.aws_region

  # ── OIDC 2단 체인의 **2단째** ────────────────────────────────────────────────
  # 1단: GitHub Actions OIDC → 입구 Role. 2단: 입구 Role → 실행 Role(AdministratorAccess). 여기.
  # 신뢰 경계를 좁힌 것이 이 체인의 핵심이다 — 실행 Role 은 입구 Role 만 믿는다.
  # ⚠️ 역할 체인 세션은 최대 1시간(연장 불가). apply job 이 다시 인증하므로 승인 지연은 무해하다.
  assume_role {
    role_arn = var.execution_role_arn
    # CloudTrail 에서 누가 무엇을 했는지 이 이름으로 갈린다. **배포 루트마다 다르게** 둔다 —
    # networking 은 tofu-live-hub-networking, 여기는 eks. 같은 계정에서 두 루트의 행위를 구분한다.
    session_name = "tofu-live-hub-eks"
  }

  # ── 거버넌스 태그는 **루트가 100% 담당**한다(모듈 repo 규약) ─────────────────
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

  # ── 계정 자동 태거 방어 — networking 에서 실측된 것과 동일 ────────────────────
  # 공용 개발 계정의 전역 자동 태거는 생성 주체·리소스 타입과 무관하게 아래 키를 붙인다.
  # EKS 가 만드는 서브넷-부착 리소스·ENI 에도 붙으므로 같은 ignore_tags 가 필요하다.
  # 없으면 두 번째 apply 에서 "태그 제거" 가짜 diff 가 생긴다. 판정 기준: 두 번째 apply 가 No changes.
  #
  # ➕ **`Dependency*` 추가** — workbench apply 에서 실측된 두 번째 태거다.
  #    `DependencyID`(= 부착 인스턴스 ID) · `DependencyName`(= 그 인스턴스의 Name) 을 붙인다.
  #    ⚠️ **볼륨 전용**이다 — 계정 전수 조회에서 `ResourceType` 이 15건 모두 `volume` 이었다.
  #       그래서 `live/dev/networking`(볼륨을 만들지 않는다)에는 넣지 않았다. 두 루트의
  #       `ignore_tags` 가 다른 것은 **의도된 차이**이니 "parity 복원"으로 맞추지 말 것.
  #    ⚠️ **생성 이벤트 기반이지 주기 실행이 아니다** — apply 로 지운 뒤 다시 붙지 않는 것을 확인했다.
  #       그래도 넣는 이유는 **인스턴스가 재생성될 때마다** 같은 가짜 diff 가 나기 때문이다
  #       (`user_data_replace_on_change = true` 라 도구 버전·AMI 핀을 올리면 실제로 재생성된다).
  ignore_tags {
    keys         = ["CreationTime", "Creator", "DependencyID", "DependencyName"]
    key_prefixes = ["cz-"]
  }
}

# ⚠️ **`Name` 은 ignore_tags 로 막지 않는다 — 막을 수도 없다.**
#
# 같은 태거가 볼륨의 `Name` 도 **인스턴스 Name 으로 덮어쓴다**(실측: workbench 볼륨이
# `vol-…-workbench-01` 대신 `ec2-…-workbench-01` 이었다). 하지만 `Name` 은 이 repo 의
# 네이밍 계약이라 무시 대상이 될 수 없다 — 무시하면 모든 `Name` 규약이 함께 눈이 먼다.
#
# ⇒ **tofu 가 되돌리는 것이 정답이고, 그것이 self-healing 이다.** 대가는 볼륨이 생성될 때마다
#    한 번씩 `volume_tags.Name` diff 가 뜨는 것뿐이다. 반복 drift 가 아니라 **생성당 1회**다.
#
# EKS 노드 볼륨은 `Name`·`DependencyName` 이 **빈 값**이다 — 태거가 인스턴스 Name 을 읽는
#    시점에 아직 태그가 없었던 경쟁 상태다. workbench 는 `volume_tags` 를 쓰므로
#    `TagSpecifications` 로 생성 시점에 붙어 태거가 값을 읽을 수 있었다(모듈 main.tf 주석 참조).
