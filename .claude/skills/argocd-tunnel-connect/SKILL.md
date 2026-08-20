---
name: argocd-tunnel-connect
description: hub ArgoCD 콘솔(https://localhost:8080)에 접속하기 위한 2단 SSM 터널을 연다 — 로컬 SSM 세션 → hub workbench → kubectl port-forward → argocd-server. 사용자가 "argocd 터널 연결", "argocd 콘솔 접속", "argocd UI 보고 싶다"고 할 때 사용한다. 멱등적이다 — 이미 정상 연결돼 있으면 아무것도 하지 않는다.
---

# ArgoCD Tunnel Connect

`iac-reference-infra`의 hub workbench(private EKS 클러스터의 유일한 접근 지점)를 거쳐
hub ArgoCD 콘솔을 로컬 브라우저에서 열 수 있게 하는 2단 터널을 연다.

```
로컬 브라우저 → https://localhost:<PORT>
             → (aws ssm start-session, AWS-StartPortForwardingSession)
             → hub workbench(EC2, private subnet)
             → (kubectl port-forward -n argocd svc/argocd-server)
             → hub EKS 클러스터의 argocd-server 파드
```

이 터널은 **읽기 접근 경로일 뿐**이다 — 여는 행위 자체는 인프라를 바꾸지 않는다. 다만
콘솔에서 하는 조작(초기 비밀번호 교체 등)은 별개로 신중히 다룬다.

## 실행

```bash
bash .claude/skills/argocd-tunnel-connect/scripts/connect.sh [LOCAL_PORT]
```

`LOCAL_PORT` 생략 시 `8080`. 출력의 마지막 줄로 결과를 판단한다:

| 출력 | 의미 |
|---|---|
| `ALREADY_CONNECTED port=N pid=N` | 이미 같은 포트로 정상 연결돼 있다 — 멱등, 아무것도 안 함 |
| `CONNECTED port=N instance=i-... pid=N` | 새로 연결하고 헬스체크(HTTP 200)까지 확인 |
| `CONNECTED_UNVERIFIED ...` | 터널은 열었지만 아직 응답 확인 전 — 몇 초 후 다시 curl 해볼 것 |
| `ERROR: ...` (stderr, exit 1) | workbench를 못 찾았거나 SSM 오프라인이거나 원격 명령 실패 |

성공하면 사용자에게 `https://localhost:<PORT>`를 안내한다(자체 서명 인증서 경고는 정상).

## 멱등성 판단 방식

스크립트가 매번 다음을 확인한다:
1. `.omc/state/argocd-tunnel/local-watchdog.pid`에 기록된 프로세스가 살아있는가
2. `https://localhost:<PORT>/`가 실제로 HTTP 200을 주는가(터널 전 구간이 살아있어야 통과)

둘 다 참이면 **재연결하지 않는다.** 하나라도 거짓이면(프로세스가 죽었거나, 로컬 SSM 세션은
살아있는데 원격 kubectl port-forward만 끊긴 경우 등) 잔여 프로세스를 정리하고 새로 연다.

## 재연결(watchdog) 2겹

- **원격**: workbench에서 `kubectl port-forward`를 `while true` 루프로 감싸 실행한다.
  argocd-server 파드 재시작 등으로 연결이 끊기면 2초 후 자동 재시도한다
  (이전 세션에서 `lost connection to pod`로 실제로 끊긴 전례가 있었다).
- **로컬**: `aws ssm start-session`도 같은 방식으로 감싼다. VPN·네트워크 전환 등으로
  세션이 끊기면 3초 후 자동 재연결한다.

두 watchdog은 서로 독립이다 — 한쪽만 끊겨도 그쪽만 재시작되고 다른 쪽은 영향받지 않는다.

## 상태 파일

`.omc/state/argocd-tunnel/`(이 프로젝트 OMC 상태 루트, git에 커밋되지 않는다):
`local-watchdog.pid` · `instance-id.txt` · `local-port.txt` · `local-watchdog.log`.
`argocd-tunnel-disconnect` 스킬이 이 파일들로 무엇을 정리해야 하는지 찾는다 — 직접 지우지 않는다.

## 전제

- `aws --profile team`이 hub 계정에 인증돼 있어야 한다(`CLAUDE.md` 4-1절).
- hub workbench(`ec2-demo-hub-an2-workbench-*`)가 실행 중이고 SSM Online 상태여야 한다.
  인스턴스 ID는 태그로 **매번 동적 탐색**한다 — 재부트스트랩되면 ID가 바뀌기 때문에
  하드코딩하지 않는다.
