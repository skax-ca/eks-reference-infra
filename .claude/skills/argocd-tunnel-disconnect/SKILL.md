---
name: argocd-tunnel-disconnect
description: argocd-tunnel-connect로 연 hub ArgoCD 콘솔 터널(로컬 SSM 세션 + workbench의 kubectl port-forward watchdog)을 전부 정리한다. 사용자가 "argocd 터널 해제", "argocd 연결 끊어줘", "터널 정리해줘"라고 할 때 사용한다. argocd-tunnel-connect와 짝을 이루는 스킬이다.
---

# ArgoCD Tunnel Disconnect

`argocd-tunnel-connect`가 연 2단 SSM 터널(로컬 watchdog + 원격 kubectl port-forward
watchdog)을 양쪽 다 종료하고 상태 파일을 지운다.

## 실행

```bash
bash .claude/skills/argocd-tunnel-disconnect/scripts/disconnect.sh
```

인자 없음 — 짝 스킬 `argocd-tunnel-connect` 디렉토리 밑 `.state/`의 상태 파일에서 무엇을
종료해야 하는지 전부 읽는다(전용 상태 폴더를 쓰는 이유는 `argocd-tunnel-connect`의
`connect.sh` 주석 참고).

## 출력

| 출력 | 의미 |
|---|---|
| `NOT_CONNECTED (...)` | 연결 상태가 아니다(이미 해제됐거나 애초에 이 스킬 쌍으로 연 적 없음) — 정상 종료 |
| `DISCONNECTED port=N instance=i-...` | 로컬·원격 프로세스 정리 완료, 상태 파일 삭제 완료 |
| `WARNING: ...`(stderr) | 원격 정리 명령이 실패했거나(인스턴스가 이미 종료됨) 로컬 포트가 여전히 응답함 — 수동 확인 필요 |

## 정리 대상 (양쪽 다)

1. **로컬**: watchdog 프로세스(자식인 `aws ssm start-session` 포함)를 죽인다. 혹시 고아로
   남은 세션이 있으면 포트 번호로 한 번 더 정리한다.
2. **원격**: workbench에 `pkill -f "kubectl port-forward -n argocd svc/argocd-server"`를
   보낸다 — 이 패턴 하나로 실제 `kubectl` 프로세스와 그걸 감싼 `while` 루프 watchdog
   bash 프로세스가 **함께 잡힌다**(watchdog의 스크립트 문자열 자체가 그 패턴을 포함하기
   때문에 별도 마커가 필요 없다). watchdog까지 죽어야 재시작되지 않는다.

## 언제 쓰는가

- ArgoCD 콘솔 확인 작업이 끝났을 때 — 터널을 열어둔 채로 세션을 끝내면 workbench에서
  불필요한 프로세스가 계속 돈다.
- `argocd-tunnel-connect`를 다른 포트로 다시 열기 전에 정리가 필요할 때.

`argocd-tunnel-connect`가 멱등적이라 재연결 전에 항상 disconnect를 먼저 부를 필요는
없다 — 이미 정상 연결돼 있으면 connect가 알아서 아무것도 안 한다. disconnect는
**정말로 닫고 싶을 때만** 쓴다.
