# live/hub/eks

EKS 클러스터 하나를 배포하는 루트다. 모듈은 `iac-module-library` 에서 **git tag 로 소싱**한다
(정확한 태그는 `main.tf` 참조 — SSOT는 `main.tf`, 여기 다시 적지 않는다). **networking 루트와
독립된 state**(`hub/eks.tfstate`)를 쓴다.

> ⚠️ 이 디렉토리도 코드만 보고는 어느 버킷·어느 계정을 가리키는지 알 수 없다(D25). 그 대가로
> 이 README 가 **주입 변수명을 명시할 의무**를 진다(「1. 주입되는 값 — 코드에 없는 것들」). networking 의 README 와 같은 규약이다.

---

## 0. vpc 와 eks 는 독립적으로 배포된다 — 어떻게

두 루트는 **state 를 공유하지 않는다.** 결합은 오직 **태그 data source 조회**로만 일어난다.

| 무엇 | 방법 |
|------|------|
| VPC 찾기 | `data.aws_vpc` — `tag:Name = vpc-demo-hub-an2-main` + `tag:Workload = demo` (공용 계정이라 2중 필터) |
| 노드 서브넷 | `data.aws_subnets` — `vpc-id` + `tag:SubnetGroup = node-uniq` (vpc-v0.3.0 D13) |
| Pod 서브넷 | `data.aws_subnets` — `vpc-id` + `tag:SubnetGroup = pod-dup` |

- **remote_state 를 쓰지 않는다.** 네이밍이 결정적이라 태그 조회가 예측 가능하다(모듈 repo
  `docs/03-new-project.md`의 「2. 배포 저장소 만들기」, networking `outputs.tf` 주석). remote_state 는
  두 루트를 state 수준에서 묶어 독립성을 깬다.
- **배포 순서**: networking 이 먼저다. VPC·서브넷·태그가 없으면 이 루트의 data source 가 빈 결과를
  내고 plan 이 **명확히 실패**한다(조용한 오작동이 아니다). 파기는 역순 — eks 를 먼저 파기한다.
- 🔑 **공유하는 것은 state 가 아니라 클러스터 이름이라는 상수**다: `eks-demo-hub-an2-main-01`.
  networking 이 이 이름으로 서브넷 디스커버리 태그를, 이 루트의 모듈이 같은 이름으로 node SG 태그를
  붙인다. 두 곳이 각자 조합하되 **정확히 같아야 한다**(어긋나면 selector 가 빈 결과 → 조용한 실패).

---

## 1. 주입되는 값 — 코드에 없는 것들

| 무엇 | 어디서 | 어떻게 |
|------|--------|--------|
| state 버킷명 | CI: repo 변수 `TF_STATE_BUCKET` · 로컬: gitignore 된 `backend.hcl` | `tofu init -backend-config=...` |
| state key | 같음 (**`hub/eks.tfstate`** — networking 과 다르다) | 동일 |
| **실행 Role ARN** | CI: repo 변수 `AWS_EXEC_ROLE_ARN` · 로컬: `TF_VAR_execution_role_arn` | provider `assume_role` |
| 입구 Role ARN | CI: repo 변수 `AWS_ENTRY_ROLE_ARN` | `configure-aws-credentials` (워크플로) |

⛔ **`EKS_PUBLIC_ACCESS_CIDRS` 행은 삭제됐다**(2026-08-06, private-only 전환). 변수·주입 지점·
repo 변수를 함께 걷어냈다 — public 이 꺼지면 EKS 가 그 값을 무시하므로 남겨 두면
*"좁혀 두었다"* 는 착시만 만든다.

- `backend.hcl`·backend 규약은 networking README의 「1. 주입되는 값 — 코드에 없는 것들」과 **동일**하다(CI 는 `assume_role` 포함, 로컬은 제외).
  차이는 **state key 하나**(`hub/eks.tfstate`)뿐이다.

---

## 2. 로컬에서 할 수 있는 것 / 없는 것

```bash
# ✅ backend·자격증명 없이 모듈 소싱과 문법 확인
tofu -chdir=live/hub/eks init -backend=false
tofu -chdir=live/hub/eks validate
```

```bash
# ⛔ 할 수 없다 — 실행 Role 신뢰가 입구 Role 하나뿐이라 개인 IAM user 로는 assume 불가(D27-1)
tofu -chdir=live/hub/eks plan   # → AccessDenied. plan 은 CI 에서만 돈다.
```

결함이 아니라 신뢰 경계다(networking README의 「2. 로컬에서 할 수 있는 것 / 없는 것」과 동일).

---

## 3. 형상 (enterprise 프로파일 — 사용자 결정 2026-08-03)

| 항목 | 값 |
|------|-----|
| k8s 버전 | `1.35` (N-1) |
| 엔드포인트 | **private-only** (2026-08-06 전환). apiserver 도달 경로는 **VPC 내부뿐** — 조작은 workbench 를 통해서만 |
| custom networking | ON — Pod 는 `pod-dup`(100.64/16 비라우팅), 노드는 `node-uniq` 로 SNAT (VPC D9) |
| 노드그룹 | `system` — **t4g.medium(graviton/arm64) × 2~4** (앱·버스트는 Karpenter) |
| AMI | `AL2023_ARM_64_STANDARD` · release `1.35.6-20260810` **핀**(D-NODE-ARCH · D-NODE-AMI-PIN) |
| addon | baseline 6종 + `cert-manager` — **7종 전부 버전 핀**(merge, 누락!=삭제). `external-dns` 는 **미탑재가 기본값**(D-EXTDNS-ZONE, 2026-08-05) |
| Karpenter | ON (IAM 전제. helm/NodePool 은 GitOps) |
| 컨트롤러 IAM | ALBC Pod Identity role ON. **external-dns 는 OFF**(addon 과 한 쌍이라 함께 끈다) |
| 컨트롤플레인 로깅 | `api` · `audit` · `authenticator` |
| 삭제 보호 | `deletion_protection = true` (AWS 네이티브) |
| **workbench** | **ON** — `vm-uniq` private 서브넷, **`t4g.small`(arm64, 2GB — 모듈 기본값)**, SSM 전용(인바운드 0). 도구: `kubectl v1.35.7` · `helm v3.21.3` · `argocd v3.5.0` · `git`(변수 없이 항상). 워크벤치 모듈 태그는 `main.tf` 참조. 🔴 **핀을 올리면 인스턴스가 교체된다**(`user_data_replace_on_change`). ⚠️ `t4g.nano` 로 내리면 부팅 중 `dnf` 가 OOM 으로 죽어 `git` 이 빠진다(2026-08-10 실측) |

이 루트가 만들지 **않는** 것: helm 릴리스 · NodePool/NodeClass · Issuer/Certificate CR ·
external-dns 애노테이션. 전부 GitOps(pull) 소관이다(모듈 repo `docs/01-architecture.md`의
「3. 계층 1과 2의 경계 — 컨트롤러와 설정을 가른다」). 이 루트는 그 전제(클러스터·IAM)만 만든다.

---

## 4. ⚠️ pre-apply 체크리스트 — apply 전에 반드시 채운다

이 루트는 **코드만 먼저 들어왔다**(2026-08-19, 허브-스포크 크로스 계정 IAM 설계 구현 1단계).
실제 apply 전에:

1. ⏳ **`ami_release_version` 핀 재확인** — 이 커밋 시점 값은 `1.35.6-20260810`(arm64, 2026-08-19
   조회). apply 직전 재조회해 stale 여부 확인:
   `aws ssm get-parameter --profile team --region ap-northeast-2 --name /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/arm64/standard/recommended/release_version`
2. ⏳ **`live/hub/networking` 선행 apply** — 이 루트의 data source(`data.aws_vpc`·`data.aws_subnets`)가
   조회할 대상이 먼저 존재해야 한다. karpenter 디스커버리 태그(node-uniq)와 serial 포함
   클러스터명 태그가 붙어 있어야 조회가 성립한다.
3. ⏳ **workbench AMI 핀 재확인** — 이 커밋 시점 값은 `ami-0f4109eb491b0476f`(AL2023 **arm64**,
   an2, 2026-08-19 조회):
   `aws ssm get-parameter --profile team --region ap-northeast-2 --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64`
   ⚠️ `instance_type` 기본값(모듈 기본, arm64)과 **아키텍처가 짝이다.** 모듈은 검증하지 않는다.
4. ⏳ **`enable_argocd_hub_pod_identity`가 `false`인지 확인** — 스포크(`cross-account-trust-role`)가
   아직 없다. `true`로 켜면 `argocd_hub_assumable_role_arns`가 빈 배열이라 모듈 validation이
   plan을 막는다(`main.tf` 참조).
5. ⏳ **plan 의 destroy/replace 목록을 읽는다**(공용 계정, D27-2). apply 는 `workflow_dispatch` 로만.

### workbench 도달 확인 순서 — 이 루트는 **처음부터 private-only**다

`live/dev/eks`는 public→private **전환**을 별도로 검증했지만, 이 루트는 `endpoint_public_access
= false`로 **첫 apply부터** private-only다(전환 이력이 없다 — 신규 클러스터는 workbench가 뜬
뒤에야 접근 가능하므로 순서만 지키면 충분하다). apply 후 검증 순서:

```
① workbench apply       → SSM 등록 확인
② SSM 접속               → PingStatus Online (aws ssm start-session --target <id>)
③ kubectl get nodes      → 노드 Ready — EKS 접근 3층(1층 workbench IAM·2층 access entry·
                            3층 cluster SG ingress) 전부 성립함을 이걸로 확인한다
```

③ 이 실패할 때 증상으로 층을 특정한다 — 세 층 중 무엇이 빠졌는지가 에러 형태로 갈린다:

| 증상 | 빠진 층 | 소유 |
|------|---------|------|
| `update-kubeconfig` 권한 오류 | 1층 `eks:DescribeCluster` | workbench 모듈 |
| `401 Unauthorized` | 2층 Access Entry | eks 모듈 `access_entries` |
| `dial tcp …: i/o timeout` | 3층 cluster SG ingress 443 | eks 모듈 `cluster_security_group_additional_rules` |

⚠️ timeout 은 **인증 계층에 닿지도 못했다**는 뜻이다. PoC 는 앞의 두 층만 갖추고 여기서 막혔다
(모듈 repo `docs/05-modules.md`의 「클러스터 접근 3층 — 누가 무엇을 소유하는가」).

### 버전을 올릴 때 함께 고치는 것 (묶음이 깨지면 apply 가 죽는다)

`kubernetes_version` 을 올리면 **아래가 한 커밋 안에서 같이** 움직여야 한다:

| 대상 | 이유 |
|------|------|
| `cluster_addons` 7종의 `addon_version` | 값이 `f(k8s, region)` 이다. 특히 `kube-proxy` 는 **정의상** k8s 마이너를 따라간다 |
| `ami_release_version` | k8s 버전별 AMI 다. ⚠️ **arm64 경로**에서 얻는다 |
| workbench `kubectl_version` | 클러스터 마이너와 맞춘다. `https://dl.k8s.io/release/stable-<major.minor>.txt` |

`instance_types` 의 아키텍처를 바꿀 때는 **`ami_type` 과 `ami_release_version` 을 함께** 고친다.
이 불일치는 plan 에서 잡히지 않는다(AWS 도 노드그룹 생성 시점에야 거부한다).

### 비용 (enterprise 프로파일)

EKS 컨트롤플레인 ~$73/월 + system 노드 2×t4g.medium ~$48/월 + workbench t4g.small(모듈 기본값,
workbench-v0.4.0 이 t4g.nano 의 dnf OOM 을 닫으려 상향) + 컨트롤플레인 로그.
networking 의 NAT ~$43/월 위에 얹힌다 — `live/dev`가 아직 폐기되지 않았다면 두 NAT 비용이 동시에
돈다는 뜻이다.

⚠️ workbench 는 **삭제 보호 대상이 아니다**(D-WORKBENCH-LIFECYCLE) — 상태를 담지 않아 수시 생성·파기가
정상 운용이다. 안 쓸 때 `workbench_enabled = false` 로 내려도 되지만, **public 을 닫은 뒤에는
유일한 도달 지점**이므로 내리기 전에 다른 경로를 확보한다.

---

## 5. teardown

`deletion_protection = true` 이므로 **2단계**다(모듈 D-EKS-PROTECT, networking 과 같은 취지).

```
① deletion_protection = false 로 apply   # 네이티브 보호 해제
② cluster_enabled = false 로 apply        # 클러스터·노드·IAM 파기
```

⚠️ ①을 건너뛰면 모듈 변수 validation 이 먼저 막는다. eks 를 파기한 뒤에야 networking 을 파기한다(역순).
