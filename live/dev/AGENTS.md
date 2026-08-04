<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# live/dev

## 목적
Phase별 배포 루트. 각 하위 디렉토리가 고유한 state와 워크플로를 가진 독립 배포 단위다.

## 하위 디렉토리

| 디렉토리 | 목적 | State Key |
|---------|------|-----------|
| `networking/` | VPC + 서브넷 + NAT + Flow Logs (`networking/AGENTS.md` 참고) | `dev/networking.tfstate` |
| `eks/` | EKS 클러스터 + 노드 그룹 + Karpenter (`eks/AGENTS.md` 참고) | `dev/eks.tfstate` |

## Phase 기록 (2026-07-30 ~ 2026-08-04)

```
Phase 1:  골격 + GitHub App 인증 (D20)
Phase 2:  OIDC sub 3패턴 실측
Phase 3:  bootstrap (D21) — S3 + OIDC + 2 Roles
Phase 4:  networking apply (66개 리소스)
Phase 5:  design/50 개정 (D-CONSUME D20~D30)
Phase 6:  Phase 6-1 (prevent_destroy), 6-2 (계정 정보 정리), 6-3 (confused deputy)
vpc-v1.2.0 승격 (2026-08-03): 서브넷 태그 in-place, 0 destroy
PR#13/14 (2026-08-03~04): eks 루트 + graviton + addon 핀
```

## AI 에이전트 가이드

### 배포 순서
`networking`이 반드시 **먼저** apply되어야 한다 — eks 루트가 태그로 VPC를 조회하기 때문이다:
```hcl
data "aws_vpc" "main" {
  filter { name = "tag:Name";    values = ["vpc-ref-dev-an2-main"] }
  filter { name = "tag:Workload"; values = ["ref"] }
}
```
networking이 apply되지 않으면 eks plan이 빈 결과를 반환한다 (에러가 아니라そっと 실패 — 주의).

### State 격리
- 각 루트가 S3에 고유한 state 파일을 가진다 (버킷은 공유, 키만 다름)
- 루트 사이에 `terraform_remote_state` 데이터 소스 없음
- 결합은 **태그 규약으로만** 이루어진다 (클러스터명 상수 `eks-ref-dev-an2-main-01`)

### 새 루트 추가
1. `live/dev/<name>/` 디렉토리를 표준 IaC 파일로 생성
2. `deploy-network.yml` 패턴을 따라 `deploy-<name>.yml` 워크플로 생성
3. 별도 concurrency group과 state key 설정
4. notepad.md Phase 기록에 추가

<!-- MANUAL: -->