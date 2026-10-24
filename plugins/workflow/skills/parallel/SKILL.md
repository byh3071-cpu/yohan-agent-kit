---
name: parallel
description: Use PROACTIVELY when the user wants parallel/동시 작업, OR when the repo being worked on is already occupied by another session (메인 트리 dirty·untracked 多·다른 worktree 존재) — git worktree 로 별도 작업방을 자동 격리해 충돌 0 으로 만든다. 사용자는 worktree 를 전혀 몰라도 된다(Claude 가 만들고·쓰고·치운다). Triggers - "병렬로 작업", "동시에 여러개", "딴것도 같이", "빠르게 같이 하자", "다른 거 작업 중인데 이것도", + 작업 레포가 다른 세션 점유된 낌새 감지 시.
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

# parallel (병렬 작업 자동 격리)

여러 작업을 충돌 없이 병렬로. **사용자가 worktree를 몰라도** Claude가 별도 작업방(git worktree)을 자동으로 만들고·쓰고·치운다. "같은 폴더에서 동시 작업 → 충돌·rebase 지옥"을 원천 제거.

## 핵심 원리
- **worktree = 같은 레포(.git 공유) + 작업 폴더만 별도.** 세션마다 다른 폴더 → 충돌 0.
- **메인 트리는 절대 안 건드림** — 다른 세션 작업 보호. 항상 새 worktree에서.
- **쓰고 치운다** — 작업·머지가 끝나면 worktree 제거(안 그러면 폴더가 쌓임).

## 발동 (능동형)
- **능동 발동:** ① 사용자가 병렬·동시 작업 의도("병렬로", "동시에", "딴것도 같이", "빠르게 같이") ② 또는 작업하려는 레포가 **이미 점유**된 낌새(메인 트리 dirty·untracked 多·다른 worktree 존재) → 명시 요청 없어도 worktree 격리를 먼저 잡는다.
- **무확인 기본:** worktree 생성은 새 폴더 추가라 위험 0 → 바로 격리하고 "별도 작업방에서 할게" 알린다. **단 정리(삭제)는 작업 완료 확인 후.**
- **발동 금지:** 단일 작업이고 레포가 깨끗하면 그냥 메인 트리에서 — worktree 불필요.

## 절차 (todo로)
1. **점유 확인 (종합 신호):** `git -C <repo> status --short`(dirty·untracked 多?) + `git -C <repo> worktree list`(다른 worktree?) + 현재 브랜치가 main/master 아님(다른 세션이 feature 작업 중 신호) → 종합 판단. ★ 애매하면 격리하는 쪽이 안전(worktree 비용은 낮고, 충돌 비용은 큼).
2. **worktree 생성:**
   - VHK 레포(`vhk` 존재): `node dist/index.js worktree add <브랜치>` — 필수 env 자동 복사.
   - 일반 레포: `git -C <repo> worktree add "<repo경로>-<브랜치>" -b <브랜치> origin/main` (origin/main 기준 = 최신 base).
3. **그 worktree 폴더에서만 작업.** 메인 트리·다른 세션 파일은 손대지 않는다.
4. **완료 → 내보내기:** PR/머지(또는 `/release-gate`)로 변경을 main에 반영.
5. **정리(필수):** `git worktree remove <경로>` → 실패 시(node_modules 점유) `powershell -Command "Remove-Item -LiteralPath '<경로>' -Recurse -Force"` → `git worktree prune` + 머지된 로컬/원격 브랜치 삭제.

## 주의 (실측 함정 — 다 겪음)
- **stacked PR 함정:** worktree base가 옛 커밋이면 **다른 세션 작업이 딸려와 PR이 삼킨다** → `git rebase --onto origin/main <old-base-commit>`로 내 커밋만 분리.
- **force push는 PR의 CI(Actions)를 안 깨운다** → required 체크가 안 붙어 머지 막힘. 해결 = **새 브랜치로 새 PR**(opened 이벤트면 CI 정상). rebase 후엔 이 패턴.
- **README 등 인덱스 충돌**(동시 세션이 같은 goal/목록 건드림)은 **재생성으로 해결**(예: `gen-goals-index.mjs`) 후 `rebase --continue`.
- **`rm -rf`가 막히면** PowerShell `Remove-Item -Recurse -Force` 사용(이 환경 권한).
- **정리 안 하면 디렉토리 누적** — 작업 끝나면 반드시 remove + prune.

## 멀티PC
이 스킬은 플러그인으로 양쪽 PC 동기화됨 — 어느 PC서든 "병렬로 해줘"면 동일 작동.
