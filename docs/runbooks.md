# 07. 운영 런북

**읽는 사람**: 이미 선 환경을 운영하는 사람.

환경을 **만들고 걷어내는** 절차는 hub는 [`hub-lifecycle.md`](hub-lifecycle.md),
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

인스턴스 ID를 모르면:

```bash
aws --profile <profile> --region <region> ec2 describe-instances \
  --filters "Name=tag:Name,Values=*workbench*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' --output text
```

> `send-command`로 비밀·자격증명을 조회하지 않는다. 출력이 SSM에 저장되고 CloudTrail에 남는다.
> 값을 봐야 하면 **대화형 세션**에서 사람이 직접 읽는다.

---

## 2. ArgoCD 웹 UI 접속: 2홉

ArgoCD `Service`는 `ClusterIP`다. 노출을 만들지 않고 기존 인증 채널 위에 스트림만 얹는다.

```bash
# 1홉: workbench 안에서 port-forward
export HOME=/root KUBECONFIG=/root/.kube/config
setsid nohup kubectl -n argocd port-forward svc/argocd-server 18080:443 \
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

두 홉이 필요한 이유가 서로 다르다. 안쪽은 **`ClusterIP`가 가상 IP**라서,
실재하는 주소가 아니라 각 **노드**의 kube-proxy가 DNAT할 뿐이고, 노드가 아닌 workbench엔 그 규칙이 없다.
바깥쪽은 **workbench에 인바운드가 0**이라서다.

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

**한 커밋에 몰지 않는다.** 순서가 의존성 그래프에 맡겨지고, 모듈이 심어 둔 순서
(vpc-cni의 `before_compute`)는 **최초 생성**에서 옳도록 설계된 것이지 업그레이드 기준이 아니다.

승인 관점에서도 나뉘는 편이 낫다: 컨트롤플레인 업그레이드는 되돌리기 어렵고(7일 rollback 창),
노드 교체는 워크로드 중단을 동반한다. 한 plan에 섞이면 **승인자가 무엇을 승인하는지 분간할 수 없다.**

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

> addon 버전이 **k8s 축과 리전 축 양쪽으로 파손된다**는 것이 실측으로 확인됐다.
> 그래서 핀의 소유자가 모듈이 아니라 배포 루트다.

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
gh workflow run deploy-eks.yml --ref main \
  -f action=apply -f replace='module.workbench.aws_instance.this[0]'
```

교체 후 kubeconfig · 도구 · 프로파일은 `user_data`가 다시 만든다.
**다시 서지 않는 것은 port-forward뿐이다.** 위 2절을 다시 실행한다.

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

> 🔴 **새로 `workflow run`을 누르지 않는다.** dispatch는 plan을 처음부터 다시 돌려
> **승인한 것과 다른 계획**을 만든다. `--failed`는 같은 run의 저장된 plan을 그대로 쓴다.
> 실패한 것이 plan job이면 어느 쪽이든 같지만, **apply job이면 이 구분이 승인 게이트 그 자체다.**

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

## 9. Karpenter + Cluster Autoscaler 동시 운영: taint 전략

**적용 대상**: app 워크로드는 전부 Karpenter로, 필수 addon·OSS(redis·postgresql·mongodb 등
상태 저장 워크로드)는 관리형 노드그룹 + Cluster Autoscaler로 분리하고 싶은 경우.

### 원리: taint와 nodeSelector는 하는 일이 다르다

- **taint**(관리형 노드그룹에 부여) = 허용 안 한 파드를 **밀어낸다**
- **nodeSelector/affinity**(addon·OSS 쪽에 부여) = 이 라벨이 있는 곳으로만 **끌어당긴다**

toleration만 주고 nodeSelector를 빼먹으면 설계가 깨진다: OSS 파드가 taint를 참더라도
Karpenter 쪽 노드엔 그 taint가 없으니, 여유가 없으면 Karpenter가 그 파드를 위해 새 노드를
띄워버릴 수 있다. **taint(밀어내기)와 nodeSelector(끌어당기기) 둘 다 있어야** 워크로드가
결정적으로 한쪽에만 간다.

### 설정표

| 대상 | taint | nodeSelector/affinity |
|---|---|---|
| 시스템 관리형 노드그룹(`managed_node_groups`) | `workload-class=system:NO_SCHEDULE` 부여 | 라벨 `workload-class=system` 부여 |
| coredns · metrics-server · **ebs-csi controller**(Deployment) · **efs-csi controller**(Deployment) | 없음 | `nodeSelector: workload-class=system` + toleration 명시 필요 |
| vpc-cni · eks-pod-identity-agent (DaemonSet) | 없음 | 명시 불필요: 차트 기본값이 이미 `tolerations: [{operator: Exists}]`라 모든 taint를 통과한다(실측: `aws/eks-charts`·`aws/eks-pod-identity-agent` 저장소의 `values.yaml`) |
| ebs-csi node (DaemonSet) | 없음 | `node.tolerateAllTaints = true` 명시 필요: 기본 toleration은 `effect: NoExecute`만 커버해 우리가 부여하는 `NoSchedule`을 통과하지 못한다 |
| **efs-csi node**(DaemonSet) | 없음 | 명시 불필요: ebs-csi node와 달리 차트 기본값이 이미 `tolerations: [{operator: Exists}]`라 모든 taint를 통과한다(실측: `kubernetes-sigs/aws-efs-csi-driver` `charts/aws-efs-csi-driver/values.yaml`), vpc-cni·eks-pod-identity-agent와 같은 부류 |
| kube-proxy | 없음 | 손댈 필요 없음: 기본 매니페스트가 이미 `tolerations: [{operator: Exists}]`라 모든 taint를 통과한다 |
| Cluster Autoscaler·Karpenter 컨트롤러 자체(helm) | 없음 | `nodeSelector: workload-class=system` + toleration |
| redis·postgresql·mongodb(helm) | 없음 | `nodeSelector: workload-class=system` + toleration |
| app 워크로드 | 아무것도 안 함 | 아무것도 안 함(기본값이 곧 Karpenter 영역) |
| Karpenter `NodePool` | 의도적으로 taint 안 둠 | 없음 |

⚠️ **DaemonSet에 `nodeSelector`를 걸면 안 된다.** vpc-cni·eks-pod-identity-agent·ebs-csi node·
efs-csi node에 `nodeSelector: workload-class=system`을 주면 Karpenter 노드에서 네트워킹·
Pod Identity·볼륨 마운트가 통째로 죽는다. vpc-cni·eks-pod-identity-agent·efs-csi node는
위 표대로 애초에 손댈 필요가 없고, ebs-csi node만 toleration을 넓힌다: 넷 다 nodeSelector는
예외 없이 금지다.

⚠️ **Karpenter NodePool에 별도 taint를 두지 않는 것도 의도적 결정이다.** 위 분리로 이미 모든
파드 종류가 한쪽으로만 갈 수 있게 강제되어 있어서(시스템 쪽=taint+nodeSelector 이중 관문,
app 쪽=기본값), "어느 컨트롤러가 반응할지 모호한 파드"가 존재하지 않는다. Karpenter 쪽에
taint를 추가하면 모든 app Deployment가 toleration을 알아야 하는 마찰만 생긴다.

🔴 **`aws-ebs-csi-driver`는 `node`(DaemonSet)와 `controller`(Deployment, 2 replica) 둘로
나뉜다: `configuration_values` 스키마도 `node.*`·`controller.*`로 완전히 분리돼 있다.**
`node`만 고치고 `controller`를 빠뜨리면, taint 적용 순간 아무 제약도 없던 `controller` pod가
system 노드에서 밀려나 "app 워크로드"와 같은 기본값 버킷(Karpenter 영역)으로 떨어진다.
Karpenter가 이 pod들을 위해 **불필요한 새 노드를 만든다**(실측: `eks-reference-infra` dev
클러스터에서 재현). `controller`는 coredns·metrics-server와 같은 취급이 맞다: 컨트롤플레인
컴포넌트는 DaemonSet이 아닌 이상 반드시 `nodeSelector`까지 명시해야 한다.

🔑 **`aws-efs-csi-driver`도 구조가 완전히 같다**: `node`(DaemonSet)·`controller`(Deployment,
2 replica)로 분리돼 있고, 스키마도 `node.*`·`controller.*`로 나뉜다(`charts/aws-efs-csi-driver/
values.yaml` 실측). 다른 점은 `node`의 기본 toleration이 이미 `[{operator: Exists}]`라 손댈
필요가 없다는 것뿐: `controller`는 EBS와 동일하게 `nodeSelector`+`tolerations` 없이는 taint
적용 순간 Karpenter 영역으로 떨어진다.

### addon toleration 주입 (`cluster_addons[name].configuration`)

각 addon이 `configuration_values`로 tolerations/nodeSelector를 지원하는지 EKS API로 직접
확인했다(`aws eks describe-addon-configuration --addon-name <name> --addon-version <ver>`).
**실제로 손대야 하는 것은 ebs-csi(node)·ebs-csi(controller)·efs-csi(controller)·coredns·
metrics-server 다섯뿐이다**: vpc-cni·eks-pod-identity-agent·efs-csi(node)는 위 표대로
기본값이 이미 요구를 만족한다.

```hcl
cluster_addons = {
  "aws-ebs-csi-driver" = {
    configuration = jsonencode({
      node = { tolerateAllTaints = true }
      controller = {
        nodeSelector = { "workload-class" = "system" }
        tolerations  = [{ key = "workload-class", operator = "Equal", value = "system", effect = "NoSchedule" }]
      }
    })
  }
  "aws-efs-csi-driver" = {
    # node는 손댈 필요 없다 — 기본 toleration이 이미 모든 taint를 통과한다.
    configuration = jsonencode({
      controller = {
        nodeSelector = { "workload-class" = "system" }
        tolerations  = [{ key = "workload-class", operator = "Equal", value = "system", effect = "NoSchedule" }]
      }
    })
  }
  "coredns" = {
    configuration = jsonencode({
      nodeSelector = { "workload-class" = "system" }
      tolerations  = [{ key = "workload-class", operator = "Equal", value = "system", effect = "NoSchedule" }]
    })
  }
  "metrics-server" = {
    configuration = jsonencode({
      nodeSelector = { "workload-class" = "system" }
      tolerations  = [{ key = "workload-class", operator = "Equal", value = "system", effect = "NoSchedule" }]
    })
  }
}
```

⚠️ **불리언 필드가 있으면 그것을 쓰고, `tolerations` 배열은 되도록 직접 교체하지 않는다.**
EKS는 `configuration_values`의 배열 필드를 addon 차트 기본값과 **병합하지 않고 통째로
교체**한다: vpc-cni·eks-pod-identity-agent에 좁은 `tolerations`를 직접 쓰면 기본값
(`operator: Exists`, 모든 taint 통과)보다 **좁아지는 후퇴**가 된다. `ebs-csi node`가
`node.tolerateAllTaints`라는 불리언으로 같은 효과를 내는 것과 대비된다. `ebs-csi controller`·
`efs-csi controller`는 그런 불리언이 없어(스키마 확인) coredns·metrics-server와 같은 방식으로
갈 수밖에 없다. coredns·metrics-server·`ebs-csi controller`·`efs-csi controller`는
`tolerations`를 교체해도 무해하다: `nodeSelector`가 배치를 system 노드로 좁히므로, 그 노드에
있는 taint는 `workload-class` 하나뿐이라 잃을 다른 toleration이 없다.

⚠️ **`vpc-cni`는 `enable_custom_networking = true` 환경에서 이 절 자체가 무의미하다.** 모듈
(`modules/eks-cluster/addons.tf`의 vpc-cni 재주입 로직)이 커스텀 네트워킹을 켜면 vpc-cni의
`configuration_values`를 env·eniConfig로 **통째로 재주입해 소비자 입력을 덮어쓴다**. 여기에
tolerations를 적어도 반영되지 않는다. 다행히 위 표대로 손댈 필요도 없다.

`kube-proxy`는 `configuration_values` 스키마에 `tolerations` 필드 자체가 없다
(`aws/containers-roadmap#2604`가 이 부재를 지적하는 미해결 기능 요청), 이미 하드코딩된
`operator: Exists`로 모든 taint를 통과하기 때문에 손댈 것이 없다.

### 테스트 절차 (workbench에서)

workbench 접속 자체는 「1. 클러스터에 접근하기」 그대로다: SSM 세션 시작 후 `kubectl`이 바로 된다.
아래는 접속 이후, taint/toleration이 실제로 반영됐는지 보는 단계다.

```bash
# ⓪ system 노드그룹에 label·taint가 실제로 붙었는지
kubectl get nodes -l workload-class=system
kubectl describe node <system-노드-이름> | grep -A2 Taints

# ① DaemonSet(vpc-cni·eks-pod-identity-agent·ebs-csi node·efs-csi node)이 시스템 노드그룹에도
#    떠 있는지(toleration이 실제로 먹었는지 — vpc-cni·eks-pod-identity-agent·efs-csi node는
#    차트 기본값, ebs-csi는 tolerateAllTaints로 커버한다)
kubectl get pods -n kube-system -o wide -l k8s-app=aws-node
kubectl get pods -n kube-system -o wide -l app.kubernetes.io/name=eks-pod-identity-agent
kubectl get pods -n kube-system -o wide -l app=ebs-csi-node
kubectl get pods -n kube-system -o wide -l app=efs-csi-node

# ② coredns·metrics-server·ebs-csi controller·efs-csi controller가 system 노드로만 배치됐는지
#    (nodeSelector+toleration 검증 — 이 넷을 빠뜨리면 Karpenter가 불필요한 노드를 만든다)
kubectl get pods -n kube-system -o wide -l k8s-app=kube-dns
kubectl get pods -n kube-system -o wide -l app.kubernetes.io/name=metrics-server
kubectl get pods -n kube-system -o wide -l app=ebs-csi-controller
kubectl get pods -n kube-system -o wide -l app=efs-csi-controller

# ③ 격리 검증 — toleration 없는 파드는 시스템 노드그룹에 절대 못 붙는다
kubectl run probe --image=public.ecr.aws/eks-distro/kubernetes/pause:3.2 --restart=Never
kubectl get pod probe -o wide   # Pending 이거나 Karpenter 노드에 배치되어야 한다

# ④ 역방향 검증 — Karpenter가 system 노드그룹 파드 때문에 새 노드를 만들지 않는지
kubectl get nodeclaims

# ⑤ CA 활성화 이후에만: 동작 확인(`enable_cluster_autoscaler`를 켠 뒤에만 배포된다)
kubectl logs -n kube-system deploy/cluster-autoscaler

# ⑥ Karpenter 동작 확인 — app 파드가 시스템 노드그룹을 안 건드리는지
kubectl get nodes -l karpenter.sh/nodepool
```

근거: [karpenter.sh FAQ](https://karpenter.sh/docs/faq/)("Karpenter can work alongside Cluster
Autoscaler") · `aws/karpenter-provider-aws#2543`(taint 분리 없이 동시 운영 시 중복 프로비저닝
실사용 보고, 컨트리뷰터 권고: taint/toleration으로 워크로드 분리) · Karpenter 공식 마이그레이션
가이드(Karpenter 컨트롤러 자체를 기존 노드그룹에 고정하는 패턴).
