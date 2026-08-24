# live/hub/tgw

**읽는 사람**: 이 배포 루트에서 작업하거나 hub 재배포 순서를 확인하는 사람.

Transit Gateway·RAM 공유·prefix list만 배포하는 허브 루트다. `live/hub/networking`에서
2026-08-24에 분리됐다(분리 근거는 이 디렉토리 `main.tf` 상단 주석 참조).

---

## 1. 배포 순서 — 이 root가 `live/hub/networking`보다 먼저다

hub를 처음부터 세울 때(부트스트랩 이후)는 **반드시 이 순서**를 지킨다:

```
① live/hub/tgw          — 이 root (TGW·RAM 공유·prefix list)
② live/hub/networking   — VPC + hub 자신의 attachment
③ live/hub/eks          — EKS + workbench
```

⚠️ 두 워크플로(`deploy-hub-tgw.yml`·`deploy-hub-network.yml`) 사이에 GitHub Actions
`needs:`로 순서를 강제할 수 없다(별도 워크플로 파일이라) — ①의 apply가 끝난 뒤에 사람이
②를 dispatch한다. 순서를 어기면 `live/hub/networking`의 spoke 자동 발견 로직이
`Invalid for_each argument`로 실패한다(TGW가 아직 없어서).

---

## 2. 주입되는 값 — 코드에 없는 것들

`live/hub/networking`과 완전히 같은 패턴이다(그 디렉토리 README.md 「1」 참조) — state
key만 다르다(`hub/tgw.tfstate`).

---

## 3. 이 루트가 만들지 않는 것

hub 자신의 attachment(`aws_ec2_transit_gateway_vpc_attachment`)는 여기 없다 — VPC가
있어야 만들 수 있어 `live/hub/networking`에 남아 있다. spoke 자동 발견 로직도
`live/hub/networking`에 있다.
