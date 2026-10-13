# EKS 마이너 업그레이드

**읽는 사람**: 이미 구축된 hub·spoke 클러스터의 Kubernetes 마이너 버전을 올리는 사람.

클러스터에 접근하는 법과 GitOps 상태를 읽는 법은 [`runbooks.md`](runbooks.md)가 갖는다. 승인 게이트와
plan을 읽는 법은 `iac-module-library/CLAUDE.md` 「배포 루트 공통」이 갖는다.

> **검증 상태**: ⏳ 표시가 붙은 줄은 실환경에서 확인하지 않았다. 나머지는 AWS·Karpenter 공식 문서와
> 이 저장소가 소비하는 모듈·provider 코드로 확인했다.

---

## 1. 제약

| 제약 | 내용 | 근거 |
|------|------|------|
| 마이너는 한 번에 하나 | `1.35 → 1.37` 직행은 안 된다. 이 문서를 두 번 돈다 | [Update existing cluster](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html) |
| 노드가 먼저 맞아 있어야 한다 | 컨트롤플레인을 올리기 전에 관리형 노드그룹의 kubelet이 컨트롤플레인과 같은 마이너여야 한다 | 같은 문서 「Step 1」 |
| 노드는 컨트롤플레인보다 높을 수 없다 | kubelet은 컨트롤플레인보다 세 마이너까지 낮아도 되지만 높을 수는 없다. 올릴 때는 컨트롤플레인이 먼저, 되돌릴 때는 노드가 먼저다 | 같은 문서, [Roll back a cluster](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html) |
| 진행 중에는 멈출 수 없다 | 컨트롤플레인 업그레이드는 시작하면 중단·일시정지가 안 된다. EKS의 자체 점검이 실패하면 EKS가 이전 버전으로 되돌린다 | Update existing cluster |
| 되돌리기는 7일 | 업그레이드가 끝난 뒤 7일 안에 한 마이너만 되돌릴 수 있다. 그 버전으로 **생성한** 클러스터는 되돌릴 수 없다 | Roll back a cluster |
| `kubectl`은 한 마이너 차이까지 | workbench의 `kubectl`이 컨트롤플레인과 두 마이너 이상 벌어지면 지원 범위 밖이다 | Update existing cluster 「Step 4」 |
| apply 한 번은 1시간 안에 | 워크플로의 자격증명이 1시간짜리다. apply가 그보다 길어지면 도중에 만료되고 state 저장도 실패할 수 있다 | `deploy-<env>-eks.yml`의 인증 단계 |

---

## 2. 무엇이 어디서 올라가나

올릴 값이 두 저장소에 흩어져 있다. 순서는 AWS 사용자 가이드가 적은 순서(컨트롤플레인 → 노드 →
cluster-autoscaler → addon → `kubectl`)다.

| 단계 | 값 | 자리 | 올리면 일어나는 일 |
|------|----|------|-------------------|
| 보류 걸기 | 그 티어의 `upgradeHoldByTier` | `eks-platform-gitops` `addons/karpenter/nodepool/values.yaml` | Karpenter가 기존 노드를 교체하지 않는다 |
| apply 1 | `kubernetes_version` | `live/<env>/eks/main.tf` | 컨트롤플레인 업그레이드 |
| apply 2 | `managed_node_groups[*]`의 `kubernetes_version`·`ami_release_version` | 같은 파일 | system 노드그룹 롤링 교체 |
| cluster-autoscaler | 그 티어의 이미지 태그 | `eks-platform-gitops` `addons/cluster-addons/values.yaml` | cluster-autoscaler 재배포 |
| 보류 풀기 | 그 티어의 `upgradeHoldByTier` | 보류를 건 자리 | Karpenter가 노드를 한 대씩 교체한다 |
| apply 3 | `cluster_addons[*].addon_version` | `live/<env>/eks/main.tf` | EKS 관리형 addon 갱신 |
| apply 4 | `kubectl_version` | 같은 파일 | workbench 인스턴스 교체 |

### 컨트롤플레인과 노드그룹을 나눈다

AWS는 둘을 별개의 단계로 적고 차례로 올리라고 한다([Best Practices for Cluster
Upgrades](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html)). 나누면 얻는 것:

| 얻는 것 | 내용 |
|---------|------|
| 멈춰 볼 지점 | 컨트롤플레인만 올라간 상태에서 API·addon·워크로드를 확인하고 노드로 넘어간다 |
| 실패의 격리 | 노드그룹이 `PodEvictionFailure`로 실패해도 컨트롤플레인 apply는 이미 끝난 run이다 |
| 자격증명 한도 | apply 하나가 한 작업만 해서 1시간 한도에서 멀어진다 |
| 대칭인 되돌리기 | 되돌릴 때 두 커밋을 역순으로 revert한다 |

노드그룹의 `kubernetes_version`을 **명시로 적어야** 나뉜다. 적지 않으면 upstream 모듈이 노드그룹 버전을
클러스터 버전에서 받아 와, `kubernetes_version`만 올린 plan에 노드그룹이 함께 뜬다. 노드그룹의
`kubernetes_version`과 `ami_release_version`의 마이너는 항상 같은 값이다.

### Karpenter 노드는 보류했다가 푼다

`EC2NodeClass`는 버전을 적은 alias(`al2023@v<날짜>`)로 AMI를 고르고, Karpenter는 이 alias를
**컨트롤플레인 버전에 맞는 AMI**로 푼다. 컨트롤플레인이 올라가면 같은 alias가 새 마이너의 AMI를 가리키고
Karpenter가 기존 노드를 drift로 판정해 교체한다([Managing AMIs](https://karpenter.sh/docs/tasks/managing-amis/)).
`amiAliasByTier`를 고치지 않아도 일어난다.

app 워크로드가 Karpenter 노드에 있으므로, 컨트롤플레인과 system 노드그룹이 끝날 때까지 이 교체를
막는다. `NodePool`의 disruption budget에 `Drifted`와 `Underutilized`를 막는 줄을 티어별로 둔다.

- 보류는 **Karpenter가 스스로 노드를 갈아 끼우는 것**만 막는다. 보류 중에 스케일 아웃, spot 중단,
  만료(`expireAfter`)로 새로 뜨는 노드는 새 마이너다. 보류 기간을 길게 끌지 않는다.
- 보류를 풀면 Karpenter가 대체 노드를 먼저 띄우고 PDB를 지키며 기존 노드를 비운다. 한 번에 교체하는
  노드 수는 budget이 정한다.
- ⚠️ alias의 날짜 버전이 **새 마이너에도 있어야** 한다. 없으면 Karpenter가 새 노드를 띄우지 못한다.
- ⏳ 보류를 푼 뒤 drift 교체가 시작되기까지 걸리는 시간과, 교체 중 복제본 2개에 PDB를 건 워크로드가
  끊기는지는 확인하지 않았다.

### 🔑 보류를 풀기 전까지가 되돌릴 수 있는 구간이다

되돌리려면 노드가 먼저 옛 마이너로 내려가야 한다. 관리형 노드그룹은 값을 내려 되돌릴 수 있지만,
Karpenter 노드는 alias가 컨트롤플레인을 따라가므로 컨트롤플레인보다 먼저 내릴 방법이 없다. 새 마이너의
Karpenter 노드가 하나라도 있으면 EKS의 검사를 건너뛰는 비상 경로로만 되돌릴 수 있다.

**되돌릴지는 보류를 풀기 전에 정한다.** addon 핀(apply 3)도 되돌려지지 않는 값이라 그 뒤에 둔다.

---

## 3. 사전 점검

클러스터마다 보류를 걸기 전에 돈다. `<k8s>`는 **올릴 대상** 마이너다.

### 3.1. 현재 상태

```bash
aws eks describe-cluster --name <cluster> --query 'cluster.[version,status]'

# workbench에서. VERSION 열이 전부 컨트롤플레인과 같은 마이너여야 한다
kubectl get nodes -L karpenter.sh/nodepool,eks.amazonaws.com/nodegroup
```

### 3.2. Upgrade Insights

```bash
aws eks start-insights-refresh --cluster-name <cluster>
aws eks describe-insights-refresh --cluster-name <cluster>     # status가 COMPLETED가 될 때까지

aws eks list-insights --cluster-name <cluster> \
  --filter '{"categories":["UPGRADE_READINESS"]}' \
  --query 'insights[].[insightStatus.status,kubernetesVersion,name]' --output table
```

| 상태 | 뜻 | 대응 |
|------|-----|------|
| `PASSING` | 문제없다 | 진행한다 |
| `WARNING` | 두 마이너 이상 뒤의 버전에 해당한다 | 진행한다. 다음 업그레이드 전에 고친다 |
| `ERROR` | 바로 다음 마이너에 해당한다 | `aws eks describe-insight --id <id>`로 대상을 읽고 고친 뒤 진행한다 |
| `UNKNOWN` | EKS가 판정하지 못했다 | refresh를 다시 돌린다 |

⚠️ deprecated API 사용은 지난 30일을 본다. 고친 뒤에도 상태가 바뀌기까지 최대 30일이 걸린다.

⚠️ **빈 목록은 통과가 아니다.** 갓 만든 클러스터는 refresh를 한 번 돌리기 전까지 목록이 비어 있다.
`start-insights-refresh`가 없다는 오류가 나면 AWS CLI가 낡은 것이다. 올리고 다시 돈다.

### 3.3. 올릴 값 조회

값은 추정하지 않는다. 전부 조회해서 적는다.

```bash
# 대상 마이너가 지원 범위에 있는가
aws eks describe-cluster-versions \
  --query 'clusterVersions[].[clusterVersion,versionStatus,endOfStandardSupportDate]' --output table

# ami_release_version. 아키텍처마다 값이 다르다(x86은 경로의 arm64를 x86_64로 바꾼다)
aws ssm get-parameter --region <region> --query Parameter.Value --output text \
  --name /aws/service/eks/optimized-ami/<k8s>/amazon-linux-2023/arm64/standard/recommended/release_version

# addon_version. AWS 기본(default) 버전을 고른다. 최신이 아니다
aws eks describe-addon-versions --region <region> --kubernetes-version <k8s> --addon-name <name> \
  --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]'

# 지금 핀이 대상 마이너의 호환 목록에 남아 있는가. 0이면 apply 1 전에 그 addon부터 올린다
aws eks describe-addon-versions --region <region> --kubernetes-version <k8s> --addon-name <name> \
  --query "length(addons[0].addonVersions[?addonVersion=='<지금 핀>'])"

# kubectl_version
curl -fsS https://dl.k8s.io/release/stable-<k8s>.txt

# cluster-autoscaler 이미지 태그. 대상 마이너로 시작하는 가장 높은 값
curl -fsSL https://registry.k8s.io/v2/autoscaling/cluster-autoscaler/tags/list | tr ',' '\n' | grep '"v<k8s>\.'
```

addon 조회는 `cluster_addons`에 적힌 이름 전부에 돈다. 값이 리전에도 묶여 있어 다른 리전의 값을 옮겨
적지 않는다.

### 3.4. 플랫폼 addon 호환성

`eks-platform-gitops`의 버전 표(`addons/cluster-addons/values.yaml`)에 있는 값이 대상 마이너를 지원하는지
본다. 지원하지 않으면 **클러스터를 올리기 전에** 그 저장소의 승격 절차로 양 티어를 먼저 올린다. 승격
구간에는 한 컨트롤러 버전이 두 마이너를 모두 지원해야 하기 때문이다.

| addon | 확인하는 곳 |
|-------|-------------|
| Karpenter | [호환성 표](https://karpenter.sh/docs/upgrading/compatibility/)의 대상 마이너 하한 |
| Karpenter AMI alias | 아래 명령. `amiAliasByTier`의 날짜가 출력에 있어야 한다 |
| AWS Load Balancer Controller · Kyverno · KEDA | 각 프로젝트의 릴리스 노트와 차트 `kubeVersion` |
| Gateway API CRD | 컨트롤러(ALBC)가 지원하는 CRD 버전 |

```bash
aws ssm get-parameters-by-path --region <region> --query 'Parameters[].Name' --output text \
  --path /aws/service/eks/optimized-ami/<k8s>/amazon-linux-2023/arm64/standard \
  | tr '\t' '\n' | grep -oE 'v[0-9]{8}' | sort -u
```

### 3.5. 워크로드

```bash
# ALLOWED DISRUPTIONS가 0이면 그 파드가 있는 노드는 비워지지 않는다
kubectl get pdb -A
```

| 워크로드 | 노드 교체 때 |
|----------|-------------|
| 복제본 2개 이상에 PDB가 있다(AWS 권고는 `topologySpreadConstraints`까지다) | 한 번에 하나씩 옮겨져 서비스가 이어진다 |
| 복제본이 하나다 | 옮겨지는 동안 끊긴다. 노드 쪽 설정으로는 막지 못한다 |
| PDB가 eviction을 전부 막는다 | 관리형 노드그룹이 15분 뒤 `PodEvictionFailure`로 실패한다 |

---

## 4. 승격 순서

nonprd 티어(dev)를 끝까지 올리고 확인한 뒤 prd 티어(hub)를 올린다. 티어는 cluster Secret의 `tier`
라벨이 정한다.

| 순서 | 대상 | 무엇을 |
|------|------|--------|
| 1 | dev | 사전 점검 → 5절 전체 |
| 2 | dev | 완료 판정(6절). 워크로드를 지켜볼 시간을 둔다 |
| 3 | hub | 사전 점검 → 5절 전체 |
| 4 | hub | 완료 판정 |

⚠️ dev와 hub의 `live/<env>/eks/main.tf`는 다른 파일이고 워크플로도 다르다(`deploy-dev-eks.yml`·
`deploy-hub-eks.yml`). 한 PR에 두 파일을 함께 올리지 않는다. 두 plan이 동시에 떠 승격 순서가 사라진다.

⚠️ **승격 구간에는 `eks-platform-gitops`의 티어로 가르지 않은 매니페스트가 두 마이너 모두에서 유효해야
한다.** 새 마이너에만 있는 API를 쓰는 변경은 hub까지 끝난 뒤에 머지한다.

⚠️ hub는 ArgoCD가 도는 클러스터다. ArgoCD는 system 노드그룹에 고정되어 있어 **hub의 apply 2 동안**
노드와 함께 옮겨진다. server·repo-server·applicationset은 복제본 2개에 PDB가 있어 이어지고, 복제본이
하나인 application-controller가 옮겨지는 동안 dev를 포함한 전 클러스터의 reconcile이 멈춘다. 그
구간에는 `eks-platform-gitops`에 머지하지 않는다. ⏳ 멈추는 시간과 재시작 뒤 스스로 `Synced`로
돌아오는지는 확인하지 않았다.

---

## 5. 절차

배포 루트의 apply는 브랜치 → PR → 머지이고, 머지가 plan을 돌리고 environment 승인이 apply를 돌린다.
`eks-platform-gitops`는 머지가 곧 적용이다. 앞 단계의 완료를 확인하기 전에 다음 PR을 머지하지 않는다.

### 5.1. 보류 걸기

`eks-platform-gitops`의 `addons/karpenter/nodepool/values.yaml`에서 **올릴 클러스터의 티어 줄만** `true`로
바꾸고 PR로 머지한다. dev는 `nonprd`, hub는 `prd`다.

```yaml
upgradeHoldByTier:
  prd: false
  nonprd: true      # dev를 올리는 동안
```

머지하면 hub의 ArgoCD가 그 티어 클러스터의 `NodePool`에 budget을 건다. 반영까지 3분쯤 걸린다.

```bash
# 올릴 클러스터의 workbench에서. {"nodes":"0","reasons":["Drifted","Underutilized"]}가 보여야 한다
kubectl get nodepool default -o jsonpath='{.spec.disruption.budgets}'; echo
```

⛔ 반대 티어 클러스터에서도 같은 명령을 돌려 `Drifted`를 막는 줄이 없는지 본다.

### 5.2. apply 1: 컨트롤플레인

```hcl
kubernetes_version = "<k8s>"
```

plan에서 볼 것:

| 줄 | 기대 |
|----|------|
| `aws_eks_cluster.this[0]` | `version`이 바뀌는 `update in-place` |
| `time_sleep.this[0]` | `must be replaced`. 클러스터 버전이 trigger라서 정상이다 |
| `aws_iam_openid_connect_provider` | `thumbprint_list`가 `(known after apply)`로 바뀌는 `update in-place`. 클러스터를 읽는 data source가 apply 때 다시 읽혀서다 |
| `data.aws_eks_addon_version.*` | `will be read during apply`. data source라 리소스 변경이 아니다 |
| 그 밖 | 없어야 한다. 노드그룹·addon·workbench가 뜨면 승인하지 않고 원인을 찾는다 |

요약 줄은 `Plan: 1 to add, 2 to change, 1 to destroy`다. add와 destroy는 `time_sleep`의 교체다.

⛔ 클러스터가 `must be replaced`로 뜨면 승인하지 않는다.

```bash
aws eks list-updates --name <cluster>
aws eks describe-update --name <cluster> --update-id <id> --query 'update.[type,status]'
```

완료 조건: `aws eks describe-cluster`의 `version`이 대상 마이너이고 `status`가 `ACTIVE`다. 노드는 전부 옛
마이너에 남아 있고(`kubectl get nodes`), `runbooks.md` 「GitOps 상태 확인」의 Application이 전부
`Synced`/`Healthy`다. ⏳ 소요 시간은 확인하지 않았다.

### 5.3. apply 2: system 노드그룹

두 값을 함께 올린다. 주석의 조회 경로에 든 마이너(`optimized-ami/<k8s>/`)도 함께 고친다.

```hcl
managed_node_groups = {
  system = {
    kubernetes_version  = "<k8s>"
    ami_release_version = "<3.3에서 조회한 값>"
  }
}
```

plan에는 `aws_eks_node_group`의 `version`·`release_version` 변경만 떠야 한다. 관리형 노드그룹은 새 노드를
먼저 띄우고 한 번에 한 대씩 기존 노드를 비운다.

```bash
# workbench에서. Karpenter 노드는 그대로이고 system 노드만 바뀌어야 한다
kubectl get nodes -L karpenter.sh/nodepool,eks.amazonaws.com/nodegroup -w
```

완료 조건: system 노드가 전부 대상 마이너이고 `Ready`다. Karpenter 노드는 옛 마이너에 남아 있다.
⏳ 소요 시간과, 그동안 복제본이 하나인 플랫폼 컴포넌트(Kyverno·KEDA·ArgoCD application-controller)가
끊기는 시간은 확인하지 않았다.

| 증상 | 대응 |
|------|------|
| `PodEvictionFailure`로 실패한다 | PDB나 모든 taint를 견디는 파드가 노드를 붙잡고 있다. 원인 파드를 풀고 `action=apply`로 다시 dispatch한다. state가 바뀐 뒤라 저장된 plan은 `Saved plan is stale`로 거부되어 `gh run rerun --failed`가 통하지 않는다 |

### 5.4. cluster-autoscaler

`eks-platform-gitops`의 `addons/cluster-addons/values.yaml`에서 그 티어의 이미지 줄을 3.3에서 조회한
값으로 올리고 PR로 머지한다. AWS는 cluster-autoscaler를 클러스터와 같은 마이너로 맞추라고 적는다.

```yaml
versions:
  clusterAutoscalerImage:
    prd: v1.35.0
    nonprd: v1.36.1   # dev를 올리는 동안
```

```bash
kubectl -n kube-system get deploy -l app.kubernetes.io/name=aws-cluster-autoscaler \
  -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'; echo
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=50
```

⏳ 차트가 새 마이너의 이미지가 요구하는 RBAC를 갖고 있는지는 확인하지 않았다. 로그에 `forbidden`이
있으면 차트 버전도 함께 올린다.

### 5.5. 되돌릴지 정하고 보류를 푼다

여기가 되돌릴 수 있는 마지막 지점이다. 6절의 컨트롤플레인·노드·GitOps 행을 확인하고, 되돌린다면
`upgrade-rollback.md`로 간다. 진행한다면 5.1에서 `true`로 바꾼 줄을 `false`로 되돌려 PR로 머지한다.

```bash
# workbench에서. Karpenter 노드가 한 대씩 대상 마이너로 바뀐다
kubectl get nodeclaims -o wide -w
```

| 증상 | 대응 |
|------|------|
| 노드가 옛 마이너에 남는다 | `kubectl describe nodeclaim`으로 drift 판정과 막는 사유(PDB, `karpenter.sh/do-not-disrupt`)를 읽는다 |
| 새 노드를 못 띄운다 | `EC2NodeClass`의 status에서 AMI 해석 실패를 본다. alias 날짜가 대상 마이너에 없으면 `amiAliasByTier`를 있는 날짜로 올린다 |

완료 조건: `kubectl get nodes`의 `VERSION`이 전부 대상 마이너다.

### 5.6. apply 3: EKS 관리형 addon

`cluster_addons`의 `addon_version`을 3.3에서 조회한 값으로 올린다. 값이 그대로인 addon은 건드리지
않는다. 주석에 적힌 기준 마이너도 함께 고친다. `kube-proxy`는 Kubernetes 마이너를 따라가므로 빠뜨리지
않는다.

plan에는 `aws_eks_addon`의 `addon_version` 변경만 떠야 한다.

```bash
aws eks list-addons --cluster-name <cluster> --query 'addons' --output text | tr '\t' '\n' | while read a; do
  aws eks describe-addon --cluster-name <cluster> --addon-name "$a" \
    --query 'addon.[addonName,addonVersion,status]' --output text
done
```

전부 `ACTIVE`이고 버전이 커밋한 값과 같아야 한다. ⏳ `vpc-cni`·`coredns` 갱신 중 워크로드가 끊기는지는
확인하지 않았다.

### 5.7. apply 4: workbench의 `kubectl`

```hcl
kubectl_version = "<3.3에서 조회한 값>"
```

`kubectl_version`은 workbench의 `user_data`에 들어가고, 모듈은 `user_data`가 바뀌면 인스턴스를 교체한다.
plan에 `module.workbench.aws_instance.this[0]`이 `must be replaced`로 뜨는 것이 정상이다. 교체 대상이 그
인스턴스 하나뿐인지 본다.

⚠️ 교체하면 instance-id가 바뀌고 열려 있던 SSM 세션과 port-forward가 끊긴다. workbench에서 도는 작업이
없을 때 승인한다. 교체 뒤 `eks-argocd-tunnel-connect`를 다시 실행하고 `kubectl version`으로 Client와
Server가 같은 마이너인지 본다.

---

## 6. 완료 판정

| 확인 | 명령 | 기대 |
|------|------|------|
| 컨트롤플레인 | `aws eks describe-cluster --name <cluster> --query cluster.version` | 대상 마이너 |
| 노드 | `kubectl get nodes` | 전 노드가 대상 마이너, `Ready` |
| GitOps | `runbooks.md` 「GitOps 상태 확인」 | 전부 `Synced`/`Healthy` |
| addon | 5.6의 조회 | 전부 `ACTIVE` |
| cluster-autoscaler | 5.4의 조회 | 이미지가 대상 마이너 |
| 보류 | 5.1의 조회 | `Drifted`를 막는 줄이 없다 |
| 드리프트 | `gh workflow run deploy-<env>-eks.yml --ref main -f action=plan` | plan job 로그에 `No changes` |
| Insights | 3.2의 조회 | 다음 마이너에 대한 `ERROR`가 없다 |

---

## 7. 되돌리기

조건, 경로, 단계별 명령은 [`upgrade-rollback.md`](upgrade-rollback.md)가 갖는다. 5.5에서 보류를 풀기 전에 읽는다.

---

## 8. 자주 막히는 지점

| 증상 | 원인 | 대응 |
|------|------|------|
| apply 1의 plan에 노드그룹이 뜬다 | 노드그룹의 `kubernetes_version`을 적지 않아 클러스터 버전을 따라간다 | 승인하지 않고 Reject한 뒤 노드그룹에 지금 마이너를 명시한다 |
| apply가 `그 버전 없음`으로 죽는다 | addon 핀이 대상 마이너의 호환 목록에 없다 | 3.3의 조회로 그 addon의 값을 다시 고른다 |
| 승인 게이트가 서지 않고 apply가 `skipped`다 | plan에 변경이 없다 | 값이 실제로 바뀌었는지, 이미 적용된 커밋인지 plan job 로그로 본다 |
