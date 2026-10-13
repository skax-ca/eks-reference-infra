# EKS 마이너 업그레이드

**읽는 사람**: 이미 구축된 hub·spoke 클러스터의 Kubernetes 마이너 버전을 올리는 사람.

이 문서는 따라 하는 절차다. 순서가 왜 이런지는 `iac-module-library`의
`docs/architectures/gitops-hub-spoke/aws/upgrade.md`가, 되돌리기는 [`upgrade-rollback.md`](upgrade-rollback.md)가,
클러스터 접근과 GitOps 상태를 읽는 법은 [`runbooks.md`](runbooks.md)가, 승인 게이트와 plan을 읽는 법은
`iac-module-library/CLAUDE.md` 「배포 루트 공통」이 갖는다.

> **검증 상태**: ⏳ 표시가 붙은 줄은 실환경에서 확인하지 않았다. 소요 시간과 끊김은 dev(노드 4대)에서
> `1.35 → 1.36`으로 잰 값이다.

---

## 1. 한눈에 보기

클러스터 하나를 올리는 데 승인 4번, 머지 7번, 약 1시간이 든다. dev를 끝까지 올리고 확인한 뒤 hub를 올린다.

| # | 단계 | 저장소 | 적용 | 소요 | 워크로드 |
|---|------|--------|------|------|----------|
| 0 | 사전 점검, 값 기록 | 없음 | 조회만 | 20분 | 영향 없음 |
| 1 | disruption 차단 | `eks-platform-gitops` | 머지 | 5분 | 영향 없음 |
| 2 | 컨트롤플레인 apply | 이 저장소 | 승인 | 8~10분 | 끊김 없음 |
| 3 | 노드그룹 apply | 이 저장소 | 승인 | 9~10분 | system 노드의 파드가 옮겨진다 |
| 4 | cluster-autoscaler | `eks-platform-gitops` | 머지 | 5분 | 영향 없음 |
| 5 | **되돌릴지 정한다** | 없음 | 판단 | | |
| 6 | disruption 차단 해제 | `eks-platform-gitops` | 머지 | 5분 + 노드당 1분 | app 파드가 옮겨진다 |
| 7 | addon apply | 이 저장소 | 승인 | 2분 | 끊김 없음 |
| 8 | workbench apply | 이 저장소 | 승인 | 2분 | workbench 세션이 끊긴다 |
| 9 | 완료 판정 | 없음 | 조회만 | 10분 | |

- **적용**이 "승인"인 단계는 PR 머지가 plan을 돌리고 environment 승인이 apply를 돌린다. "머지"인 단계는
  머지가 곧 적용이고 hub의 ArgoCD가 5분 안에 반영한다.
- 앞 단계의 완료 조건을 확인하기 전에 다음 PR을 머지하지 않는다.
- 1번부터 6번까지는 끊지 않고 이어서 한다. 차단 중에도 스케일 아웃, spot 중단, 만료로 새로 뜨는 Karpenter
  노드는 새 마이너라, 차단 기간이 길수록 되돌리기가 어려워진다.

| 환경 | 티어 | 클러스터 | 고칠 파일 | 워크플로 |
|------|------|----------|-----------|----------|
| dev | `nonprd` | `eks-demo-dev-an2-main-01` | `live/dev/eks/main.tf` | `deploy-dev-eks.yml` |
| hub | `prd` | `eks-demo-hub-an2-main-01` | `live/hub/eks/main.tf` | `deploy-hub-eks.yml` |

명령 앞의 주석이 치는 자리다. `# 로컬:`은 그 계정의 프로파일로 내 터미널에서, `# workbench:`는 올릴
클러스터의 workbench에서 친다.

---

## 2. 시작 전에

### 2.1. 제약

| 제약 | 내용 |
|------|------|
| 마이너는 한 번에 하나 | `1.35 → 1.37` 직행은 안 된다. 이 문서를 두 번 돈다 |
| 노드가 먼저 맞아 있어야 한다 | 시작할 때 전 노드의 kubelet이 컨트롤플레인과 같은 마이너여야 한다 |
| 진행 중에는 멈출 수 없다 | 컨트롤플레인 업그레이드는 시작하면 중단되지 않는다 |
| 되돌리기는 7일, 한 마이너 | 그 버전으로 **생성한** 클러스터는 되돌릴 수 없다 |
| apply 한 번은 1시간 안에 | 워크플로의 자격증명이 1시간짜리다 |

### 2.2. 현재 상태와 Upgrade Insights

```bash
# 로컬:
aws eks describe-cluster --name <cluster> --query 'cluster.[version,status]'

# workbench: VERSION 열이 전부 컨트롤플레인과 같은 마이너여야 한다
kubectl get nodes -L karpenter.sh/nodepool,eks.amazonaws.com/nodegroup

# 로컬: refresh의 status가 COMPLETED가 된 뒤에 목록을 읽는다
aws eks start-insights-refresh --cluster-name <cluster>
aws eks describe-insights-refresh --cluster-name <cluster> --query status
aws eks list-insights --cluster-name <cluster> --filter '{"categories":["UPGRADE_READINESS"]}' \
  --query 'insights[].[insightStatus.status,kubernetesVersion,name]' --output table
```

| 상태 | 뜻 | 대응 |
|------|-----|------|
| `PASSING` | 문제없다 | 진행한다 |
| `WARNING` | 두 마이너 이상 뒤의 버전에 해당한다 | 진행한다. 다음 업그레이드 전에 고친다 |
| `ERROR` | 바로 다음 마이너에 해당한다 | `aws eks describe-insight --id <id>`로 대상을 읽고 고친 뒤 진행한다 |
| `UNKNOWN` | EKS가 판정하지 못했다 | refresh를 다시 돌린다 |

- ⚠️ **빈 목록은 통과가 아니다.** 갓 만든 클러스터는 refresh를 한 번 돌리기 전까지 목록이 비어 있다.
- ⚠️ deprecated API 사용은 지난 30일을 본다. 고친 뒤에도 상태가 바뀌기까지 최대 30일이 걸린다.
- `start-insights-refresh`가 없다는 오류가 나면 AWS CLI가 낡은 것이다. 올리고 다시 돈다.

### 2.3. 값 기록

값은 추정하지 않는다. 아래 명령으로 조회해 표를 채우고, 절차는 이 표의 칸 이름으로 값을 부른다. `<k8s>`는
**올릴 대상** 마이너다. 값이 리전에 묶여 있어 다른 리전의 값을 옮겨 적지 않는다.

| 칸 | 값 | 쓰는 단계 |
|----|----|-----------|
| `<k8s>` | | 전 단계 |
| `<ami>` | | 노드그룹 apply |
| `<ca>` | | cluster-autoscaler |
| `<addon>` (이름마다) | | addon apply. **그 단계 직전에 다시 조회한다** |
| `<kubectl>` | | workbench apply |

```bash
# 로컬: 대상 마이너가 지원 범위에 있는가
aws eks describe-cluster-versions \
  --query 'clusterVersions[].[clusterVersion,versionStatus,endOfStandardSupportDate]' --output table

# 로컬: <ami>. 아키텍처마다 값이 다르다(x86은 경로의 arm64를 x86_64로 바꾼다)
aws ssm get-parameter --region <region> --query Parameter.Value --output text \
  --name /aws/service/eks/optimized-ami/<k8s>/amazon-linux-2023/arm64/standard/recommended/release_version

# 로컬: <ca>. 대상 마이너로 시작하는 가장 높은 값
curl -fsSL https://registry.k8s.io/v2/autoscaling/cluster-autoscaler/tags/list | tr ',' '\n' | grep '"v<k8s>\.'

# 로컬: <addon>. cluster_addons에 적힌 이름 전부에 돈다. AWS 기본(default) 버전을 고른다. 최신이 아니다
aws eks describe-addon-versions --region <region> --kubernetes-version <k8s> --addon-name <name> \
  --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]'

# 로컬: 지금 핀이 대상 마이너의 호환 목록에 남아 있는가. 0이면 2번 단계 전에 그 addon만 먼저 올린다
aws eks describe-addon-versions --region <region> --kubernetes-version <k8s> --addon-name <name> \
  --query "length(addons[0].addonVersions[?addonVersion=='<지금 핀>'])"

# 로컬: <kubectl>
curl -fsS https://dl.k8s.io/release/stable-<k8s>.txt
```

### 2.4. 플랫폼 addon 호환성

`eks-platform-gitops`의 버전 표(`addons/cluster-addons/values.yaml`)에 있는 값이 대상 마이너를 지원하는지
본다. ⛔ 지원하지 않는 것이 있으면 여기서 멈추고, 그 저장소의 승격 절차로 **양 티어를 먼저** 올린 뒤에
이 문서로 돌아온다. dev와 hub의 마이너가 갈리는 동안 한 컨트롤러 버전이 두 마이너를 모두 지원해야 한다.

| addon | 확인하는 곳 |
|-------|-------------|
| Karpenter | [호환성 표](https://karpenter.sh/docs/upgrading/compatibility/)의 대상 마이너 하한 |
| Karpenter AMI alias | 아래 명령. `amiAliasByTier`의 날짜가 출력에 있어야 한다 |
| AWS Load Balancer Controller · Kyverno · KEDA | 각 프로젝트의 릴리스 노트와 차트 `kubeVersion` |
| Gateway API CRD | 컨트롤러(ALBC)가 지원하는 CRD 버전 |

```bash
# 로컬:
aws ssm get-parameters-by-path --region <region> --query 'Parameters[].Name' --output text \
  --path /aws/service/eks/optimized-ami/<k8s>/amazon-linux-2023/arm64/standard \
  | tr '\t' '\n' | grep -oE 'v[0-9]{8}' | sort -u
```

### 2.5. 워크로드

```bash
# workbench: ALLOWED DISRUPTIONS가 0이면 그 파드가 있는 노드는 비워지지 않는다
kubectl get pdb -A
```

| 워크로드 | 노드 교체 때 |
|----------|-------------|
| 복제본 2개 이상에 PDB가 있다 | 한 번에 하나씩 옮겨져 서비스가 이어진다 |
| 복제본이 하나다 | 대체 노드가 뜰 때까지 1분쯤 끊긴다. 노드 쪽 설정으로는 막지 못한다 |
| PDB가 eviction을 전부 막는다 | 관리형 노드그룹이 15분 뒤 `PodEvictionFailure`로 실패한다 |

---

## 3. 절차

### 3.1. disruption 차단

Karpenter가 app 노드를 스스로 교체하지 못하게 막는다. 컨트롤플레인이 올라가면 Karpenter가 기존 노드를
drift로 판정하는데, 컨트롤플레인과 system 노드그룹을 확인하기 전에 app 노드가 바뀌지 않게 한다.

- **고칠 곳**: `eks-platform-gitops` `addons/karpenter/nodepool/values.yaml`. **올릴 클러스터의 티어 줄만** 바꾼다.

```yaml
upgradeHoldByTier:
  prd: false
  nonprd: true      # dev를 올리는 동안
```

```bash
# workbench: {"nodes":"0","reasons":["Drifted","Underutilized"]}가 보여야 한다
kubectl get nodepool default -o jsonpath='{.spec.disruption.budgets}'; echo
```

- **완료 조건**: 올릴 클러스터에 위 줄이 보인다. ⛔ 반대 티어 클러스터에서도 같은 명령을 돌려 `Drifted`를
  막는 줄이 없는지 본다.

### 3.2. 컨트롤플레인 apply

- **고칠 곳**: `live/<env>/eks/main.tf`의 `module "eks"`.

```hcl
kubernetes_version = "<k8s>"
```

| plan의 줄 | 기대 |
|-----------|------|
| `aws_eks_cluster.this[0]` | `version`이 바뀌는 `update in-place` |
| `time_sleep.this[0]` | `must be replaced`. 클러스터 버전이 trigger다 |
| `aws_iam_openid_connect_provider` | `thumbprint_list`가 `(known after apply)`로 바뀌는 `update in-place` |
| `data.aws_eks_addon_version.*` | `will be read during apply`. 리소스 변경이 아니다 |
| 그 밖 | 없어야 한다 |

요약 줄은 `Plan: 1 to add, 2 to change, 1 to destroy`다.

⛔ 클러스터가 `must be replaced`로 뜨거나 노드그룹·addon·workbench가 뜨면 승인하지 않는다.

```bash
# 로컬:
aws eks describe-cluster --name <cluster> --query 'cluster.[version,status]'
```

- **완료 조건**: `version`이 `<k8s>`이고 `status`가 `ACTIVE`다. 노드는 전부 옛 마이너에 남아 있다.
  `runbooks.md` 「GitOps 상태 확인」의 Application이 전부 `Synced`/`Healthy`다.
- 완료 뒤 6~8분이 지나면 Karpenter 노드의 NodeClaim에 `Drifted`(`AMIDrift`)가 붙는다. 차단 때문에 교체되지
  않는 것이 정상이다.

### 3.3. 노드그룹 apply

- **고칠 곳**: 같은 파일의 `managed_node_groups`. 두 값을 함께 올리고, 주석의 조회 경로에 든
  마이너(`optimized-ami/<k8s>/`)도 고친다.

```hcl
managed_node_groups = {
  system = {
    kubernetes_version  = "<k8s>"
    ami_release_version = "<ami>"
  }
}
```

plan에는 `aws_eks_node_group`의 `version`·`release_version`이 바뀌는 `update in-place` 하나만 떠야 한다.
요약 줄은 `Plan: 0 to add, 1 to change, 0 to destroy`다.

```bash
# workbench: system 노드만 바뀌고 Karpenter 노드는 그대로여야 한다
kubectl get nodes -L karpenter.sh/nodepool,eks.amazonaws.com/nodegroup -w
```

새 노드가 AZ마다 한 대씩 함께 뜨고, 기존 노드가 함께 cordon된 뒤 한 대씩 약 3분 간격으로 비워진다.
system 노드의 파드(플랫폼 컴포넌트)가 이때 옮겨진다. 복제본이 하나인 컴포넌트는 옮겨지는 동안 멈춘다.

- **완료 조건**: system 노드가 전부 `<k8s>`이고 `Ready`다. Karpenter 노드는 옛 마이너에 남아 있다.

### 3.4. cluster-autoscaler

- **고칠 곳**: `eks-platform-gitops` `addons/cluster-addons/values.yaml`. 그 티어의 줄만 바꾼다.

```yaml
versions:
  clusterAutoscalerImage:
    prd: v1.35.0
    nonprd: <ca>      # dev를 올리는 동안
```

```bash
# workbench: 이미지 태그와 오류 수준 로그 수. 0이어야 한다
kubectl -n kube-system get deploy -l app.kubernetes.io/name=aws-cluster-autoscaler \
  -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'; echo
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=400 | grep -c '^E'
```

- **완료 조건**: 이미지가 `<ca>`이고 오류 수준 로그가 0줄이다. 권한 오류(`forbidden`)가 있으면 버전 표의
  차트 버전도 함께 올린다.
- ⚠️ 로그를 `forbidden`으로 grep하지 않는다. 시작할 때 찍히는 설정 값(`scaleDownForbidden`)이 걸린다.

### 3.5. 되돌릴지 정한다

여기가 되돌릴 수 있는 마지막 지점이다. 다음 단계에서 차단을 풀면 app 워크로드가 새 마이너의 노드로
옮겨지고, 그 뒤에는 되돌리지 않고 새 마이너에서 고친다.

| 확인 | 기대 |
|------|------|
| 컨트롤플레인 | `<k8s>`, `ACTIVE` |
| system 노드 | 전부 `<k8s>`, `Ready` |
| GitOps | 전부 `Synced`/`Healthy` |
| 플랫폼 파드 | `kubectl get pods -A`에 `Running`·`Completed`가 아닌 것이 없다 |
| app 워크로드 | 서비스 지표와 오류율이 올리기 전과 같다 |

되돌린다면 [`upgrade-rollback.md`](upgrade-rollback.md)로 간다. 차단은 풀지 않는다.

### 3.6. disruption 차단 해제

- **고칠 곳**: 3.1에서 `true`로 바꾼 줄을 `false`로 되돌린다.

```bash
# workbench: Karpenter 노드가 한 대씩 대상 마이너로 바뀐다
kubectl get nodeclaims -o wide -w
```

budget이 반영되면 20초 안에 교체가 시작된다. Karpenter가 대체 노드를 먼저 띄우고 PDB를 지키며 기존
노드를 비운다. 노드 10대 이하에서는 한 번에 한 대이고 대당 1분쯤 걸린다.

- **완료 조건**: `kubectl get nodes`의 `VERSION`이 전부 `<k8s>`다.

### 3.7. addon apply

- **고칠 곳**: `live/<env>/eks/main.tf`의 `cluster_addons`. `addon_version`을 `<addon>`으로 올리고 주석에 적힌
  기준 마이너도 고친다. 값이 그대로인 addon은 건드리지 않는다. `kube-proxy`를 빠뜨리지 않는다.

plan에는 값을 바꾼 `aws_eks_addon`의 `addon_version`이 바뀌는 `update in-place`만 떠야 한다.

```bash
# 로컬:
aws eks list-addons --cluster-name <cluster> --query 'addons' --output text | tr '\t' '\n' | while read a; do
  aws eks describe-addon --cluster-name <cluster> --addon-name "$a" \
    --query 'addon.[addonName,addonVersion,status]' --output text
done
```

`vpc-cni`와 `kube-proxy` DaemonSet이 전 노드에서 다시 뜨고 `coredns`가 롤링된다. 그동안 Service 호출은
끊기지 않는다.

- **완료 조건**: 전부 `ACTIVE`이고 버전이 커밋한 값과 같다.

### 3.8. workbench apply

- **고칠 곳**: 같은 파일의 `module "workbench"`. 주석의 URL에 든 마이너도 고친다.

```hcl
kubectl_version = "<kubectl>"
```

plan에는 `module.workbench.aws_instance.this[0]`이 `must be replaced`로 뜬다. `kubectl_version`이
`user_data`에 들어가서다. 요약 줄은 `Plan: 1 to add, 0 to change, 1 to destroy`이고 교체 대상이 그 인스턴스
하나뿐이어야 한다.

⚠️ instance-id가 바뀌고 열려 있던 SSM 세션과 port-forward가 끊긴다. workbench에서 도는 작업이 없을 때
승인한다.

```bash
# 로컬: 새 instance-id
aws ec2 describe-instances --filters 'Name=tag:Name,Values=*workbench*' 'Name=instance-state-name,Values=running' \
  --query 'Reservations[].Instances[].[InstanceId,LaunchTime]' --output text

# workbench: Client와 Server가 같은 마이너여야 한다
kubectl version
```

- **완료 조건**: 새 workbench에서 `kubectl version`의 두 줄이 같은 마이너다. 인스턴스가 뜬 뒤 1분쯤 지나야
  `kubectl`이 준비된다. hub는 `eks-argocd-tunnel-connect`를 다시 실행한다.

---

## 4. 완료 판정

| 확인 | 명령 | 기대 |
|------|------|------|
| 컨트롤플레인 | `aws eks describe-cluster --name <cluster> --query cluster.version` | `<k8s>` |
| 노드 | `kubectl get nodes` | 전 노드가 `<k8s>`, `Ready` |
| GitOps | `runbooks.md` 「GitOps 상태 확인」 | 전부 `Synced`/`Healthy` |
| addon | 3.7의 조회 | 전부 `ACTIVE` |
| cluster-autoscaler | 3.4의 조회 | 이미지가 `<ca>` |
| disruption 차단 | 3.1의 조회 | `Drifted`를 막는 줄이 없다 |
| 드리프트 | `gh workflow run deploy-<env>-eks.yml --ref main -f action=plan` | plan job 로그에 `No changes` |
| Insights | 2.2의 조회 | `UPGRADE_READINESS`에 다음 마이너에 대한 `ERROR`가 없다 |

`ROLLBACK_READINESS` 항목은 여기서 `ERROR`인 것이 정상이다. 노드와 addon이 새 마이너라는 뜻이다.

dev가 끝나면 워크로드를 지켜볼 시간을 두고 hub를 올린다.

---

## 5. hub를 올릴 때 다른 점

| 항목 | dev | hub |
|------|-----|-----|
| 티어 줄 | `nonprd` | `prd` |
| 평소의 budget | `10%` 한 줄 | `10%`와 평일 업무 시간에 `Underutilized`를 막는 줄. 차단 줄은 그 뒤에 하나 더 붙는다 |
| GitOps 반영 | hub의 ArgoCD가 dev에 민다 | hub의 ArgoCD가 자기 클러스터에 건다 |
| 노드그룹 apply | 플랫폼 컴포넌트가 옮겨진다 | **ArgoCD도 함께 옮겨진다** |

- ⚠️ hub의 노드그룹 apply 동안 ArgoCD가 노드와 함께 옮겨진다. server·repo-server·applicationset은 복제본
  2개에 PDB가 있어 이어진다. 복제본이 하나인 application-controller가 옮겨지는 동안 dev를 포함한 전
  클러스터의 reconcile이 멈춘다. ⛔ 그 구간에는 `eks-platform-gitops`에 머지하지 않는다. ⏳ 멈추는 시간과
  재시작 뒤 스스로 `Synced`로 돌아오는지는 확인하지 않았다.
- ⚠️ hub의 workbench apply는 ArgoCD 터널이 걸린 인스턴스를 교체한다.
- dev와 hub의 `main.tf`를 한 PR에 함께 올리지 않는다. 두 plan이 동시에 떠 순서가 사라진다.
- dev가 `<k8s>`이고 hub가 옛 마이너인 동안, `eks-platform-gitops`의 티어로 가르지 않은 매니페스트는 두 마이너
  모두에서 유효해야 한다. 새 마이너에만 있는 API를 쓰는 변경은 hub까지 끝난 뒤에 머지한다.

---

## 6. 자주 막히는 지점

| 단계 | 증상 | 원인과 대응 |
|------|------|-------------|
| 컨트롤플레인 apply | plan에 노드그룹이 뜬다 | 노드그룹의 `kubernetes_version`을 적지 않아 클러스터 버전을 따라간다. Reject하고 노드그룹에 지금 마이너를 명시한다 |
| 노드그룹 apply | `PodEvictionFailure`로 실패한다 | PDB나 모든 taint를 견디는 파드가 노드를 붙잡고 있다. 원인 파드를 풀고 `action=apply`로 다시 dispatch한다. ⏳ 저장된 plan은 state가 바뀐 뒤라 `gh run rerun --failed`가 통하지 않을 수 있다 |
| disruption 차단 해제 | 노드가 옛 마이너에 남는다 | `kubectl describe nodeclaim`으로 drift 판정과 막는 사유(PDB, `karpenter.sh/do-not-disrupt`)를 읽는다 |
| disruption 차단 해제 | 새 노드를 못 띄운다 | `EC2NodeClass`의 status에서 AMI 해석 실패를 본다. alias 날짜가 대상 마이너에 없으면 `amiAliasByTier`를 있는 날짜로 올린다 |
| addon apply | `그 버전 없음`으로 죽는다 | addon 핀이 대상 마이너의 호환 목록에 없다. 2.3의 조회로 값을 다시 고른다 |
| 전 단계 | 승인 게이트가 서지 않고 apply가 `skipped`다 | plan에 변경이 없다. 값이 실제로 바뀌었는지, 이미 적용된 커밋인지 plan job 로그로 본다 |
| 전 단계 | 머지가 `required status checks`로 거부된다 | PR의 검사가 아직 돌고 있다. `gh pr checks <번호> --watch`로 끝난 것을 보고 머지한다 |
