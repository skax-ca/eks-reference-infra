# EKS 마이너 업그레이드 되돌리기

**읽는 사람**: 올린 Kubernetes 마이너를 이전 버전으로 되돌릴지 정하거나 되돌리는 사람.

올리는 절차와 단계 이름(apply 1·apply 2·보류)은 [`upgrade.md`](upgrade.md)가 갖는다.

> **검증 상태**: ⏳ 표시가 붙은 줄은 실환경에서 확인하지 않았다.

---

⏳ 이 절은 실환경에서 확인하지 않았다.

| 조건 | 내용 |
|------|------|
| 기한 | 업그레이드 완료 뒤 7일 |
| 범위 | 한 마이너. `1.35 → 1.36 → 1.37`로 올렸으면 `1.36`까지만 돌아간다 |
| 되돌려지는 것 | 컨트롤플레인 |
| 되돌려지지 않는 것 | EKS 관리형 addon 버전, 관리형 노드그룹, etcd 데이터, 워크로드 |
| 되돌릴 수 없는 경우 | 그 버전으로 생성한 클러스터, 7일 경과, 그 뒤 다시 올린 클러스터 |

올린 순서의 역순으로 내린다. Karpenter의 drift 보류를 풀기 전이면 아래 넷이 전부다.

| 순서 | 무엇을 | 방법 |
|------|--------|------|
| 1 | 준비 상태를 읽는다 | 아래 명령. `ERROR`·`UNKNOWN`이 있으면 고친다 |
| 2 | cluster-autoscaler | 그 티어의 이미지 태그를 올린 커밋을 revert한다 |
| 3 | system 노드그룹 | apply 2의 커밋을 revert한다 |
| 4 | 컨트롤플레인 | apply 1의 커밋을 revert한다 |

```bash
aws eks list-insights --cluster-name <cluster> --filter '{"categories":["ROLLBACK_READINESS"]}' \
  --query 'insights[].[insightStatus.status,name]' --output table
```

- ⚠️ 보류 중에 새로 뜬 Karpenter 노드는 새 마이너다. kubelet version skew insight가 `ERROR`로 뜨면
  `kubectl delete nodeclaim <name>`으로 그 노드를 비우고 지운다. 컨트롤플레인이 내려간 뒤 Karpenter가
  옛 마이너로 다시 띄운다.
- ⚠️ 보류를 이미 풀었다면 Karpenter 노드 전부가 여기에 해당한다. 워크로드가 전부 옮겨진다.
- ⚠️ apply 3까지 갔다면 옛 마이너의 호환 목록에 없는 addon을 먼저 내린다. `kube-proxy`가 해당한다.
- ⛔ revert한 plan에 클러스터나 노드그룹이 `must be replaced`로 뜨면 승인하지 않는다. provider 코드는
  버전 하향을 교체로 다루지 않지만 ⏳ plan으로 확인하지 않았다.
