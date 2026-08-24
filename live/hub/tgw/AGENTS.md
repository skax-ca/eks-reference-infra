<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-08-24 | Updated: 2026-08-24 -->

# live/hub/tgw

## 목적

Transit Gateway·RAM 공유·prefix list 배포 루트. `live/hub/networking`에서 2026-08-24에
분리됐다 — TGW가 networking과 같은 apply에서 새로 생기면 spoke 자동 발견 로직의 for_each가
"TGW ID가 plan 시점에 unknown"이라 실패하기 때문이다(분리 근거는 `main.tf` 상단 주석).

## 주요 파일

| 파일 | 설명 |
|------|------|
| `backend.tf` | `terraform { backend "s3" {} }` 만 — 버킷명은 init 시 주입됨 |
| `main.tf` | TGW·RAM 공유·principal association·prefix list |
| `outputs.tf` | `transit_gateway_id`·`transit_gateway_route_table_id`·`tgw_resource_share_arn` |
| `providers.tf` | AWS provider 블록 — `live/hub/networking`과 동일 패턴 |
| `variables.tf` | 입력 계약 — `live/hub/networking`과 동일 |
| `versions.tf` | OpenTofu + provider 버전 제약 |

## 의존성

### 내부

`live/hub/networking`이 이 TGW를 **data source로 조회**한다(remote state 참조 아님 —
`data "aws_ec2_transit_gateway"` 태그 필터). 배포 순서는 이 root가 먼저다 — `README.md`
「1」 참조.

### 외부

없음 — VPC·EKS 어느 것도 필요 없다(hub 자신의 attachment만 예외적으로 `live/hub/networking`에
남아 있다, VPC가 있어야 만들 수 있어서).

## 제약사항

| 제약 | 메커니즘 |
|------|---------|
| 거버넌스 태그 | 100% 루트의 `default_tags`에서 자동 부착 |
| `ignore_tags` | `cz-*` 접두사 + `CreationTime` + `Creator` 무시 |

<!-- MANUAL: -->
