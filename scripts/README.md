# scripts: 운영 절차 스크립트

**읽는 사람**: hub에서 ArgoCD 부트스트랩·철수 검증을 실행하는 사람.

| 스크립트 | 무엇을 하는가 | 설계 SSOT |
|---|---|---|
| `teardown-verify.sh` | 철수 후 잔존물 검사(읽기 전용). 지우지 않고 남은 것만 찾는다 | `docs/hub-lifecycle.md`, `docs/spoke-lifecycle.md` |
| `validate-doc-conventions.py` | 이 저장소 문서(`docs/*.md`·`README.md`·`AGENTS.md`·`CLAUDE.md`)의 작성 규칙 검사 | `.githooks/pre-commit` |

⚠️ 모든 스크립트는 환경값을 하드코딩하지 않는다. 대상 계정·클러스터 이름 같은 값은 전부
환경변수나 인자로 받는다.

---

## hub seed 준비: GitHub App과 private key

`argocd-seed.sh` 자체는 이 저장소에 없다. `<project>-platform-gitops`의 `bootstrap/`이
소유하고 workbench에서 거기 것을 실행한다. 이 절은 그 스크립트가 **이미 있다고 전제하는**
값(`GH_APP_ID`·`GH_APP_INSTALLATION_ID`·`GH_APP_PRIVATE_KEY`)을 만들고 workbench로
나르는 절차다. seed를 돌리기 전에 끝나야 한다.

### GitHub App 만들기

`GITOPS_REPO_URL`이 가리키는 저장소가 private이면 ArgoCD와 workbench 양쪽이 GitHub App으로
인증한다. 아직 App이 없다면(신규 온보딩이나 재발급 시) 아래 절차로 만든다.

1. **등록**: GitHub 프로필 → Settings → Developer settings → GitHub Apps → New GitHub App.
   이름·설명·Homepage URL만 입력한다(Webhook은 Active를 끈다).
2. **권한**: `Repository permissions`에서 `Contents: Read-only` 하나만 준다. 이 App은 clone과
   ArgoCD repository Secret 용도이고 push하지 않는다.
3. **private key 발급**: App 설정 페이지의 `Private keys`에서 `Generate a private key`를 눌러
   PEM을 받는다. ⚠️ GitHub는 public key만 보관하므로 다운로드한 파일이 유일한 원본이다.
   분실하면 복구가 아니라 재발급(로테이션)만 가능하다.
4. **설치**: 조직 설정 → Developer settings → GitHub Apps → 해당 App의 `Edit` → `Install App`
   → `Only select repositories`로 대상 저장소(GitOps 저장소)만 선택한다.
5. **Installation ID 확인**: 웹 UI에는 직접 표시되지 않는다. `Configure` 버튼을 눌렀을 때
   URL의 마지막 세그먼트(`.../settings/installations/<ID>`)로 읽거나, App 인증 후
   `GET /orgs/<org>/installation` API로 조회한다.

발급된 App ID·Installation ID·PEM은 아래 「private key를 workbench로 옮기는 경로」와
「사용법」에서 그대로 쓴다.

### private key를 workbench로 옮기는 경로

클러스터가 private이라 seed는 workbench 안에서 실행되는데, workbench는 SSM Session
Manager 전용이라 `scp`가 없다. 스크립트는 키를 파일 경로로 받으므로(`--from-file=`),
키의 실물 파일이 workbench 디스크에 있어야 한다. 그 경로로 **SSM Parameter Store
SecureString**을 쓴다.

이 방식을 고른 근거는 세 가지 확인된 사실이다.

| 확인한 것 | 값 | 의미 |
|---|---|---|
| `AmazonSSMManagedInstanceCore` | `ssm:GetParameter`를 `Resource: "*"`로 포함 | workbench Role에 IAM 권한을 추가할 필요가 없다 |
| `alias/aws/ssm` 키 정책 | `Principal: {"AWS":"*"}` + `kms:ViaService=ssm.<region>` 직접 부여 | SecureString 복호화에 `kms:Decrypt`를 따로 추가할 필요가 없다 |
| Standard tier 파라미터 | 4KB, 과금 없음 | RSA 2048 PEM(약 1.7KB)이 넉넉히 들어간다 |

#### 절차

```bash
# ── 1) 노트북에서 한 번 — 키를 SecureString으로 올린다 ──────────────────
aws ssm put-parameter --region <region> \
  --name /<workload>/<env>/gitops/github-app-private-key \
  --type SecureString \
  --description "ArgoCD seed 임시 저장 - GitHub App private key. seed 완료 후 삭제한다" \
  --value file://~/.config/gh-apps/<app>.private-key.pem
#  --description을 반드시 붙인다. 공용 계정에는 남의 파라미터가 섞여 있어서,
#  정체를 밝히지 않으면 아무도 지우지 못하는 자격증명이 된다.

# ── 2) workbench 안에서 — 파일로 내려받는다 ──────────────────────────
umask 077                                    # 0600으로 만든다. chmod 전에 umask부터 건다
aws ssm get-parameter \
  --name /<workload>/<env>/gitops/github-app-private-key \
  --with-decryption --query Parameter.Value --output text > ~/gh-app.pem
#  리다이렉트가 핵심이다. 키가 터미널에 출력되지 않으므로 세션 로깅이 켜진
#  계정에서도 로그에 남지 않는다. 내려받은 파일은 원본보다 1바이트 크다
#  (--output text가 후행 개행을 붙인다). PEM은 이를 정상으로 받으므로
#  체크섬이 다르다고 손상으로 오해하지 않는다. 검증하려면 openssl rsa -noout -check.

export GH_APP_PRIVATE_KEY=~/gh-app.pem
#  이어서 GitOps 저장소의 bootstrap/argocd-seed.sh 를 돌린다

# ── 3) 완료 조건 — 위생이 아니라 필수 조건이다 ────────────────────────
shred -u ~/gh-app.pem
aws ssm delete-parameter --region <region> \
  --name /<workload>/<env>/gitops/github-app-private-key
```

🔴 **3단계는 선택이 아니다.** `AmazonSSMManagedInstanceCore`가 `GetParameter`를
`Resource: "*"`로 주기 때문에, 그 파라미터는 계정 안의 SSM 관리 인스턴스 전부가 읽을 수
있다. 남겨 두면 노출 범위가 workbench 하나가 아니라 계정 전체가 된다. 이건 관리형
정책의 성질이라 우리가 좁힐 수 없다.

#### 복구 절차

repository Secret이 사라지면 모든 sync가 멈춘다. 이때는 위 파라미터도 이미 지워져 있고
노트북의 `.pem`도 영구 보관물이 아니다. 그래서 키를 다시 발급하는 것으로 복구한다.

1. GitHub App 설정에서 새 private key를 발급하고 옛 키를 삭제한다(App당 여러 키를
   가질 수 있어 발급과 삭제를 분리해도 무방하다)
2. 위 절차 1~3을 그대로 다시 실행한다
3. GitOps 저장소의 `bootstrap/argocd-seed.sh --from 2 --to 2`로 2단계만 재적용한다

🔑 **키를 보관해서 복구하는 게 아니라 재발급으로 복구한다.** 그래서 3단계의 즉시 삭제가
복구 가능성을 해치지 않는다. 장기 자격증명을 계정에 남기지 않는 쪽이 항상 더 안전하다.

#### 기각한 대안

| 안 | 기각 사유 |
|---|---|
| SSM 세션에 키를 직접 붙여넣기 | 리소스는 추가로 안 들지만, 세션 로깅이 켜진 계정에서는 키 전체가 로그에 남는다. 감사 요건으로 세션 로깅을 켜 두는 경우가 흔해서 재사용 가능한 절차로 채택할 수 없다 |
| `aws ssm send-command` | 명령 파라미터가 평문으로 command 히스토리와 CloudTrail에 남는다. 붙여넣기보다 나쁘다 |
| Secrets Manager (workbench가 직접 조회) | 효과는 같지만 workbench Role에 `secretsmanager:GetSecretValue`가 없어 Terraform 변경이 필요하고, 시크릿당 매달 비용이 붙는다. 같은 값을 더 비싸게 사는 셈이다 |
| External Secrets Operator | 컨트롤러와 IAM Role을 새로 두고 ArgoCD 밖의 예외를 하나 더 만드는 비용이, 재구축 빈도에 비해 과하다. ESO가 관리할 다른 시크릿이 생기면 재검토한다 |

### GITOPS_REPO_DIR: private 저장소를 workbench로 clone하기

`argocd-seed.sh`는 `GITOPS_REPO_DIR`로 로컬 clone 경로를 받는데, workbench에는 `gh` CLI도
git credential helper도 없다(SSM Session Manager 전용 인스턴스이기 때문이다). 위 「GitHub App
만들기」로 받은 PEM으로 installation access token을 직접 발급해 clone한다.

```bash
# ── workbench 안에서 실행. 위 절차로 받은 ~/gh-app.pem을 쓴다 ──────────
GH_APP_ID=<app_id>
GH_APP_INSTALLATION_ID=<installation_id>
GH_APP_PRIVATE_KEY=~/gh-app.pem

b64url() { openssl base64 -A | tr -d '=' | tr '/+' '_-'; }

now=$(date +%s)
header='{"alg":"RS256","typ":"JWT"}'
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now-60))" "$((now+540))" "$GH_APP_ID")
#  iat는 60초 과거로 잡는다. workbench 시계가 GitHub 서버보다 조금이라도 앞서면
#  토큰이 즉시 거부된다. exp는 10분 이내로 잡는다. GitHub App JWT의 최대 유효 시간이다.

signed=$(printf '%s.%s' "$(printf '%s' "$header"  | b64url)" \
                         "$(printf '%s' "$payload" | b64url)")
sig=$(printf '%s' "$signed" | openssl dgst -sha256 -sign "$GH_APP_PRIVATE_KEY" | b64url)
JWT="$signed.$sig"

TOKEN=$(curl -sf -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$GH_APP_INSTALLATION_ID/access_tokens" \
  | jq -r .token)
#  installation access token은 1시간 뒤 만료된다. clone 한 번 쓰고 버리는 값이다.

git clone "https://x-access-token:${TOKEN}@github.com/<org>/<gitops-repo>.git" "$GITOPS_REPO_DIR"

# ── clone 직후. remote URL에서 토큰을 지운다 ────────────────────────────
git -C "$GITOPS_REPO_DIR" remote set-url origin \
  "https://github.com/<org>/<gitops-repo>.git"
#  argocd-seed.sh는 로컬 파일만 읽고 push하지 않으므로 clone 이후 인증이 필요 없다.
#  토큰을 .git/config에 남겨 두면 만료 전까지 workbench 디스크에 자격증명이 남는다.
```

필요 도구: `openssl`, `jq`, `curl`(workbench 기본 이미지에 이미 있다).

---

## `teardown-verify.sh`

철수(destroy) 뒤에 실제로 아무것도 남지 않았는지 확인하는 읽기 전용 스크립트다. 아무것도
지우지 않는다. 삭제는 사람이 `tofu destroy`로 한다.

```bash
WORKLOAD=demo ENVIRONMENT=hub AWS_PROFILE=team ./scripts/teardown-verify.sh
```

비용이 계속 나는 자원(NAT Gateway, EC2, EBS, Elastic IP, 로드밸런서, EKS 컨트롤 플레인)부터
검사하고, 이어서 삭제를 막는 자원(ENI, VPC), 마지막으로 보존 요건을 확인해야 하는 자원
(CloudWatch 로그 그룹)을 본다. 대상 계정이 공용일 수 있으므로 모든 조회를 `WORKLOAD`/
`ENVIRONMENT` 태그로 좁힌다. 태그가 없는 자원은 이 스크립트가 찾지 못하므로, 콘솔에서
VPC 기준으로 한 번 더 확인하는 것이 안전하다.

종료 코드: `0` = 잔존물 없음, `1` = 잔존물 있음, `2` = 실행 불가.

## 열린 항목: `.sh` 파일의 문법을 아무도 검사하지 않는다

`scripts/validate-comment-conventions.py`가 `bootstrap/*.sh`·`scripts/*.sh`·
`.claude/skills/**/*.sh`의 주석 규칙을 보지만 셸 문법은 보지 않는다. CI
(`.github/workflows/deploy-*.yml`)도 각 배포 루트의 Terraform만 다룬다. 지금은 사람이
`bash -n`을 돌리는 것이 유일한 방어다. 배포 워크플로 중 하나에 `bash -n scripts/*.sh`
(가능하면 `shellcheck`) 스텝을 추가하는 것을 검토할 만하다.
