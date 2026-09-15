# provider 설정에 이 루트의 규약 셋이 모여 있다: 2단 체인, 거버넌스 태그, 계정 자동 태거 방어.
# networking 루트의 providers.tf와 같은 규약이고 session_name과 ignore_tags의 Dependency* 키만 다르다.

provider "aws" {
  region = var.aws_region

  # OIDC 2단 체인의 2단째. 1단은 GitHub Actions OIDC → 입구 Role, 2단은 입구 Role → 실행
  # Role(AdministratorAccess). 실행 Role은 입구 Role만 믿는다.
  # ⚠️ 역할 체인 세션은 최대 1시간(연장 불가). apply job이 다시 인증하므로 승인 지연은 무해하다.
  assume_role {
    role_arn = var.execution_role_arn
    # CloudTrail에서 누가 무엇을 했는지 이 이름으로 갈린다. 배포 루트마다 다르게 둔다.
    session_name = "tofu-live-dev-eks"
  }

  # 거버넌스 태그는 루트가 100% 담당한다. 모듈은 Name 태그만 조합하고 거버넌스 태그를 모른다.
  # EKS가 만드는 전 리소스(클러스터·노드그룹·SG·IAM role·OIDC provider·SQS)에 default_tags로
  # 자동 부착된다.
  default_tags {
    tags = {
      Environment = var.env
      Workload    = var.workload
      RegionCode  = var.region_code
      ManagedBy   = "opentofu"
      Repository  = var.repository
    }
  }

  # 계정 자동 태거 방어. 공용 개발 계정의 전역 자동 태거는 생성 주체·리소스 타입과 무관하게
  # CreationTime·Creator·cz-* 키를 붙이고, EKS가 만드는 서브넷-부착 리소스·ENI에도 붙는다.
  # 없으면 두 번째 apply에서 "태그 제거" 가짜 diff가 생긴다.
  # ⚠️ Dependency*(DependencyID = 부착 인스턴스 ID, DependencyName = 그 인스턴스의 Name)는
  #    볼륨에만 붙는 두 번째 태거다. 볼륨을 만들지 않는 networking 루트에는 넣지 않으므로 두
  #    루트의 ignore_tags가 다른 것은 의도된 차이다. "parity 복원"으로 맞추지 않는다.
  # ⚠️ 이 태거는 생성 이벤트 기반이라 apply로 지운 뒤 다시 붙지 않지만, workbench는
  #    user_data_replace_on_change = true라 도구 버전·AMI 핀을 올릴 때마다 재생성되고 그때마다
  #    같은 가짜 diff가 난다. 판정 기준은 두 번째 apply가 No changes를 내는가이다.
  ignore_tags {
    keys         = ["CreationTime", "Creator", "DependencyID", "DependencyName"]
    key_prefixes = ["cz-"]
  }
}

# ⚠️ Name은 ignore_tags로 막지 않는다(막을 수도 없다). 같은 태거가 볼륨의 Name도 인스턴스
#    Name으로 덮어쓰지만, Name은 이 repo의 네이밍 계약이라 무시하면 모든 Name 규약이 함께 눈이
#    먼다. tofu가 되돌리는 것이 정답이고, 대가는 볼륨이 생성될 때마다 한 번씩 volume_tags.Name
#    diff가 뜨는 것뿐이다(반복 drift가 아니라 생성당 1회).
#    EKS 노드 볼륨은 Name·DependencyName이 빈 값이다. 태거가 인스턴스 Name을 읽는 시점에 아직
#    태그가 없었던 경쟁 상태다. workbench는 volume_tags를 쓰므로 TagSpecifications로 생성
#    시점에 붙어 태거가 값을 읽을 수 있다.
