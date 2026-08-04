# live/dev/eks

EKS 클러스터 하나를 배포하는 루트다. 모듈은 `iac-module-library` 에서 **git tag 로 소싱**한다
(`eks-cluster-v1.0.0`, D20). **networking 루트와 독립된 state**(`dev/eks.tfstate`)를 쓴다.

> ⚠️ 이 디렉토리도 코드만 보고는 어느 버킷·어느 계정을 가리키는지 알 수 없다(D25). 그 대가로
> 이 README 가 **주입 변수명을 명시할 의무**를 진다(§1). networking 의 README 와 같은 규약이다.

---

## 0. vpc 와 eks 는 독립적으로 배포된다 — 어떻게

두 루트는 **state 를 공유하지 않는다.** 결합은 오직 **태그 data source 조회**로만 일어난다.

| 무엇 | 방법 |
|------|------|
| VPC 찾기 | `data.aws_vpc` — `tag:Name = vpc-ref-dev-an2-main` + `tag:Workload = ref` (공용 계정이라 2중 필터) |
| 노드 서브넷 | `data.aws_subnets` — `vpc-id` + `tag:SubnetGroup = node-uniq` (vpc-v1.2.0 D13) |
| Pod 서브넷 | `data.aws_subnets` — `vpc-id` + `tag:SubnetGroup = pod-dup` |

- **remote_state 를 쓰지 않는다.** 네이밍이 결정적이라 태그 조회가 예측 가능하다(모듈 repo 03 §3.1,
  networking `outputs.tf` 주석). remote_state 는 두 루트를 state 수준에서 묶어 독립성을 깬다.
- **배포 순서**: networking 이 먼저다. VPC·서브넷·태그가 없으면 이 루트의 data source 가 빈 결과를
  내고 plan 이 **명확히 실패**한다(조용한 오작동이 아니다). 파기는 역순 — eks 를 먼저 파기한다.
- 🔑 **공유하는 것은 state 가 아니라 클러스터 이름이라는 상수**다: `eks-ref-dev-an2-main-01`.
  networking 이 이 이름으로 서브넷 디스커버리 태그를, 이 루트의 모듈이 같은 이름으로 node SG 태그를
  붙인다. 두 곳이 각자 조합하되 **정확히 같아야 한다**(어긋나면 selector 가 빈 결과 → 조용한 실패).

---

## 1. 주입되는 값 — 코드에 없는 것들

| 무엇 | 어디서 | 어떻게 |
|------|--------|--------|
| state 버킷명 | CI: repo 변수 `TF_STATE_BUCKET` · 로컬: gitignore 된 `backend.hcl` | `tofu init -backend-config=...` |
| state key | 같음 (**`dev/eks.tfstate`** — networking 과 다르다) | 동일 |
| **실행 Role ARN** | CI: repo 변수 `AWS_EXEC_ROLE_ARN` · 로컬: `TF_VAR_execution_role_arn` | provider `assume_role` |
| 입구 Role ARN | CI: repo 변수 `AWS_ENTRY_ROLE_ARN` | `configure-aws-credentials` (워크플로) |
| **public 접근 CIDR** | CI: repo 변수 `EKS_PUBLIC_ACCESS_CIDRS` · 로컬: `TF_VAR_public_access_cidrs` | 모듈 `public_access_cidrs` |

- `backend.hcl`·backend 규약은 networking README §1 과 **동일**하다(CI 는 `assume_role` 포함, 로컬은 제외).
  차이는 **state key 하나**(`dev/eks.tfstate`)뿐이다.
- ⚠️ **`EKS_PUBLIC_ACCESS_CIDRS` 는 JSON 배열 문자열**이어야 한다(list 타입 주입):
  `["1.2.3.4/32","5.6.7.8/32"]`. 운영자 출발지 IP 라 git 에 두지 않는다(D25 의 연장).
  기본값이 없어 **값 없이는 plan 이 실패**한다 — 빈 리스트면 EKS 가 0.0.0.0/0 으로 전면 개방하기 때문이다.

---

## 2. 로컬에서 할 수 있는 것 / 없는 것

```bash
# ✅ backend·자격증명 없이 모듈 소싱과 문법 확인
tofu -chdir=live/dev/eks init -backend=false
tofu -chdir=live/dev/eks validate
```

```bash
# ⛔ 할 수 없다 — 실행 Role 신뢰가 입구 Role 하나뿐이라 개인 IAM user 로는 assume 불가(D27-1)
tofu -chdir=live/dev/eks plan   # → AccessDenied. plan 은 CI 에서만 돈다.
```

결함이 아니라 신뢰 경계다(networking README §2 와 동일).

---

## 3. 형상 (enterprise 프로파일 — 사용자 결정 2026-08-03)

| 항목 | 값 |
|------|-----|
| k8s 버전 | `1.35` (N-1) |
| 엔드포인트 | **public-restricted** + private (public 은 `public_access_cidrs` 로 좁힘) |
| custom networking | ON — Pod 는 `pod-dup`(100.64/16 비라우팅), 노드는 `node-uniq` 로 SNAT (VPC D9) |
| 노드그룹 | `system` — **t4g.medium(graviton/arm64) × 2~4** (앱·버스트는 Karpenter) |
| AMI | `AL2023_ARM_64_STANDARD` · release `1.35.6-20260728` **핀**(D-NODE-ARCH · D-NODE-AMI-PIN) |
| addon | baseline 6종 + `cert-manager` · `external-dns` — **8종 전부 버전 핀**(merge, 누락!=삭제) |
| Karpenter | ON (IAM 전제. helm/NodePool 은 GitOps) |
| 컨트롤러 IAM | ALBC · external-dns Pod Identity role ON |
| 컨트롤플레인 로깅 | `api` · `audit` · `authenticator` |
| 삭제 보호 | `deletion_protection = true` (AWS 네이티브) |

이 루트가 만들지 **않는** 것: helm 릴리스 · NodePool/NodeClass · Issuer/Certificate CR ·
external-dns 애노테이션. 전부 GitOps(pull) 소관이다(설계 §1 경계). 이 루트는 그 전제(클러스터·IAM)만 만든다.

---

## 4. ⚠️ pre-apply 체크리스트 — apply 전에 반드시 채운다

이 루트는 **코드만 먼저 들어왔다**(2026-08-03, 사용자 결정 "코드만 추가"). 실제 apply 전에:

1. ✅ **repo 변수 `EKS_PUBLIC_ACCESS_CIDRS`** — 설정 완료(2026-08-03). 없으면 plan 이 실패한다.
2. ✅ **`ami_release_version` 핀** — `1.35.6-20260728`(arm64, 2026-08-04 실측).
   ⚠️ **아키텍처별로 값이 다르다.** 이 루트는 graviton 이므로 **arm64 경로**에서 얻는다:
   `aws ssm get-parameter --profile team --region ap-northeast-2 --name /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/arm64/standard/recommended/release_version`
3. ✅ **networking 선행 apply** — 완료(2026-08-03, `0 added / 6 changed / 0 destroyed`).
   karpenter 디스커버리 태그(node-uniq)와 serial 포함 클러스터명 태그가 붙어 있어야 조회가 성립한다.
4. ⏳ **plan 의 destroy/replace 목록을 읽는다**(공용 계정, D27-2). apply 는 `workflow_dispatch` 로만.

### 🔄 버전을 올릴 때 함께 고치는 것 (묶음이 깨지면 apply 가 죽는다)

`kubernetes_version` 을 올리면 **아래가 한 커밋 안에서 같이** 움직여야 한다:

| 대상 | 이유 |
|------|------|
| `cluster_addons` 8종의 `addon_version` | 값이 `f(k8s, region)` 이다. 특히 `kube-proxy` 는 **정의상** k8s 마이너를 따라간다 |
| `ami_release_version` | k8s 버전별 AMI 다. ⚠️ **arm64 경로**에서 얻는다 |

`instance_types` 의 아키텍처를 바꿀 때는 **`ami_type` 과 `ami_release_version` 을 함께** 고친다.
이 불일치는 plan 에서 잡히지 않는다(AWS 도 노드그룹 생성 시점에야 거부한다).

### 💰 비용 (enterprise 프로파일)

EKS 컨트롤플레인 ~$73/월 + system 노드 2×t4g.medium ~$48/월 + 컨트롤플레인 로그.
networking 의 NAT ~$43/월 위에 얹힌다.

---

## 5. teardown

`deletion_protection = true` 이므로 **2단계**다(모듈 D-EKS-PROTECT, networking 과 같은 취지).

```
① deletion_protection = false 로 apply   # 네이티브 보호 해제
② cluster_enabled = false 로 apply        # 클러스터·노드·IAM 파기
```

⚠️ ①을 건너뛰면 모듈 변수 validation 이 먼저 막는다. eks 를 파기한 뒤에야 networking 을 파기한다(역순).
