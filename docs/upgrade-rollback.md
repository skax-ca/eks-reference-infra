# EKS 마이너 업그레이드 되돌리기

**읽는 사람**: 올린 Kubernetes 마이너를 이전 버전으로 되돌릴지 정하거나 되돌리는 사람.

올리는 절차와 단계 이름(컨트롤플레인 apply·노드그룹 apply·보류)은 [`upgrade.md`](upgrade.md)가 갖는다. 이 문서는 그
절차의 「되돌릴지 정하고 보류를 푼다」 단계에서 되돌리기로 정했을 때 연다.

> **검증 상태**: ⏳ 표시가 붙은 줄은 실환경에서 확인하지 않았다. 나머지는 dev에서 `1.36 → 1.35`로
> 확인한 값이다.

---

## 1. 조건

| 조건 | 내용 |
|------|------|
| 기한 | 업그레이드 완료 뒤 7일 |
| 범위 | 한 마이너. `1.35 → 1.36 → 1.37`로 올렸으면 `1.36`까지만 돌아간다 |
| EKS가 되돌리는 것 | 컨트롤플레인 |
| 직접 되돌리는 것 | system 노드그룹, cluster-autoscaler 이미지, Karpenter 노드, EKS 관리형 addon 버전 |
| 그대로 남는 것 | etcd 데이터, 워크로드, 영구 볼륨 |
| 되돌릴 수 없는 경우 | 그 버전으로 생성한 클러스터, 7일 경과, 그 뒤 다시 올린 클러스터, 옛 마이너가 지원하지 않는 EKS 기능을 켠 클러스터. `--force`로도 넘지 못한다 |
| 지원 정책 | 옛 마이너가 extended support 구간이면 클러스터의 `upgradePolicy`가 `EXTENDED`여야 한다. 내려가면 extended support 요금이 붙는다 |

근거는 [Roll back a cluster](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html)다.

⚠️ `UpdateNodegroupVersion` API 레퍼런스는 노드그룹을 이전 버전으로 되돌릴 수 없다고 적지만, 컨트롤플레인을
올린 뒤의 되돌리기 구간에서는 EKS가 노드그룹의 버전 하향을 받는다.

---

## 2. 어느 경로인가

EKS는 컨트롤플레인을 내리기 전에 `ROLLBACK_READINESS` insight를 검사한다. 새 마이너의 kubelet이 하나라도
남아 있으면 `Kubelet version rollback compatibility`가 `ERROR`가 되어 내리기를 거부한다. Karpenter 노드는
alias가 컨트롤플레인 버전을 따라가므로 컨트롤플레인보다 먼저 내릴 수단이 없다.

| 상태 | 경로 | 컨트롤플레인을 내리는 수단 |
|------|------|-----------------------------|
| 보류를 풀기 전이고 Karpenter 노드가 전부 옛 마이너다 | CI 경로 | 컨트롤플레인 apply의 커밋 revert ⏳ |
| 보류를 풀기 전인데 Karpenter 노드 몇 대가 새 마이너로 떴다 | 비상 경로 | AWS CLI의 `--force` |
| 보류를 이미 풀었다 | 되돌리지 않는다 | 없다. 문제를 새 마이너에서 고친다 |

보류 중에도 spot 중단, 스케일 아웃, 만료(`expireAfter`)로 새로 뜨는 Karpenter 노드는 새 마이너다. 보류
기간이 길수록 비상 경로가 될 가능성이 커진다.

🔑 AWS가 권하는 순서는 노드가 먼저다. 자체 관리 노드는 컨트롤플레인을 내리기 전에 AMI를 옛 마이너로
바꾸라고 적고, EKS Auto Mode도 노드를 먼저 내린다. CI 경로는 이 순서와 같다. 비상 경로는 다르다. 새
마이너의 kubelet을 옛 마이너의 컨트롤플레인 아래에 잠시 두는데, Kubernetes가 지원하지 않는 조합이다.
AWS는 먼저 내릴 수단이 없는 Fargate에만 이 방법을 대안으로 적고, 그 파드가 교체될 때까지 예기치 않은
동작이 있을 수 있다고 경고한다.

- 그래서 비상 경로는 **몇 대**가 새어 나간 경우에만 쓴다. 보류를 풀어 app 워크로드 전부가 새 마이너의
  노드에 있으면 되돌리지 않는다. 되돌릴지는 보류를 풀기 전에 정한다.
- `--force`는 "적용 경로는 CI 하나"라는 원칙의 예외다. 사람이 로컬 자격증명으로 한 번 실행하고, 바로
  뒤에 커밋 revert를 머지해 코드를 실제와 맞춘다.
- `--force`가 건너뛰는 것은 insight 검사뿐이다. 1절의 조건은 그대로 걸린다. EKS는 건너뛴 되돌리기의
  안전을 보장하지 않는다.
- ⚠️ `--force`로 건너뛴 비호환 리소스는 etcd에 남고 EKS가 치우지 않는다. `API usage` 항목이 `ERROR`면
  건너뛰지 않고 그 리소스를 먼저 고친다.
- ⚠️ insight는 조회한 시점의 값이다. 조회한 뒤 새 API로 만든 리소스는 검사에 잡히지 않는다. 되돌리기로
  정했으면 그 클러스터에 새 리소스를 배포하지 않는다.

---

## 3. 준비 상태를 읽는다

```bash
aws eks start-insights-refresh --cluster-name <cluster>
aws eks describe-insights-refresh --cluster-name <cluster>     # status가 COMPLETED가 될 때까지

aws eks list-insights --cluster-name <cluster> --filter '{"categories":["ROLLBACK_READINESS"]}' \
  --query 'insights[].[insightStatus.status,id,name]' --output table

# ERROR 항목이 가리키는 대상
aws eks describe-insight --cluster-name <cluster> --id <id> \
  --query 'insight.resources[].kubernetesResourceUri'
```

| 항목 | `ERROR`일 때 |
|------|--------------|
| `Kubelet version rollback compatibility` | 대상 노드가 새 마이너다. system 노드는 4.2에서 내려간다. Karpenter 노드가 남으면 비상 경로다 |
| `EKS add-on version rollback compatibility` | 그 addon의 핀이 옛 마이너의 호환 목록에 없다. 4.3에서 내린다 |
| `kube-proxy version rollback compatibility` | `kube-proxy` addon이 새 마이너다. 4.3에서 내린다 |
| `API usage rollback compatibility` · `Cluster health rollback compatibility` | 대상을 읽고 고친다 |

```bash
# workbench에서. 어느 노드가 새 마이너인지와 Karpenter 노드인지를 함께 본다
kubectl get nodes -L karpenter.sh/nodepool,eks.amazonaws.com/nodegroup
```

⚠️ insight는 EKS 관리형 addon만 검사한다. 올린 뒤에 `eks-platform-gitops`의 차트 버전(Karpenter, AWS Load
Balancer Controller, Kyverno 등)을 올렸다면 그 버전이 옛 마이너를 지원하는지 `upgrade.md`의 「플랫폼
addon 호환성」 표로 직접 확인한다. 지원하지 않으면 그 차트부터 내린다.

---

## 4. 절차

올린 순서의 역순이다. 앞 단계의 완료를 확인하기 전에 다음으로 가지 않는다. 보류(`upgradeHoldByTier`)는
끝까지 `true`로 둔다.

### 커밋을 revert해 PR로 머지하는 방법

아래 단계의 "커밋을 revert한다"는 올릴 때 머지한 PR을 되돌리는 PR을 새로 만들어 머지한다는 뜻이다.
`main`에 직접 push하지 않는다. 그 저장소의 클론에서 돌린다.

```bash
# 1. 올릴 때 머지한 PR의 번호를 찾는다. 제목이 "ops(<env>-eks): ...을 <새 마이너>로 올린다"다
gh pr list --state merged --limit 10 --json number,title,mergedAt \
  --jq '.[] | "\(.number)\t\(.mergedAt)\t\(.title)"'

# 2. 그 PR을 되돌리는 PR을 만들고 새 PR의 번호를 읽는다
gh pr revert <올린 PR 번호>
gh pr list --state open --json number,title --jq '.[] | "\(.number)\t\(.title)"'

# 3. 값이 옛 마이너로 돌아가는지 읽고, 검사가 끝나면 머지한다
gh pr diff <새 PR 번호>
gh pr checks <새 PR 번호> --watch
gh pr merge <새 PR 번호> --squash --delete-branch
```

`eks-platform-gitops`는 여기까지다. 머지가 곧 적용이고 hub의 ArgoCD가 3분 안에 반영한다.
`eks-reference-infra`는 머지가 plan을 돌리고 apply가 승인을 기다린다.

```bash
# 4. 머지가 깨운 run과 그 plan job을 찾는다
gh run list --workflow deploy-<env>-eks.yml --limit 1 --json databaseId,status --jq '.[0]'
gh run view <run id> --json jobs --jq '.jobs[] | "\(.databaseId)\t\(.name)\t\(.conclusion)"'

# 5. plan job이 끝나면 요약을 읽어 그 단계의 기대값과 맞댄다
gh api repos/<owner>/eks-reference-infra/actions/jobs/<plan job id>/logs \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E ' (will be|must be) |Plan:|No changes'

# 6. 승인한다. 거절은 state=rejected다
ENV_ID=$(gh api repos/<owner>/eks-reference-infra/actions/runs/<run id>/pending_deployments \
  --jq '.[0].environment.id')
gh api -X POST repos/<owner>/eks-reference-infra/actions/runs/<run id>/pending_deployments \
  -f state=approved -f comment='<읽은 plan 요약>' -F "environment_ids[]=$ENV_ID"

gh run watch <run id>
```

- ⚠️ `gh pr revert`가 충돌로 실패하면 그 PR 뒤에 같은 줄을 고친 커밋이 있는 것이다. 브랜치를 만들어 그
  값을 손으로 옛 마이너로 고치고 `gh pr create`로 연다.
- ⚠️ plan이 기대값과 다르면 승인하지 않고 거절한다. 게이트를 열어 둔 채 다음 PR을 머지하지 않는다.
- 승인 대기 중인 run은 `gh run view --log`로 plan을 읽을 수 없어 5번처럼 job 로그 API를 쓴다.

### 4.1. cluster-autoscaler

`eks-platform-gitops`에서 그 티어의 `versions.clusterAutoscalerImage`를 올린 커밋을 revert해 PR로
머지한다.

```bash
kubectl -n kube-system get deploy -l app.kubernetes.io/name=aws-cluster-autoscaler \
  -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'; echo
```

완료 조건: 이미지 태그가 옛 마이너다.

### 4.2. system 노드그룹

노드그룹 apply의 커밋을 revert해 PR로 머지한다. `kubernetes_version`과 `ami_release_version`이 함께 내려간다.

| plan의 줄 | 기대 |
|-----------|------|
| `aws_eks_node_group` | `version`과 `release_version`이 내려가는 `update in-place` |
| 그 밖 | 없어야 한다 |

⛔ 노드그룹이 `must be replaced`로 뜨면 승인하지 않는다.

올릴 때와 같은 방식으로 교체된다. 새 노드가 AZ마다 한 대씩 함께 뜨고, 기존 노드가 함께 cordon된 뒤 한
대씩 약 3분 간격으로 비워진다. 노드 2대 기준으로 apply는 약 10분이다.

완료 조건: system 노드가 전부 옛 마이너이고 `Ready`다. 3절의 insight를 다시 읽으면 kubelet 항목의 대상에서
system 노드가 빠져 있다.

### 4.3. EKS 관리형 addon ⏳

addon apply까지 갔을 때만 한다. addon apply의 커밋을 revert해 PR로 머지한다. plan에는 `aws_eks_addon`의
`addon_version` 변경만 떠야 한다. `kube-proxy`가 여기에 든다.

완료 조건: `upgrade.md`의 addon 조회에서 전부 `ACTIVE`이고, 3절의 addon·`kube-proxy` 항목이 `PASSING`이다.

### 4.4. 컨트롤플레인

**CI 경로** ⏳: 3절의 항목이 전부 `PASSING`이면 컨트롤플레인 apply의 커밋을 revert해 PR로 머지한다. plan에는
`aws_eks_cluster.this[0]`의 `version`이 내려가는 `update in-place`와 `time_sleep`의 교체가 떠야 한다.
4.5를 건너뛴다.

**비상 경로**: kubelet 항목의 `ERROR` 대상이 Karpenter 노드뿐인지 확인한 뒤 아래를 실행한다.

```bash
aws eks update-cluster-version --profile <profile> --region <region> \
  --name <cluster> --kubernetes-version <옛 마이너> --force
```

⚠️ 붙여 넣을 때 줄이 갈리면 `--kubernetes-version` 없이 첫 줄만 실행되어 인자 오류로 끝난다. 이 오류는
AWS에 닿지 않아 클러스터는 그대로다. 한 줄로 다시 실행한다.

⛔ 이 명령을 실행한 뒤 4.5를 마칠 때까지 그 `eks` 루트에 다른 변경을 머지하지 않는다. 코드가 아직 새
마이너라, 그 plan은 클러스터를 다시 올리려 한다.

```bash
# type이 VersionRollback이고 status가 Successful이 될 때까지
aws eks describe-update --name <cluster> --update-id <응답의 update.id> --query 'update.[type,status,errors]'
```

시작하면 중단할 수 없다. 약 7분 걸리고 그동안 워크로드는 끊기지 않는다.

완료 조건: `aws eks describe-cluster`의 `version`이 옛 마이너이고 `status`가 `ACTIVE`다.

### 4.5. 코드를 실제와 맞춘다 (비상 경로)

컨트롤플레인 apply의 커밋을 revert해 PR로 머지한다. 컨트롤플레인이 `ACTIVE`가 된 **뒤에** 머지한다. 먼저 머지하면
apply가 insight 검사에서 거부된다.

| plan의 줄 | 기대 |
|-----------|------|
| `Objects have changed outside of OpenTofu` | `aws_eks_cluster`의 `version`과 `platform_version`. 4.4의 명령이 바꾼 것을 읽어 들인 것이다 |
| `time_sleep.this[0]` | `must be replaced`. 클러스터 버전이 trigger다 |
| `aws_eks_cluster.this[0]` | 변경 목록에 없어야 한다 |

요약 줄은 `Plan: 1 to add, 0 to change, 1 to destroy`다. 승인하면 state가 실제와 같아진다.

⛔ 변경 목록에 `aws_eks_cluster`의 `version`이 뜨면 승인하지 않는다. 코드의 값이 실제와 다르다.

---

## 5. 새 마이너로 남은 Karpenter 노드를 지운다

비상 경로에서만 한다. 4.4가 끝난 직후에는 kubelet이 컨트롤플레인보다 높은 노드가 남아 있다. Kubernetes가
지원하지 않는 조합이므로 바로 정리한다. 그 노드는 `Ready`로 남아 워크로드를 계속 돌린다.

⚠️ `EC2NodeClass`의 alias는 컨트롤플레인이 `ACTIVE`가 된 뒤 약 8분이 지나야 옛 마이너의 AMI로 풀린다.
그 전에 노드를 지우면 대체 노드가 다시 새 마이너로 뜬다.

```bash
# workbench에서. AMI 이름의 마이너가 옛 마이너로 바뀔 때까지 기다린다
kubectl get ec2nodeclass default -o jsonpath='{.status.amis[*].name}'; echo

# 새 마이너 노드의 NodeClaim에 AMIDrift가 붙고 옛 마이너 노드에서는 사라진다
kubectl get nodeclaim -o custom-columns='NAME:.metadata.name,NODE:.status.nodeName,DRIFT:.status.conditions[?(@.type=="Drifted")].reason'

# 한 대씩 지우고 대체 노드가 Ready가 된 뒤 다음으로 간다
kubectl delete nodeclaim <name>
kubectl get nodes -L karpenter.sh/nodepool
```

- 직접 지우는 것은 보류의 budget을 거치지 않는다. 파드를 비울 때 PDB는 지켜진다.
- 지운 뒤 대체 노드가 `Ready`가 되기까지 1분쯤 걸린다. 그동안 그 노드의 파드는 `Pending`이다. 복제본이
  둘이고 PDB가 `minAvailable: 1`인 워크로드는 끊기지 않는다. 복제본이 하나인 워크로드는 그 시간만큼
  끊긴다.
- ⏳ 보류를 `false`로 풀면 Karpenter가 drift로 스스로 교체한다. 대상이 여러 대면 그쪽이 낫다.

---

## 6. 완료 판정

| 확인 | 명령 | 기대 |
|------|------|------|
| 컨트롤플레인 | `aws eks describe-cluster --name <cluster> --query cluster.version` | 옛 마이너 |
| 노드 | `kubectl get nodes` | 전 노드가 옛 마이너, `Ready` |
| 되돌리기 이력 | `aws eks list-updates --name <cluster>` 뒤 `describe-update` | `VersionRollback`, `Successful` |
| cluster-autoscaler | 4.1의 조회 | 이미지가 옛 마이너 |
| addon | `upgrade.md`의 addon 조회 | 전부 `ACTIVE`. `kube-system` 파드가 전부 `Running` |
| GitOps | `runbooks.md` 「GitOps 상태 확인」 | 전부 `Synced`/`Healthy` |
| 드리프트 | `gh workflow run deploy-<env>-eks.yml --ref main -f action=plan` | plan job 로그에 `No changes` |
| Insights | `upgrade.md`의 Upgrade Insights 조회 | `UPGRADE_READINESS`가 전부 `PASSING` |

보류(`upgradeHoldByTier`)는 다시 올릴 계획이 없을 때 `false`로 되돌린다. 곧 다시 올린다면 그대로 둔다.

---

## 7. 자주 막히는 지점

| 증상 | 원인 | 대응 |
|------|------|------|
| revert한 apply가 `Kubelet version rollback compatibility`로 거부된다 | 새 마이너의 노드가 남아 있다 | 3절로 대상을 읽는다. system 노드면 4.2가 끝나지 않은 것이고, Karpenter 노드면 2절의 표로 경로를 다시 고른다 |
| `--force` 옵션이 없다고 나온다 | AWS CLI가 되돌리기 기능보다 오래됐다 | CLI를 올린다 |
| 지운 Karpenter 노드가 다시 새 마이너로 뜬다 | `EC2NodeClass`가 아직 새 마이너의 AMI를 가리킨다 | 5절의 조회로 AMI가 풀린 것을 확인한 뒤 다시 지운다 |
| 4.5의 plan이 클러스터 `version`을 올리려 한다 | revert가 머지되지 않았거나 다른 변경이 먼저 머지됐다 | 승인하지 않고 Reject한다. revert를 머지한 run의 plan을 다시 읽는다 |
