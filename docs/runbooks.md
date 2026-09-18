# 운영 런북

**읽는 사람**: 이미 구축된 환경을 운영하는 사람.

환경을 **구축하고 철거하는** 절차는 hub는 [`hub-lifecycle.md`](hub-lifecycle.md),
spoke는 [`spoke-lifecycle.md`](spoke-lifecycle.md)가 소유한다.

---

## 1. 클러스터에 접근하기

EKS 엔드포인트가 private이므로 노트북에서 `kubectl`이 직접 닿지 않는다. workbench를 경유한다.

```bash
aws --profile <profile> --region <region> ssm start-session --target <instance-id>
```

workbench에는 kubeconfig가 이미 있다. `KUBECONFIG` 환경변수를 설정할 필요가 없다.

```bash
kubectl get nodes
k get po -A          # alias k 가 프로파일에 있다
nv                   # eks-node-viewer
```

> `send-command`로 비밀·자격증명을 조회하지 않는다. 출력이 SSM에 저장되고 CloudTrail에 남는다.
> 값을 봐야 하면 **대화형 세션**에서 사람이 직접 읽는다.

---

## 2. ArgoCD 웹 UI 접속: 2홉

ArgoCD `Service`는 `ClusterIP`다. 노출을 만들지 않고 기존 인증 채널 위에 스트림만 얹는다.
평소에는 `eks-argocd-tunnel-connect` 스킬(`.claude/skills/`, 멱등·자동 재연결)을 쓴다. 아래는
같은 일을 손으로 한다.

```bash
# 1홉: workbench 안에서 port-forward
export HOME=/root KUBECONFIG=/root/.kube/config
setsid nohup kubectl -n argocd port-forward svc/argocd-server 8080:443 \
  --address 127.0.0.1 > /tmp/argocd-pf.log 2>&1 < /dev/null &

# 2홉: 로컬에서 SSM 포트 포워딩
aws --profile <profile> --region <region> ssm start-session \
  --target <instance-id> --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

브라우저에서 **https://localhost:8080**. 자체 서명 인증서 경고는 통과한다.

| 증상 | 원인 | 대응 |
|------|------|------|
| 갑자기 끊긴다 | SSM 세션 **유휴 타임아웃**(기본 20분) | 2홉만 다시 실행한다. 1홉은 살아 있다 |
| 재부팅·교체 후 안 된다 | 1홉이 사라졌다 | 1홉부터 다시 |

안쪽 홉은 `ClusterIP`가 가상 IP이기 때문에 필요하다 — 각 **노드**의 kube-proxy가 DNAT할 뿐이라
노드가 아닌 workbench에는 그 규칙이 없다. 바깥쪽 홉은 workbench의 인바운드가 0이라서 필요하다.

---

## 3. ArgoCD 관리자 비밀번호 교체

seed 직후 **완료 조건**이다. 선택 항목이 아니다.

```bash
export ARGOCD_OPTS='--port-forward --port-forward-namespace argocd --insecure'

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo      # 대화형 세션에서만

argocd login --username admin                            # 프롬프트
argocd account update-password 2>/tmp/argocd-pw.err
kubectl -n argocd delete secret argocd-initial-admin-secret
```

| 주의 | 내용 |
|------|------|
| `--core`는 쓸 수 없다 | argocd-server를 우회해 **세션 토큰이 없다**. 신원이 필요한 작업은 `--port-forward` |
| `--insecure`의 뜻 | **클라이언트** 인증서 검증 생략이다. 서버 TLS를 끄는 것이 아니다 |
| `broken pipe` 로그 | 포워더가 CLI 안에서 돌아 stderr로 섞인다. **실패가 아니다**(`2>`로 분리한다) |
| 새 비밀번호 | `^.{8,32}$`를 만족해야 한다 |

교체 확인:

```bash
kubectl -n argocd get secret argocd-secret \
  -o jsonpath='{.data.admin\.passwordMtime}' | base64 -d; echo
kubectl -n argocd get secret argocd-initial-admin-secret     # NotFound 여야 한다
```

> 이 patch는 `selfHeal`에 되돌려지지 않는다. 차트가 `argocd-secret`을 `data` 없이 렌더하므로
> 런타임에 채워진 `admin.password`는 ArgoCD의 소유 필드가 아니다.

---

## 4. EKS 업그레이드

### 하드 제약 두 가지

- **마이너는 1단계씩만.** `1.35 -> 1.37` 직행은 불가하다. 두 번 돈다.
- **컨트롤플레인을 올리기 전에** 노드 kubelet이 이미 컨트롤플레인과 같은 마이너여야 한다.

### apply를 셋으로 나눈다

| 단계 | 바꾸는 값 | 무엇이 일어나나 |
|------|----------|----------------|
| 사전 | (없음) | Upgrade Insights로 deprecated API 스캔 + 노드 kubelet 버전 확인 |
| **apply 1** | `kubernetes_version` **+1 마이너** | 컨트롤플레인만 |
| **apply 2** | `managed_node_groups[*].ami_release_version` | 노드 롤링 교체 |
| **apply 3** | `cluster_addons[*].addon_version` **전부** | addon |

**한 커밋에 몰지 않는다.** 순서가 의존성 그래프에 맡겨지는데, 모듈이 심어 둔 순서
(vpc-cni의 `before_compute`)는 **최초 생성** 기준이지 업그레이드 기준이 아니다. 승인도 갈린다:
컨트롤플레인 업그레이드는 rollback 창이 7일이고 노드 교체는 워크로드 중단을 동반한다. 한 plan에
섞으면 **승인자가 무엇을 승인하는지 분간할 수 없다.**

### 값을 조회하는 법: 추정하지 않는다

```bash
# 현재 버전
aws eks describe-cluster --name <cluster> --query 'cluster.version'

# ami_release_version — 아키텍처별로 값이 다르다
aws ssm get-parameter --region <region> \
  --name /aws/service/eks/optimized-ami/<k8s>/amazon-linux-2023/arm64/standard/recommended/release_version
#                                                                  ^^^^^ x86_64 는 여기를 바꾼다

# addon_version — f(kubernetes_version, region) 이다. k8s를 올릴 때마다 전 addon 재조회
aws eks describe-addon-versions --region <region> \
  --kubernetes-version <k8s> --addon-name <name> \
  --query 'addons[].addonVersions[].addonVersion'
```

> addon 버전은 **k8s 축과 리전 축 양쪽으로 파손된다.** 그래서 핀의 소유자가 모듈이 아니라
> 배포 루트다.

---

## 5. GitOps 상태 확인

```bash
kubectl -n argocd get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

| 상태 | 뜻 |
|------|-----|
| `Synced` / `Healthy` | 정상 |
| `OutOfSync`가 **고착** | 대개 CRD 스키마 defaulting. 해당 Application에 `ServerSideDiff=true`를 켠다 |
| `Progressing`이 오래 | 파드 이벤트를 본다. 대개 이미지 pull 또는 리소스 부족 |

root Application이 저장소를 실제로 읽었는지는 **revision으로** 판정한다:

```bash
kubectl -n argocd get application root-app -o jsonpath='{.status.sync.revision}{"\n"}'
```

값이 `main`이면 아직 **설정값**이다. **실제 커밋 SHA여야** pull에 성공한 것이다.

---

## 6. workbench 교체

`user_data`는 **부팅 때만 돈다.** 그래서 부팅 당시 조건이 틀렸던 인스턴스는 `apply`로 고쳐지지 않고
**교체해야** 코드가 상태를 되찾는다(예: 클러스터보다 먼저 떠서 kubeconfig가 없는 경우).

```bash
# hub
gh workflow run deploy-hub-eks.yml --ref main \
  -f action=apply -f replace='module.workbench.aws_instance.this[0]'

# spoke(dev)
gh workflow run deploy-dev-eks.yml --ref main \
  -f action=apply -f replace='module.workbench.aws_instance.this[0]'
```

교체 후 kubeconfig · 도구 · 프로파일은 `user_data`가 다시 만든다.
**다시 서지 않는 것은 port-forward뿐이다.** 「ArgoCD 웹 UI 접속」을 다시 실행한다.

`instance_type`을 기본값보다 작게 잡지 않는다. 부팅 중 `dnf`가 OOM으로 죽어
도구가 설치되지 않은 채 인스턴스만 정상으로 보인다.

---

## 7. 배포 워크플로가 실패했을 때

### `tofu init`이 모듈을 못 받는다

```
fatal: unable to access 'https://github.com/...': server certificate verification failed
```

**일시적 장애다.** 같은 run 안에서 다른 모듈은 받아지고, 재실행하면 통과한다.

```bash
gh run rerun <run-id> --failed
```

> 🔴 **새로 `workflow run`을 누르지 않는다.** dispatch는 plan을 처음부터 다시 돌려 새 승인
> 대상을 만든다. `--failed`는 같은 run의 **이미 승인한** 저장된 plan을 그대로 쓴다. 실패한 것이
> plan job이면 어느 쪽이든 같지만, **apply job이면 이 구분이 승인 게이트 그 자체다.**

---

## 8. 자주 쓰는 조회

```bash
# kubeconfig 재생성 (--name 필수. ListClusters 권한이 없다)
aws eks update-kubeconfig --region <region> --name <cluster>

# 노드 현황
kubectl get nodes -L node.kubernetes.io/instance-type,topology.kubernetes.io/zone

# Karpenter가 만든 노드만
kubectl get nodes -l karpenter.sh/nodepool
```

> `kubectl -o jsonpath`는 map 순회를 지원하지 않는다. 필요하면 `-o go-template`을 쓴다.

---

## 9. 노드 배치: Karpenter와 Cluster Autoscaler를 같이 쓴다

app 워크로드는 Karpenter가, 플랫폼 컴포넌트와 상태 저장 OSS(redis·postgresql·mongodb)는 관리형
노드그룹이 받는다. 두 컨트롤러를 같이 켜는 근거는 `iac-module-library`의
`docs/architectures/gitops-hub-spoke/aws/` 패턴 문서가 갖고, 여기는 배선과 확인 절차를 적는다.

### 두 축

| 축 | 값 | 하는 일 |
|---|---|---|
| 밀어내기 | 노드그룹 taint `CriticalAddonsOnly=true:NO_SCHEDULE` | 이 taint를 견디지 못하는 파드를 노드그룹 밖으로 밀어낸다 |
| 끌어당기기 | 노드 라벨 `workload-class=system` | 이 라벨을 `nodeSelector`로 요구한 파드를 그 노드에 모은다 |

한 축만 걸면 분리가 깨진다. toleration만 주고 `nodeSelector`를 빼면 그 파드는 Karpenter 노드에도
설 수 있고, 시스템 노드에 여유가 없는 순간 Karpenter가 그 파드를 위해 새 노드를 띄운다.

이름이 갈리는 것은 축마다 근거가 달라서다. 밀어내기 키는 생태계 관례를 따랐다 — 플랫폼 컴포넌트
여럿이 `CriticalAddonsOnly` toleration을 차트 기본값으로 갖고 있어 키를 맞추면 우리가 써 넣을
값이 줄어든다. 끌어당기기 쪽에는 그런 관례가 없어서 노드그룹 `labels`로 우리가 만든다.

⚠️ **관례 키를 쓰는 대가가 있다.** `CriticalAddonsOnly` toleration을 기본으로 달고 오는 차트는
우리가 허락하지 않아도 이 노드그룹에 설 수 있고, `nodeSelector`는 파드를 보내는 장치이지 남을
막는 장치가 아니라 이것을 못 막는다. ⇒ **새 차트를 들일 때 기본 `tolerations`부터 읽고**(아래
「기본값을 읽는 법」), 그 파드가 시스템 노드그룹에 서도 되는지 판정한다.

### 설정표

기본값이 요구를 이미 만족하는 칸에 **같은 값을 다시 쓰지 않는다.** 배열 필드는 병합이 아니라
교체라, 덧붙이려고 쓴 값이 덮어쓰기가 된다.

| 대상 | 우리가 명시하는 것 | 나머지를 덮는 기본값 |
|---|---|---|
| 시스템 관리형 노드그룹(`managed_node_groups`) | taint `CriticalAddonsOnly=true:NO_SCHEDULE` + 라벨 `workload-class=system` | — |
| coredns · metrics-server · **ebs-csi controller** | `nodeSelector`만 | addon 기본 toleration이 `CriticalAddonsOnly: Exists`다 |
| **cert-manager**(컨트롤러·cainjector·webhook) | 셋 다 `nodeSelector` + toleration | 없다. 기본 toleration을 갖지 않는 유일한 addon이다 |
| **Karpenter 컨트롤러**(helm) | 아무것도 쓰지 않는다 | 기본 toleration `CriticalAddonsOnly: Exists` + 기본 affinity `karpenter.sh/nodepool DoesNotExist` |
| Cluster Autoscaler(helm) | `nodeSelector` + toleration + `karpenter.sh/nodepool DoesNotExist` affinity | 차트 기본값이 셋 다 비어 있다 |
| KEDA(helm) | `nodeSelector` + toleration | 차트 기본값이 비어 있다 |
| ALBC · Kyverno · ArgoCD(helm) | toleration만(고정이 아니라 부트스트랩 허용) | 차트 기본값이 비어 있다 |
| redis·postgresql·mongodb(helm) | `nodeSelector` + toleration | — |
| vpc-cni · eks-pod-identity-agent · **efs-csi node**(DaemonSet) | 아무것도 쓰지 않는다 | 차트 기본값 `tolerations: [{operator: Exists}]`가 모든 taint를 통과한다 |
| **ebs-csi node**(DaemonSet) | `node.tolerateAllTaints = true` | 같은 값이 기본이다. 명시는 "DaemonSet은 모든 taint를 통과한다"를 눈에 보이게 두려는 것이다 |
| kube-proxy | 아무것도 쓰지 않는다 | 매니페스트에 `operator: Exists`가 하드코딩돼 있다(`configuration_values` 스키마에 `tolerations` 필드가 없다) |
| **efs-csi controller** | 들일 때 판정한다 | ⚠️ 기본값을 확인하지 않았다. `CriticalAddonsOnly`가 없으면 cert-manager와 같이 쓴다 |
| app 워크로드 | 아무것도 쓰지 않는다 | 제약이 없는 것이 곧 Karpenter 영역이다 |
| Karpenter `NodePool` | taint를 두지 않는다 | — |

⛔ **DaemonSet 넷(vpc-cni·eks-pod-identity-agent·ebs-csi node·efs-csi node)에 `nodeSelector`를
걸지 않는다.** Karpenter 노드에서 네트워킹·Pod Identity·볼륨 마운트가 통째로 죽는다. 예외 없다.

⚠️ **Karpenter `NodePool`에 taint를 두지 않는 것도 결정이다.** 위 배선으로 파드가 이미 한쪽으로만
갈 수 있다. 여기에 taint를 더하면 모든 app Deployment가 toleration을 알아야 하는 마찰만 남는다.

⚠️ **Karpenter 컨트롤러의 고정은 노드그룹이 하나일 때만 성립한다.** 차트 기본 affinity는
"Karpenter가 만든 노드는 안 된다"만 말하고, 남는 후보가 시스템 노드그룹뿐이라 거기 선다. 관리형
노드그룹을 하나 더 만들면 그때 `nodeSelector`를 명시로 채운다(Cluster Autoscaler가 그 형태다).

⚠️ **ALBC·Kyverno·ArgoCD의 toleration은 고정이 아니라 부트스트랩 허용이다.** Karpenter 노드가
없는 구간에서 설 자리를 주는 것이 목적이라, 노드가 생긴 뒤에는 어느 쪽에 있어도 된다.
⛔ 고정할 근거가 생기기 전에 `nodeSelector`를 미리 넣지 않는다.

🔴 **`aws-ebs-csi-driver`는 `node`(DaemonSet)와 `controller`(Deployment, 2 replica)로 나뉘고
스키마도 `node.*`·`controller.*`로 분리돼 있다.** `controller`의 기본 toleration이 우리 taint를
통과해서 밀어내기 축은 이쪽을 건드리지 않고, 빠뜨리기 쉬운 쪽은 끌어당기기 축이다 —
`nodeSelector`가 없으면 무제약 상태로 남아 Karpenter가 그 파드를 위해 노드를 만든다.
`aws-efs-csi-driver`도 구조가 같다.

### 기본값을 읽는 법

설정표의 "쓰지 않는다" 판정은 전부 아래 출력에서 나온다. **추정하지 않는다.** 두 명령 다 클러스터
없이 돌아서 철거 상태에서도 다시 찍는다.

```bash
# 계층 1: EKS 관리형 addon — 스키마의 default 필드가 "안 적으면 쓰이는 값"이다
aws eks describe-addon-configuration --addon-name coredns \
  --addon-version <ver> --region <region> --profile <profile> \
  --query 'configurationSchema' --output text | python3 -m json.tool | grep -B2 -A8 tolerations

# 계층 2: helm 차트
helm show values <chart> --repo <url> --version <ver> | grep -A4 '^tolerations:'
helm show values oci://public.ecr.aws/karpenter/karpenter --version <ver> | grep -A4 '^tolerations:'
```

⚠️ **버전을 올릴 때 다시 찍는다.** 상향 대상이 설정표의 "쓰지 않는다" 칸에 있으면 올리기 전에
기본값이 그대로인지 본다. 사라져 있으면 `nodeSelector`에 고정된 파드가 갈 곳을 잃고 `Pending`으로
멈추고, coredns가 그러면 클러스터 DNS가 함께 멈춘다.

### addon 주입 (`cluster_addons[name].configuration`)

써 넣는 값의 대부분이 끌어당기기 축이다. toleration을 직접 쓰는 자리는 cert-manager 하나뿐이다.

```hcl
locals {
  # 끌어당기기 축만 갖는 값. 밀어내기는 이 addon들의 기본 toleration이 이미 통과한다.
  system_node_selector = jsonencode({
    nodeSelector = { "workload-class" = "system" }
  })

  # 두 축을 다 갖는 값. 기본 toleration이 없는 addon만 쓴다.
  system_node_placement = jsonencode({
    nodeSelector = { "workload-class" = "system" }
    tolerations = [
      { key = "CriticalAddonsOnly", operator = "Equal", value = "true", effect = "NoSchedule" },
    ]
  })
}

cluster_addons = {
  "coredns"        = { configuration = local.system_node_selector }
  "metrics-server" = { configuration = local.system_node_selector }
  "aws-ebs-csi-driver" = {
    configuration = jsonencode({
      node       = { tolerateAllTaints = true }
      controller = jsondecode(local.system_node_selector)
    })
  }
  # 세 컴포넌트가 각자 받는다. 최상위만 주면 cainjector·webhook이 빠진다.
  "cert-manager" = {
    configuration = jsonencode(merge(
      jsondecode(local.system_node_placement),
      {
        cainjector = jsondecode(local.system_node_placement)
        webhook    = jsondecode(local.system_node_placement)
      }
    ))
  }
}
```

⚠️ **배열 필드를 쓰면 기본값이 통째로 사라진다.** EKS는 `configuration_values`의 배열을 병합하지
않는다. coredns에 `tolerations`를 적으면 `node-role.kubernetes.io/control-plane`이, ebs-csi
controller에 적으면 `NoExecute/Exists/300s`가 함께 지워진다. vpc-cni·eks-pod-identity-agent에
좁은 `tolerations`를 쓰면 기본값(`operator: Exists`)보다 좁아지는 것과 같은 함정이다.

🔑 **불리언 필드가 있으면 그것을 쓴다.** `ebs-csi node`의 `node.tolerateAllTaints`가 그 형태고,
controller 쪽에는 그런 불리언이 없어 `nodeSelector`로 간다.

⚠️ **`vpc-cni`는 `enable_custom_networking = true`에서 이 절이 닿지 않는다.** 모듈
(`modules/eks-cluster/addons.tf`의 재주입 로직)이 `configuration_values`를 env·eniConfig로 다시 써서
소비자 입력을 덮는다. 설정표대로 손댈 필요도 없다.

### 확인 (workbench에서)

```bash
# 두 축이 노드에 붙었는지
kubectl describe node -l workload-class=system | grep -A2 Taints   # CriticalAddonsOnly=true:NoSchedule

# 파드가 어디에 떴고 무엇을 견디는지 — 설정표와 한 화면에서 대조한다
kubectl -n kube-system get pod -o custom-columns=\
NAME:.metadata.name,NODE:.spec.nodeName,TOLERATIONS:.spec.tolerations[*].key

# Karpenter가 불필요한 노드를 만들지 않았는지
kubectl get nodeclaims
```

⚠️ 두 번째 출력에서 **`TOLERATIONS`가 비어 있는 파드**를 먼저 본다. 기본값에 기댄 자리인데 값이
없으면 그 기본값이 사라진 것이고, `nodeSelector`에 고정된 파드는 곧 `Pending`이 된다.
