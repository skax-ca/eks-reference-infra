<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-08-19 | Updated: 2026-08-19 -->

# live/hub

## 목적
허브 배포 루트. `live/dev`를 템플릿으로 신설했다(2026-08-19, 허브-스포크 크로스 계정 IAM
설계 구현 1단계) — 각 하위 디렉토리가 고유한 state와 워크플로를 가진 독립 배포 단위인 점은
`live/dev`와 같다. **같은 AWS 계정**을 쓴다(실측: `live/dev`가 이미 배포된 공용 개발 계정과
동일)지만 **소유는 별도**다 — dev가 향후 별도 계정으로 이전할 예정이라, state 버킷·입구/실행
Role은 dev·hub 각자 갖는다(공유하는 유일한 예외는 OIDC provider — AWS 제약). CIDR·`env`
토큰도 당연히 다르다.

## 하위 디렉토리

| 디렉토리 | 목적 | State Key |
|---------|------|-----------|
| `tgw/` | Transit Gateway + RAM 공유 + prefix list (`tgw/AGENTS.md` 참고, 2026-08-24 networking에서 분리) | `hub/tgw.tfstate` |
| `networking/` | VPC + 서브넷 + NAT + Flow Logs + hub 자신의 TGW attachment (`networking/AGENTS.md` 참고) | `hub/networking.tfstate` |
| `eks/` | EKS 클러스터 + 노드 그룹 + Karpenter + ArgoCD hub Pod Identity 전제 (`eks/AGENTS.md` 참고) | `hub/eks.tfstate` |

## 진행 기록

```
2026-08-19: 코드+workflow 신설(이 커밋). bootstrap 입구 Role 신뢰 정책에 environment:hub
            패턴 추가·수렴 확인. GitHub Environment `hub` 신설. 아직 apply 안 함.
```

## AI 에이전트 가이드

### 배포 순서
`tgw` → `networking` → `eks` 순서다(2026-08-24 tgw 분리 이후). `tgw`가 먼저인 이유는
`networking`의 spoke 자동 발견 로직이 그 TGW를 data source로 조회하기 때문이다(TGW가
없으면 `Invalid for_each argument`로 실패 — `tgw/README.md` 참조). `networking`이
`eks`보다 먼저인 이유는 `eks` 루트가 태그로 VPC를 조회하기 때문이다:
```hcl
data "aws_vpc" "this" {
  filter { name = "tag:Name";     values = ["vpc-demo-hub-an2-main"] }
  filter { name = "tag:Workload"; values = ["demo"] }
}
```
networking이 apply되지 않으면 eks plan이 빈 결과를 반환한다(에러가 아니라 조용히 실패 — 주의).

### State 격리
- 각 루트가 S3에 고유한 state 파일을 가진다. **버킷도 `live/dev`와 별도**(`s3-demo-hub-an2-tfstate-*`) —
  같은 계정이지만 dev·hub는 부트스트랩 자원(버킷·입구/실행 Role)을 공유하지 않는다
  (`bootstrap/README.md` 참조. OIDC provider만 AWS 제약으로 불가피하게 공유)
- 루트 사이에 `terraform_remote_state` 데이터 소스 없음
- 결합은 **태그 규약으로만** 이루어진다(클러스터명 상수 `eks-demo-hub-an2-main-01`)

### 크로스 계정 확장과의 관계
`live/hub/eks`는 스포크 계정과의 크로스 계정 IAM 연결점(`enable_argocd_hub_pod_identity`)을
갖지만, 스포크(`live/<spoke-env>` — 아직 미신설)가 없는 동안은 `false`로 둔다. 스포크 배포·
배선은 이 루트의 범위 밖이다(notepad 우선순위 3~6번 참조).

### 새 루트 추가
1. `live/hub/<name>/` 디렉토리를 표준 IaC 파일로 생성
2. `deploy-hub-network.yml` 패턴을 따라 `deploy-hub-<name>.yml` 워크플로 생성
3. 별도 concurrency group과 state key 설정
4. notepad.md에 진행 기록 추가

<!-- MANUAL: -->
