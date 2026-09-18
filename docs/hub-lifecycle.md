# hub 계정 생애주기: 구축과 철거

**읽는 사람**: hub(team 계정)의 인프라를 구축하거나 철거하는 사람.

레퍼런스 구현이 `eks-reference-infra`의 `live/hub/`에 있다. spoke(예: dev)는
`spoke-lifecycle.md`를 본다(hub가 먼저 구축되어 있어야 spoke를 구축할 수 있다).

---

## 구축

### 0. 준비물

| 항목 | 확인 |
|------|------|
| AWS 계정 + 관리자 권한 | `aws sts get-caller-identity` |
| GitHub org + 저장소 생성 권한 | |
| 로컬 도구 | `tofu` · `aws` · `gh` · `session-manager-plugin` · `jq` |

```bash
brew install opentofu awscli gh jq
brew install --cask session-manager-plugin
```

### 1. 착수 전에 확정할 값

**되돌릴 수 없는 것들이다.** 판단 근거는 `iac-module-library`의
`docs/architectures/gitops-hub-spoke/aws/README.md` 「되돌릴 수 없는 선택」이 소유한다.

| 값 | 예 | 왜 되돌릴 수 없나 |
|----|-----|------------------|
| `workload` 코드 | `demo` | 모든 리소스 이름에 들어간다 |
| 리전 | `ap-northeast-2` (`an2`) | 전면 재구축 |
| VPC CIDR | `10.50.0.0/24` | VPC 재생성 |
| 클러스터 이름 | `eks-demo-hub-an2-main-01` | 클러스터 재생성 |
| EKS 엔드포인트 public 여부 | `false` | 정책상 되돌리기 어렵다 |
| hub를 어디 둘지(같은 계정/분리 계정) | 분리 계정 | 「질문 D」 계열 재구축 |

### 2. 배포 저장소 만들기

```bash
gh repo create <org>/<project>-infra --private
```

```
bootstrap/                 state 버킷 · OIDC provider · Role   (IaC 밖)
live/hub/networking/       VPC
live/hub/eks/               EKS + workbench
live/hub/tgw/               Transit Gateway
.github/workflows/         배포 루트마다 워크플로 하나
```

`live/hub/networking`과 `live/hub/eks`는 **state를 분리**한다. 결합은
`terraform_remote_state`가 아니라 **Name·태그 기반 `data` 조회**로만 한다.

### 3. 부트스트랩: state 버킷 · OIDC · Role

```bash
export EXPECTED_ACCOUNT=<12자리 계정 ID>   # 필수. 기본값이 없다
cd bootstrap && ./bootstrap.sh             # BOOTSTRAP_TARGET=hub 가 기본값
./verify.sh                                # drift 확인만
```

기대 상태(SSOT)는 `../bootstrap/README.md`가 가진다: 값을 여기 다시 적지 않는다.
`config.sh`는 그 코드 측면이다.

**순서가 자유롭지 않다**: OIDC provider → 입구 Role(신뢰=OIDC) → 실행 Role(신뢰=입구) → 입구
inline 정책(Resource=실행 Role). IAM은 신뢰 정책의 principal이 실제로 존재하는지 검증한다:
아직 없는 Role을 principal로 쓰면 `MalformedPolicyDocument`다. `Resource`는 존재 검증을 안
받으므로 입구 inline 정책이 마지막이어도 된다. **IAM은 eventual consistency다**:
`bootstrap.sh`는 `Invalid principal`일 때만 재시도한다.

**OIDC `sub` 패턴 확인**: 2026-07-15 이후 생성된 저장소는 `sub`에 이름 대신 숫자 ID를 쓴다
(`repo:<org>@<org_id>/<repo>@<repo_id>:...`): 신뢰 정책을 쓰기 전에 실제 토큰의 `sub`를
확인한다, 추정하지 않는다.

버킷명은 **git에 넣지 않는다.** GitHub 저장소 변수 `HUB_TF_STATE_BUCKET`과 로컬
`backend.hcl`에만 둔다.

### 4. TGW와 네트워크 (L1)

TGW(`live/hub/tgw`)는 네트워킹과 **분리된 배포 루트**이고, **반드시 먼저 apply한다**(같은
apply 안에 있으면 TGW ID가 plan 시점에 unknown이라 spoke 자동 발견 `for_each`가 `Invalid
for_each argument`로 실패한다. `needs:`로 순서 강제는 불가하다).

아래 네트워크와 같은 방식으로 초기화한다(`key = "hub/tgw.tfstate"`). CIDR(`locals.cidr_uniq`)은 네트워크와 반드시 같아야 한다(state 미공유, 사람이 유지).

```bash
gh workflow run deploy-hub-tgw.yml --ref main -f action=apply
```

run은 plan까지 돌고 apply job은 environment 승인을 기다린다. Summary 탭의 plan 요약을 읽고 **Review deployments**로 승인하면 같은 run이 저장된 plan을 적용한다(`gh run watch <run-id>`).
main push가 만든 run도 같은 경로라, 이미 승인 대기 중인 run이 있으면 dispatch 없이 그것을 승인한다. 이 문서의 모든 apply 명령이 같다.

```bash
cat > live/hub/networking/backend.hcl <<'EOF'
bucket       = "<bootstrap.sh 가 출력한 버킷명>"
key          = "hub/networking.tfstate"
region       = "ap-northeast-2"
use_lockfile = true
EOF

tofu -chdir=live/hub/networking init -backend-config=backend.hcl
tofu -chdir=live/hub/networking validate
```

`backend.hcl`은 `.gitignore` 대상이라 루트마다 새로 만든다. 커밋하지 않는다.

> 🔴 **로컬에서 `plan`·`apply`는 성립하지 않는다.** provider가 실행 Role을 assume하는데 그
> Role은 입구 Role만 신뢰한다: 개인 IAM user로는 관리자여도 `AccessDenied`다. **로컬은
> `init`+`validate`까지**이고, 그 위는 전부 워크플로가 한다.

`main.tf`는 `iac-module-library`의 `docs/module-catalog.md`의 연결 예시를 따른다. `eks_cluster_name`을
넘겨 EKS 자동 발견용 서브넷 태그를 붙인다(클러스터를 만들기 전에 해야 한다).

```bash
gh workflow run deploy-hub-network.yml --ref main -f action=apply
```

> **L1 apply 전까지 EKS 워크플로의 plan은 실패한다**(`no matching EC2 VPC found`), 순서가
> 있다는 신호이지 고장이 아니다.

### 5. EKS와 workbench (L2)

같은 방식으로 `live/hub/eks`를 초기화한다(`key = "hub/eks.tfstate"`).

**세 모듈의 연결 순서**에 주의한다. `workbench`는 자기 SG ID와 Role ARN을 출력하고,
`eks-cluster`가 그것을 `access_entries`와 `cluster_security_group_additional_rules`로
받는다: 배포 루트가 연결하며, 모듈끼리 직접 참조하지 않는다.

> 🔴 **`workbench`에는 `eks_cluster_name`을 `module.eks.cluster_name`으로 넘긴다**: `local`
> 문자열을 쓰면 순서 간선이 없어져 병렬 생성되고 `update-kubeconfig`가 실패한다. ⛔
> `depends_on = [module.eks]`로 풀지 않는다(순환). ⚠️ `eks_cluster_arn`은 `local` 유지:
> 실 ARN은 plan 시점 unknown이라 `count`를 깨뜨린다.

`workbench`의 도구 핀은 nullable이다.

```hcl
kubectl_version = "v1.34.1"
helm_version    = "v3.21.3"
argocd_version  = "v3.5.0"     # ArgoCD 차트 appVersion과 맞춘다
```

apply 후 접근을 확인한다:

```bash
aws ssm start-session --target <instance-id>
kubectl get nodes            # KUBECONFIG 설정 없이 동작해야 한다
```

### 6. GitOps (L3)

hub만 자기 `argocd-seed.sh`를 돈다. spoke는 자체 ArgoCD가 없어 이 절이 없다(`spoke-lifecycle.md`가 hub에 등록하는 절차를 갖는다).

```bash
gh repo create <org>/<project>-platform-gitops --public
```

`eks-platform-gitops`의 레이아웃을 본뜬다. **이 저장소에 `.tf`를 두지 않는다.** public이어야 한다. ArgoCD가 repository Secret 없이 익명으로 읽고 workbench도 자격증명 없이 클론한다. private이면 seed의 preflight가 익명 `ls-remote`에서 멈춘다. `argocd-seed.sh`는 그 저장소의 `bootstrap/`이 소유한다(workbench가 그 저장소만 클론한다).

```bash
git clone https://github.com/<org>/<project>-platform-gitops.git "$GITOPS_REPO_DIR"          # workbench에서
cd "$GITOPS_REPO_DIR/bootstrap" && ./argocd-seed.sh --dry-run && ./argocd-seed.sh
```

스크립트는 매니페스트를 **생성하지 않는다.** GitOps 저장소에 커밋된 파일을 그대로 apply한다:
`--set`도, 인라인 heredoc 매니페스트도 쓰지 않는다.

**완료 조건: 비밀번호 교체**는 선택이 아니다. 절차는 [`runbooks.md`](runbooks.md)
「3. ArgoCD 관리자 비밀번호 교체」가 소유한다.

### 7. 완료 판정

| # | 확인 | 명령 |
|---|------|------|
| 1 | 부트스트랩 drift 없음 | `./bootstrap/verify.sh` |
| 2 | 노드가 Ready | `kubectl get nodes` |
| 3 | root Application이 커밋 SHA를 읽음 | `kubectl -n argocd get application root-app -o jsonpath='{.status.sync.revision}'` |
| 4 | 전 Application이 `Synced`/`Healthy` | `kubectl -n argocd get applications` |
| 5 | 초기 비밀번호 Secret 삭제됨 | `kubectl -n argocd get secret argocd-initial-admin-secret` → NotFound |
| 6 | CI 게이트 통과 | GitHub Actions |

3번에서 값이 `main`이면 아직 설정값이다. 4번은 **두 열을 따로 본다**: `Synced`는 "Git이
요구한 것을 적용했다"일 뿐이고, 그 요구 자체가 틀렸으면 여전히 `Synced`다.

---

## 철거

### 8. 시작 전에: 공용 계정이면 특히 읽는다

**삭제는 이 자산에서 가장 위험한 작업이다.** 생성은 잘못해도 내 것만 늘어나지만, 삭제는
잘못하면 남의 것이 사라진다.

```bash
aws --profile <p> --region <r> ec2 describe-vpcs --query 'length(Vpcs)'
aws --profile <p> --region <r> eks list-clusters
```

여러 개가 나오면 공용 계정이다. **이름을 눈으로 보고 지우지 않는다**: 이후 모든 수동 정리는
반드시 태그로 특정한다.

```bash
--filters "Name=tag:Name,Values=*<workload>-<env>*"
```

### 9. 삭제는 생성의 역순이 아니다

`tofu destroy`는 **IaC가 만들지 않은 것을 모른다.**

| 무엇이 남는가 | 누가 만들었나 | tofu가 아는가 |
|--------------|-------------|--------------|
| Karpenter 노드 (EC2) | Karpenter 컨트롤러 | ❌ |
| ALB · TargetGroup | AWS Load Balancer Controller | ❌ |
| EBS 볼륨 | PVC (CSI 드라이버) | ❌ |
| ENI | VPC CNI | ❌ |
| CRD | helm 차트(`crds.keep: true`) | ❌ |
| CloudWatch 로그 그룹(재생성분) | AWS가 destroy 도중 자동 생성 | ❌ |

**이것들을 먼저 치우지 않으면**: 노드는 계속 과금되고, ALB와 ENI는 VPC 삭제를 막는다.

0단계 삭제 보호 해제 → 1단계 클러스터 안에서 IaC 밖 자원 선처리 → 2단계 L2 destroy(EKS·
workbench) → 3단계 L1 destroy(VPC·TGW 순) → 4단계 잔존물 검증(destroy의 "성공" 보고를 믿지 않는다).

> 🔑 **삭제는 한 번의 명령이 아니라 수렴 과정이다.** ArgoCD가 지운 것을, CloudWatch가 지운
> 로그 그룹을 각각 되살린다: "명령은 성공했는데 상태가 원래대로"다. 4단계는 마무리가 아니라
> 절차의 일부다.

### 10. 0단계: 삭제 보호 해제

`deletion_protection = true`면 destroy가 실패한다. 2단계로 나눠 apply한다.

```hcl
module "vpc" { deletion_protection = false ... }
module "eks" { deletion_protection = false ... }
```

```bash
gh workflow run deploy-hub-eks.yml     --ref main -f action=apply
gh workflow run deploy-hub-network.yml --ref main -f action=apply
```

VPC 모듈은 `prevent_destroy`를 쓴다. **CLI 플래그로 우회할 수 없다.** 로컬 `tofu apply`가
아니다: 이 apply도 워크플로에서만 실행된다.

⛔ **`false` 커밋을 되돌리는 것까지가 이 단계다.** 파기가 끝나면 `true`로 복원한다.

> `git push`가 pre-push 훅에서 막히면, 훅의 `tofu validate`가 backend 자격증명을 요구하는
> 것이다. `AWS_PROFILE=<프로파일> git push`로 넘긴다. `--no-verify`로 훅을 끄지 않는다.

> 🔴 **VPC와 EKS는 이 단계에서 다르게 반응한다.** VPC의 `deletion_protection`은
> `prevent_destroy`(Terraform lifecycle 메타 인자)일 뿐 AWS 쪽 실제 속성이 아니다: `false`로
> apply해도 `No changes.`가 정상이다. EKS는 AWS 네이티브 속성이라 apply가 실행돼야 반영된다.

### 11. 1단계: IaC 밖 자원 선처리

hub는 자기 ArgoCD를 스스로 멈춘다(아래). spoke는 다르다, `spoke-lifecycle.md`를 본다.
workbench에서 실행한다.

**먼저 ArgoCD 컨트롤러를 멈춘다.** 살아 있으면 아래 ②③④를 지우는 족족 되살린다.
`syncPolicy`를 끄는 것으로는 부족하다: App-of-Apps라 root-app이 그 설정 자체를 복원한다.

```bash
# ① 컨트롤러 정지
kubectl -n argocd scale statefulset argocd-application-controller --replicas=0
kubectl -n argocd scale deployment  argocd-applicationset-controller --replicas=0

# ② LoadBalancer 타입 Service·Ingress·Gateway
kubectl delete ingress --all -A
kubectl delete svc -A --field-selector spec.type=LoadBalancer
kubectl delete gateway --all -A

# ③ PVC
kubectl delete pvc --all -A

# ④ Karpenter NodePool
kubectl delete nodepool --all
kubectl delete ec2nodeclass --all
```

**순서가 중요하다.** ①을 건너뛰면 ArgoCD가 ②③④를 되살린다. ④를 건너뛰고 클러스터를 지우면
Karpenter 컨트롤러가 먼저 죽어 노드가 고아가 된다. `gateway.k8s.aws/alb`도 `Gateway`만으로 ALB를 만든다.

확인: **지운 직후가 아니라 30초쯤 뒤에 본다.**

```bash
kubectl get nodes
kubectl get nodepool -A
aws elbv2 describe-load-balancers --query 'LoadBalancers[?VpcId==`<vpc-id>`]'
```

> 🔴 `kubectl get nodes`에 노드가 남아 있어도 실패가 아닐 수 있다: NodePool의 `NODES`가
> 원래 `0`이면 남은 건 관리형 노드그룹(시스템 계층) 소속이라 2단계 `tofu destroy`가 회수한다.

### 12. 2단계 · 3단계: destroy(EKS → 네트워크 → TGW)

🔴 **파기도 워크플로로 한다.** 로컬 사용자가 계정 관리자여도 `sts assume-role`이
`AccessDenied`다.

```bash
gh workflow run deploy-hub-eks.yml --ref main \
  -f action=destroy -f confirm='destroy live/hub/eks'

gh workflow run deploy-hub-network.yml --ref main \
  -f action=destroy -f confirm='destroy live/hub/networking'

gh workflow run deploy-hub-tgw.yml --ref main \
  -f action=destroy -f confirm='destroy live/hub/tgw'
```

`confirm`에 루트 이름을 손으로 적어야 한다. `plan`만 `-destroy`로 갈리고 apply는 생성과 같은
job이다. **TGW는 반드시 마지막이다**: hub 자신의 attachment가 `live/hub/networking`
소속이라, 그게 먼저 사라져야(attachment `deleted`) TGW destroy가 막히지 않는다.

> 🔴 **승인 지점은 plan 뒤다.** `plan` job이 `-destroy`로 끝나면 `apply` job이 승인을 기다린다.
> Summary의 파기 목록(`must be destroyed`)을 읽고 승인한다. `confirm` 문자열은 잘못된 루트를
> 파괴하는 사고만 막지 예상 밖 자원은 못 막는다: 승인 전에 13절의 `teardown-verify.sh`나
> `aws ec2 describe-*`로 태그 기준 현황을 대조한다.

```bash
aws eks list-clusters       # 우리 클러스터가 없어야 한다
```

### 13. 4단계: 잔존물 검증

```bash
WORKLOAD=<code> ENVIRONMENT=hub AWS_PROFILE=<team-profile> ./scripts/teardown-verify.sh
```

종료 코드: `0` 잔존물 없음 · `1` 잔존물 있음 · `2` 실행 불가. **아무것도 지우지 않는다.**

🔴 **`tofu destroy`가 성공해도 로그 그룹이 남을 수 있다**: 살아 있던 Flow Logs가 쓰면
CloudWatch가 같은 이름을 자동으로 만든다. state에 없으니 다음 apply에서도 안 보인다.
`retentionInDays`가 비어 있으면 손으로 지운다.

| 순위 | 자원 | 확인 |
|:---:|------|------|
| 1 | NAT Gateway | 트래픽 0이어도 시간당 과금 |
| 2 | EC2 인스턴스 | Karpenter 고아 노드 |
| 3 | EBS 볼륨(`available`) | 붙어 있지 않아도 과금 |
| 4 | Elastic IP(미연결) | 미연결일 때 과금 |
| 5 | ALB / NLB | |
| 6 | EKS 클러스터 | 노드 0대여도 컨트롤 플레인 과금 |
| 7 | ENI(`available`) | 과금은 없으나 VPC 삭제를 막는다 |
| 8 | CloudWatch 로그 그룹 | 보존 기간만큼 저장 과금 |

### 14. 부분 삭제

**GitOps만 철거**: 클러스터는 두고 ArgoCD만 뺀다. Git에서 매니페스트를 지우고 ArgoCD가
반영한 뒤 제거한다(컨트롤러를 먼저 죽이지 않는다, Git과 클러스터가 조용히 갈라진다).

```bash
helm -n argocd uninstall argocd
kubectl delete ns argocd
```

CRD는 남는다(`crds.keep: true`).

**노드만 줄이기 / 야간 정지(비용 절감)**: EKS 컨트롤 플레인은 끌 수 없다. 노드만 줄이거나
workbench를 멈춘다.

```bash
kubectl scale deployment --all --replicas=0 -n <ns>
kubectl delete nodepool <name>                        # 또는 --all
aws ec2 stop-instances --instance-ids <workbench-id>
```

관리형 노드그룹은 `managed_node_groups`의 `desired_size`를 줄여 apply한다.

### 15. 되돌릴 수 없는 것

| 지우면 | 무엇을 잃나 |
|--------|------------|
| S3 state 버킷 | state 전체. 남은 자원을 IaC로 회수할 방법이 사라진다 |
| CloudWatch 로그 그룹 | 감사 로그. 보존 요건이 있으면 먼저 export |
| EBS 볼륨 | 데이터. 스냅샷을 먼저 뜬다 |
| OIDC provider | CI가 즉시 멈춘다. 다른 저장소가 같은 provider를 쓸 수 있다 |

**state 버킷은 가장 마지막에 지운다.** versioning이 켜져 있어 일반 삭제로는 지워지지 않는다.

```bash
aws s3api delete-objects --bucket <b> --delete "$(aws s3api list-object-versions \
  --bucket <b> --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
aws s3 rb s3://<b>
```

### 16. 자주 막히는 지점

| 증상 | 원인 | 대응 |
|------|------|------|
| `DependencyViolation`: 서브넷을 지울 수 없다 | ENI가 남아 있다 | `describe-network-interfaces`로 소유자 확인 |
| VPC destroy가 몇 분째 멈춰 있다 | ENI 해제 대기 | EKS가 완전히 사라졌는지 먼저 확인 |
| `prevent_destroy`로 plan이 실패한다 | 삭제 보호 | 10절: 코드를 고쳐 apply한다 |
| destroy 후에도 노드가 살아 있다 | Karpenter 고아 | NodePool을 먼저 지웠어야 한다 |
| 클러스터를 지웠는데 ALB가 남았다 | ALBC가 먼저 죽었다 | 태그(`elbv2.k8s.aws/cluster`)로 특정해 수동 삭제 |
| state lock이 풀리지 않는다 | apply가 중단됐다 | S3의 lock 객체를 확인 후 제거 |
| 로컬 destroy가 `AccessDenied` | 실행 Role 신뢰가 입구 Role 하나뿐 | 로컬 경로는 없다: 워크플로로 파기한다 |
| 지운 리소스가 되살아난다 | ArgoCD 컨트롤러가 살아 있다 | 11절: `patch`가 아니라 컨트롤러를 `scale 0` |
| destroy 성공 후 로그 그룹이 남았다 | Flow Logs가 CloudWatch를 자동 생성 | 13절: 손으로 지운다 |
| `tofu init`이 provider SHA256SUMS 다운로드에서 실패 | runner-registry 간 일시적 네트워크 지연 | 새 dispatch가 아니라 `gh run rerun <run-id> --failed` |