# spoke 계정 생애주기: 구축과 철거

**읽는 사람**: spoke(예: asset 계정의 dev)의 인프라를 구축하거나 철거하는 사람.

> ⚠️ **hub가 먼저 구축되어 있어야 한다.** spoke는 hub의 `argocd_hub_pod_identity` Role·TGW·프리픽스
> 리스트에 의존한다. `hub-lifecycle.md`부터 본다.
> **검증 상태**: 구축·철거 둘 다 `eks-reference-infra`의 dev(spoke 첫 인스턴스)로
> 실환경 검증했다. spoke 단독 teardown 시 hub 쪽 잔존물 처리(13절)는 **열린 질문**이다.

레퍼런스 구현이 `eks-reference-infra`의 `live/dev/`에 있다.

---

## 구축

### 0. 준비물

hub와 같다: `tofu`·`aws`·`gh`·`session-manager-plugin`·`jq`. hub를 구축할 때 이미 설치했다면
이 절은 건너뛴다.

### 1. 착수 전에 확정할 값: hub와 다른 것만

| 값 | 예 | 왜 되돌릴 수 없나 |
|----|-----|------------------|
| `SPOKE_ENV` | `dev` | 부트스트랩 자원 이름 전체(버킷·Role)에 들어간다 |
| 계정 | asset 계정 | 계정 자체는 안 바뀐다(옮기려면 재부트스트랩) |
| VPC CIDR(uniq) | hub와 겹치지 않는 대역 | VPC 재생성. hub와 dup 허용 대역은 RFC 6598로 겹쳐도 된다 |
| 클러스터 이름 | `eks-demo-dev-an2-main-01` | 클러스터 재생성 |

hub와 공통인 값(workload 코드·리전·EKS public 여부)은 `hub-lifecycle.md` 1절과 같다.
같은 배포 저장소 안의 다른 env이므로 workload 코드는 반드시 hub와 동일해야 한다.

### 2. 배포 저장소: hub와 같은 repo, 새 env 하나

```
live/dev/networking/       hub와 같은 repo에 env만 새로 추가
live/dev/eks/
```

`bootstrap/`·`.github/workflows/`는 hub를 구축할 때 이미 있다. 새로 만들지 않는다.

### 3. 부트스트랩: `BOOTSTRAP_TARGET=spoke SPOKE_ENV=<env>`

```bash
export EXPECTED_ACCOUNT=<asset 계정 12자리 ID>   # 필수. hub와 다른 계정이다
cd bootstrap
BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev AWS_PROFILE=asset ./bootstrap.sh
BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev AWS_PROFILE=asset ./verify.sh
```

기대 상태(SSOT)는 `../bootstrap/README.md`가 가진다(`config.sh`는 그 코드 측면이다).
**`AWS_PROFILE`을
반드시 spoke 계정 프로파일로 지정한다.** 기본 프로파일이 hub(team) 계정이면 조용히 hub를
다시 건드린다.

OIDC provider·입구/실행 Role은 **spoke 계정 안에 별도로** 생긴다(hub와 공유하지 않는다.
OIDC provider는 URL당 계정에 1개 제약이라 계정이 다르면 각자 가진다). `sub` 2패턴의
`environment` 값은 `SPOKE_ENV`(예: `dev`)다.

### 4. 네트워크 (L1): TGW attachment + RAM 초대 수락

hub와 같은 방식으로 `backend.hcl`을 만들고(`key = "dev/networking.tfstate"`) `init`·
`validate`까지 로컬에서 한다. `main.tf`는 hub의 TGW·프리픽스 리스트를 `data` 소스로
발견해 attachment와 라우트를 만든다.

```bash
gh workflow run deploy-dev-network.yml --ref main -f action=apply
```

✅ **apply 안에서 자동으로 수락한다. 사람 개입이 필요 없다.**
RAM 초대는 `deploy-dev-network.yml` plan job의 CI 단계가 수락한다(설계 배경은
`iac-module-library`의 `docs/architectures/gitops-hub-spoke/aws/network.md` 「RAM 초대 수락은
CI 단계다」, 왜 Terraform 리소스로는 안 되는지는 `live/dev/networking/main.tf`의
`aws_ec2_transit_gateway_vpc_attachment` 바로 위 ⛔ 주석에 있다). 완전 신규 spoke의 첫
apply든 teardown 이후 재배포든 이 CI 단계가 처리한다. 사람이 CLI를 직접 돌리거나
import 블록을 추가할 필요가 없다.

⛔ **"hub 쪽 RAM principal association이 사라져 있을 수 있다"는 문제는 재발하지 않는다.**
`aws_ram_resource_share_accepter`는 Terraform이 생성·삭제하는 리소스가 아니므로, spoke
teardown이 그 리소스를 destroy하며 `DisassociateResourceShare`를 호출하던 경로가 없다.
hub의 association은 teardown 이후에도 ACTIVE로 남는다.

> 🔑 **hub→spoke 방향 라우트는 이 apply만으로 안 끝난다.** hub의 networking이 spoke보다
> 먼저 서므로, 그 시점엔 spoke attachment가 없어 hub 최초 apply에 못 들어간다. spoke
> networking apply(=RAM 수락) 뒤 **hub networking을 한 번 더 재적용**해야 hub→spoke 라우트가
> 채워진다. 전체 순서: hub networking → hub eks → spoke networking → spoke eks → **hub
> networking 재적용**. TGW 전용으로 따로 기억할 단계는 이 마지막 재적용 하나뿐이다.

🔴 **완전 신규(또는 완전 재배포) VPC의 첫 apply에서 `aws_route.to_hub`가 "Invalid for_each
argument"로 plan 자체를 거부할 수 있다.** `route_table_ids_by_group["node-uniq"]`
는 module output(리스트)인데, 그 라우트테이블 자신이 **같은 apply 안에서 처음 생성**되면
apply 시점까지 값을 모른다. 그런 리스트를 `for_each` 키로 쓰면 OpenTofu가 plan을 거부한다.
고정 개수(AZ 수)로 만든 정적 인덱스 집합을 `for_each` 키로 쓰고, 실제 라우트테이블 ID는 그
인덱스로 apply 시점에 조회하도록 바꾼다(코드는 `eks-reference-infra` `live/dev/networking/main.tf`
커밋 이력 참조). 처음부터 이렇게 작성하면 재배포 때마다 이 실패를 다시 겪지 않는다.

### 5. EKS와 workbench (L2): `cross-account-trust-role` 연결

hub와 같은 세 모듈(`workbench`→`eks-cluster`) 연결 순서 경고가 그대로 적용된다
(`hub-lifecycle.md` 5절). 여기에 `cross-account-trust-role` 모듈을 추가한다. trust
policy의 Principal이 hub의 `argocd_hub_pod_identity` Role ARN이다.

```bash
gh workflow run deploy-dev-eks.yml --ref main -f action=apply
```

⚠️ **hub의 `argocd_hub_pod_identity`가 아직 `enable=false`여도 이 apply는 성공한다.** AWS는
trust policy의 Principal 존재를 **생성 시점에 검증하지 않는다.** 순서를 걱정해 hub를 먼저
켤 필요는 없지만, 크로스 계정 인증이 실제로 되려면 결국 hub 쪽도 켜야 한다(6절에서 등록한
뒤 확인).

### 6. GitOps 등록: hub에 `cluster-secret.yaml` 신규 등록

spoke는 자체 ArgoCD가 없다. hub의 ArgoCD가 크로스 계정으로 원격 관리하므로, **GitOps
저장소에 이 클러스터를 등록**하는 것이 spoke의 "L3"에 해당한다. hub처럼 자기 `argocd-seed.sh`
를 돌리지 않는다.

`<project>-platform-gitops`에 `clusters/<env>/<cluster-name>/cluster-secret.yaml`을
추가한다:

| 필드 | 값 | 확인 방법 |
|---|---|---|
| `metadata.labels.environment` | `<SPOKE_ENV>` | baseline ApplicationSet이 이 라벨의 **존재만** 검사(값은 경로 해석용) |
| `metadata.labels.vpcName`·`karpenterNodeRole` 등 | per-cluster addon 파라미터 | 실측한다(추정 금지): `aws ec2 describe-vpcs`·`aws iam list-roles` |
| `addon-<name>: enabled` 라벨 | opt-in 카탈로그 구독 | 필요한 addon만 |
| `stringData.server` | **EKS API endpoint**(`https://<hash>.<region>.eks.amazonaws.com`) | ⚠️ 클러스터 ARN이 아니다. ARN 계약은 AWS 완전관리형 "EKS Capability for Argo CD"(이 프로젝트가 안 쓰는 별개 제품) 전용, self-managed ArgoCD 공식 계약은 API endpoint다 |
| `stringData.config.awsAuthConfig.roleARN` | `cross-account-trust-role`이 만든 Role ARN(5절) | |
| `stringData.config.tlsClientConfig.caData` | 클러스터의 CA(base64) | `aws eks describe-cluster --query 'cluster.certificateAuthority.data'` |

root-app이 이 커밋을 pull하면 baseline ApplicationSet이 이 클러스터를 fan-out 대상에
자동 추가한다. **재배포 시 재등록**은 14절이다. 처음 등록과 절차는 같지만 `server`·`caData`가
반드시 바뀐다는 것과 기존 `addon-*` 라벨을 그대로 옮겨야 한다는 함정이 있다.

⚠️ **`projects/platform.yaml`의 AppProject `destinations`는 편집하지 않는다.** 위 표만
채우면 되고, fan-out과 별개로 존재하는 세 번째 가드레일(AppProject `destinations`,
어느 클러스터로 배포해도 되는지 정하는 목록)은 이미 region 단위 glob으로 spoke EKS API
endpoint 전체를 허용해뒀다. endpoint 정확한 값을 그 목록에 박아두면 14절(재배포)마다 그
파일도 같이 고쳐야 하는 함정이 생기기 때문이다. 실제 접근 게이트는 그 목록이 아니라 이
저장소에 `cluster-secret.yaml`을 커밋할 git 권한과 `cross-account-trust-role`의 trust
policy다.

### 7. 완료 판정

hub 7절과 같은 6항목을 이 spoke 클러스터 기준으로 확인한다. 3번(root Application이 커밋
SHA를 읽음)·4번(Application `Synced`/`Healthy`)은 hub의 ArgoCD에서 확인한다. spoke 자신에는
ArgoCD가 없다.

---

## 철거

### 8. 시작 전에: 공용 계정이면 특히 읽는다

hub 8절과 동일한 원칙(태그로 특정, 이름으로 지우지 않는다)이 spoke 계정에도 그대로
적용된다. `--profile`만 spoke 계정 것으로 바꾼다.

### 9. 0단계: 삭제 보호 해제

hub 10절과 같은 2단계 apply 패턴(`deletion_protection = false` → 커밋 → apply). VPC와
EKS가 다르게 반응하는 것도 동일(hub 10절 참조).

```bash
gh workflow run deploy-dev-eks.yml     --ref main -f action=apply
gh workflow run deploy-dev-network.yml --ref main -f action=apply
```

### 10. 1단계: IaC 밖 자원 선처리 (컨트롤러 정지 대상이 hub다)

⚠️ **hub-lifecycle.md 11절과 다르다.** spoke는 자체 ArgoCD가 없으므로 "컨트롤러를 scale
0"할 대상이 spoke 안에 없다. hub의 ApplicationSet이 이 spoke를 계속 fan-out 대상으로
보는 한, spoke 안의 LB·PVC·NodePool을 지워도 hub가 되살린다(대상만 원격일 뿐 hub 11절과
같은 메커니즘).

🔴 **cluster-secret.yaml을 한 번에 통째로 지우지 않는다.** 이 Secret은 두 역할을 겸한다:
①ArgoCD가 이 클러스터에 접속할 자격증명(`server`/`config`), ②ApplicationSet cluster
generator가 이 클러스터를 fan-out 대상으로 판단하는 라벨(`environment`·`tier`·`addon-*`).
통째로 지우면 ArgoCD가 그 클러스터에 접속할 방법 자체를 잃어(`no clusters with this name`,
argoproj/argo-cd#5817) cascade delete가 물리적으로 불가능해지고, Application 추적 기록만
사라질 뿐 실제 Deployment·DaemonSet·Webhook·ClusterPolicy는 spoke 클러스터에 orphan으로
남는다. **두 역할을 분리해 2단계로 진행한다**:

```bash
# ① 매칭 라벨만 먼저 지운다 — secret-type과 server/config(접속 정보)는 그대로 둔다.
#    이렇게 하면 ApplicationSet은 이 클러스터를 더 이상 발견 못 해 Application을
#    정상적으로 제거하려 하고, 그 순간에도 ArgoCD는 여전히 이 클러스터에 접속 가능해
#    cascade delete(resources-finalizer)가 실제로 완주한다.
#    (kubectl delete로 Application을 직접 지우는 것도 통하지 않는다 — 매칭이 살아있는 동안은
#     selfHeal이 즉시 되살린다. 반드시 "매칭을 끊기"여야 한다.)

# ② hub의 root-app이 새 커밋을 실제로 반영했는지 확인
#    (Synced/Healthy만으로는 반영을 보장 못 한다 — sync revision이 새 커밋 SHA인지 본다)
kubectl -n argocd get application root-app -o jsonpath='{.status.sync.revision}'

# ③ 이 spoke가 만든 Application들이 실제로 pruned됐는지 hub에서 확인
kubectl -n argocd get applications | grep <spoke-cluster-name>   # 결과 없어야 함

# ④ Application 추적 기록 삭제와 실제 리소스 삭제는 별개다 — ③만으로는 부족하니
#    이 spoke 클러스터 자체에서 addon 컨트롤러가 실제로 사라졌는지 확인한다.
kubectl get pods -A   # ArgoCD 관리 addon(aws-lbc·keda·kyverno·karpenter 등) 파드가 없어야 함
kubectl get nodepools 2>&1   # Karpenter를 쓰면 NodePool CR도 없어야 함(addon 자신이 소유)

# ⑤ ④는 GitOps가 만든 addon 자신만 다룬다 — 실제 워크로드가 만든 LB·PVC·Karpenter
#    NodeClaim(addon이 아니라 사용자가 배포한 앱이 낳은 것)은 여전히 별도 대상이다.
#    hub-lifecycle.md 11절과 동일한 패턴으로 이 spoke의 workbench에서 정리한다 —
#    hub가 이미 fan-out을 멈췄으니 지워도 되살아나지 않는다.

# ⑥ ④⑤ 확인 후에만 cluster-secret.yaml을 완전히 삭제해 클러스터 등록 자체를 해제한다
#    (server/config까지 포함해 전체 삭제 — 이 시점엔 정리할 것이 이미 없어 안전하다)
```

🔴 **④에서 NodePool은 사라졌는데 EC2NodeClass가 `deletionTimestamp`를 낀 채 남아 있으면
Karpenter의 `karpenter.k8s.aws/termination` finalizer가 스턱된 것이다.** ApplicationSet이
karpenter 컨트롤러 Application과 karpenter-nodepool Application(NodePool·EC2NodeClass 소유)을
병렬로 prune하면, finalizer를 처리해야 할 컨트롤러 파드가 먼저 사라져 아무도 처리하지 못한다
(`kubectl get ec2nodeclasses`는 계속 남고, `argocd-application-controller` 로그는 "1 objects
remaining for deletion"을 반복한다). 복구하기 전에 AWS 실물(Launch Template) 오르판이 없는지
먼저 확인한다:

```bash
aws ec2 describe-launch-templates --filters "Name=tag:Name,Values=*<workload>-<env>*"
kubectl patch ec2nodeclass <name> --type merge -p '{"metadata":{"finalizers":[]}}'
```

오르판이 없으면(이 spoke에서 Karpenter 노드가 한 번도 뜬 적 없는 경우 등) 위 `patch`로
finalizer를 강제로 비워 즉시 GC시킨다. 오르판이 있으면 먼저 그 EC2 인스턴스를 정리한 뒤
patch한다.

**순서가 중요하다.** ①~⑤를 건너뛰고 Secret을 한 번에 지우면 hub의 Application 추적
기록은 사라지지만 실제 addon과 워크로드 잔존물은 spoke에 orphan으로 남는다. spoke
EKS 클러스터 자체를 destroy(11절)하면 결국 함께 사라지므로 destroy 자체를 막지는
않지만, 클러스터를 재파괴하지 않고 addon만 철거하려는 시나리오(예: 재구성 리허설)에서는
치명적이다.

### 11. 2단계 · 3단계: destroy

hub 12절과 같은 패턴, 워크플로 이름과 `confirm` 문자열만 다르다.

```bash
gh workflow run deploy-dev-eks.yml --ref main \
  -f action=destroy -f confirm='destroy live/dev/eks'

gh workflow run deploy-dev-network.yml --ref main \
  -f action=destroy -f confirm='destroy live/dev/networking'
```

### 12. 4단계: 잔존물 검증

```bash
WORKLOAD=<code> ENVIRONMENT=dev AWS_PROFILE=asset ./scripts/teardown-verify.sh
```

⚠️ **`AWS_PROFILE`을 spoke 계정으로 정확히 지정한다.** `team`(hub)으로 잘못 실행하면 dev
자원이 하나도 안 잡혀 "잔존물 없음"으로 오판한다. 스크립트는 지정된 계정만 본다. 나머지
판정 기준(NAT·EC2·EBS·EIP·ALB/NLB·EKS·ENI·로그 그룹 순위)은 hub 13절 표와 같다.

### 13. spoke 단독 teardown 시 hub TGW 잔존 라우트

**hub가 destroy된 경우**는 다르다: hub networking을 destroy하면 프리픽스
리스트·TGW·RAM 공유가 전부 사라져, spoke networking을 먼저 재생성해도
`data.aws_ram_resource_share` 조회가 즉시 에러로 실패한다(순서를 잊어도 안전하게
드러난다). 통상 순서(`hub networking → hub eks → spoke networking → spoke eks → hub
networking 재적용`)를 그대로 반복하면 되고, **spoke eks apply를 생략하지 않는다**: hub
재생성 시 프리픽스 리스트도 새 ID로 바뀌므로, spoke eks가 그 새 ID를 집으려면 apply가 한
번은 돌아야 한다(data 소스는 이미 배포된 리소스를 저절로 갱신하지 않는다).

spoke만 단독으로 destroy하고 hub는 그대로 두는 경우는 아래를 본다.

hub의 spoke 라우트(`aws_route.vpc_to_spoke`·`aws_ec2_transit_gateway_route.tgw_rt_to_spoke`)는
**살아있는 데이터소스**(`state=available` 필터의 attachment 자동 발견)로 개수가 결정되는
`for_each` 기반이다. spoke의 attachment가 destroy로 사라지면:

- AWS는 그 라우트를 **즉시 지우지 않는다.** attachment 참조가 끊긴 static route를
  `blackhole` 상태로 자동 전환한다(라우트 엔트리 자체는 남고, 트래픽만 조용히 드롭된다).
- hub의 Terraform state는 이 전환을 스스로 알아채지 못한다. `for_each`가 참조하는
  데이터소스가 그 attachment를 더 이상 반환하지 않게 됐을 뿐이라, **다음 hub networking
  plan/apply를 실제로 돌려야** 그 spoke의 라우트 2개가 destroy 대상으로 잡히고 정리된다.
  **코드 수정은 필요 없다.** TGW 자체·RAM 공유·hub 자신의 attachment/route는 그대로 유지된 채
  그 spoke의 라우트만 없어진다.
- hub를 재적용하지 않고 방치해도 에러는 안 난다. blackhole 라우트가 트래픽만 조용히
  막을 뿐이고, 다음 spoke가 재배포돼도 그 spoke의 CIDR과 겹치지 않는 한 무관하다.

⚠️ `deploy-hub-network.yml`은 `workflow_dispatch`에서 **plan job이 끝나면 곧바로 apply
job이 같은 run 안에서 이어진다.** "plan만 미리 보고 멈추는" 옵션은 없다. 정리할 각오가
됐을 때만 dispatch한다.

### 14. 재배포 시 GitOps 재등록

spoke EKS를 destroy 후 재생성하면 클러스터 이름이 같아도 API endpoint·CA 인증서는 **반드시
새로 발급**된다. 6절에서 등록한 `cluster-secret.yaml`은 옛 값을 그대로 갖고 있으므로, 재적용
없이는 hub ArgoCD가 죽은 엔드포인트를 계속 찌른다.

```bash
aws eks describe-cluster --profile asset --region ap-northeast-2 --name <cluster-name> \
  --query 'cluster.{endpoint:endpoint,ca:certificateAuthority.data}'
```

`server`·`caData`만 갱신하고 **`addon-*` 라벨은 그대로 유지**한다(빠뜨리면 addon 구독이
조용히 빠진 채 재배포된다. 갱신 전에 `git diff`로 기존 라벨 목록을 먼저 확인한다).
`roleARN`은 안 바뀐다. `cross-account-trust-role`의 Role 이름은 네이밍 규약상 결정적이라
재생성 후에도 동일하다.

### 15. 되돌릴 수 없는 것 / 자주 막히는 지점

hub 15·16절과 동일하다(state 버킷·로그 그룹·EBS·OIDC provider는 되돌릴 수 없고, ENI 잔존·
`prevent_destroy`·state lock 등 자주 막히는 지점도 같다). 여기서 반복하지 않는다. spoke
고유의 막히는 지점은 12절(profile 실수)과 13절(hub 잔존 라우트) 두 가지뿐이다.