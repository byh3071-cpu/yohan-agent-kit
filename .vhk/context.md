# 프로젝트 컨텍스트

> 이 파일은 `vhk context`로 자동 생성되었습니다.
> AI 어시스턴트에게 프로젝트 맥락을 제공합니다.

## 원본 지도 (Source of Truth)

> 같은 사실은 원본 한 곳에서만 고치세요. 스냅샷은 원본을 읽어 다시 만듭니다.

- **규칙(원본)**: `RULES.md` — 규칙은 여기 한 곳에서만 수정
- **작업 정의·수용 기준**: `RULES.md`나 프로젝트 문서가 지정한 추적 원본 — 경로를 추측하지 않음
- **로컬 Goal 실행 상태**: `goals/*.md` frontmatter — 원본에서 만든 비추적 실행 카드
- **Goal 검사 스크립트(파생)**: `scripts/check-goal-<번호>.mjs` — 직접 수정 금지, `vhk goal sync`로 재생성
- **파생 스냅샷**: `.vhk/context.md`, `docs/state/next-task.md` — 원본 아님
- **로컬 차단 기록**: `docs/state/blockers.md` — append-only, 작업 정의 원본 아님
- **버전·릴리스**: `package.json`, `CHANGELOG.md`
- **명령 목록**: `COMMANDS.md` (+ `vhk help`)
- **파생본(직접 수정 금지)**: `.cursorrules`·`.windsurfrules`·`.github/copilot-instructions.md`·`AGENTS.md`·`GEMINI.md` 등 7종 + `CLAUDE.md` 규칙 영역 → `vhk sync` 로 생성

## 기술 스택

> 기술 스택 상태: 확정

### 선언된 기술 스택 (RULES.md)

- 범용 Markdown skills · 전체 디렉터리 manifest
- Claude Code plugins
- PowerShell 5.1 hooks·설치 도구 (Windows primary)

### 실제 감지된 기술 스택 (package.json)

- (감지 결과 없음)

## 헌법(core-rules) 소스

- configured — 사용자 규칙 파일 (v0.1.5)

## 디렉토리 구조

```text
├── adapters/
│   ├── antigravity/
│   │   └── hooks.json
│   ├── claude-code/
│   │   └── hooks/
│   ├── codex/
│   │   └── hooks.json
│   └── cursor/
│       └── hooks/
├── AGENTS.md
├── CLAUDE-CODE-SETUP-HANDOFF.md
├── CLAUDE.md
├── distribution/
│   ├── asset-catalog.json
│   ├── design-toolchain.json
│   └── manifests/
│       ├── adr-cycle.json
│       ├── design-team.json
│       ├── design-to-html.json
│       ├── dump-gate.json
│       ├── goal-cycle.json
│       ├── html-doc.json
│       ├── master-orchestrator.json
│       ├── morning-merge-check.json
│       ├── notion-inbox-pickup.json
│       ├── overnight-vhk-auto.json
│       ├── planning-diagrams.json
│       ├── research-brief.json
│       ├── secret-pr-guard.json
│       ├── session-card.json
│       ├── source-command-routing-review.json
│       ├── thought-to-prompt.json
│       ├── vhk-auto.json
│       └── yohan-start.json
├── docs/
│   ├── AGENT_KIT_INTAKE.md
│   ├── AGENT_KIT_RELEASES.md
│   ├── AGENT_KIT_TWO_MACHINE_RUNBOOK.md
│   ├── analysis/
│   │   ├── 2026-06-18-work-patterns.md
│   │   ├── 2026-07-06-ecosystem-audit.md
│   │   └── 2026-07-21-plan-audit-auto-trigger.md
│   ├── ARCHITECTURE.md
│   ├── audits/
│   │   ├── agent-assets-home-2026-08-14.md
│   │   ├── design-context-contract-2026-08-14.md
│   │   ├── design-team-elicitation-hardening-2026-08-22.md
│   │   ├── design-team-session-continuity-2026-08-23.md
│   │   ├── design-team-skill-2026-08-22.md
│   │   ├── design-team-taste-workflow-2026-08-22.md
│   │   ├── design-to-html-home-drift-2026-08-14.md
│   │   ├── goal-cycle-reconciliation-2026-07-29.md
│   │   ├── multivendor-install-smoke-2026-07-30.md
│   │   └── yohan-agent-kit-identity-2026-08-14.md
│   ├── DESIGN_TO_HTML_HANDOFF.md
│   ├── log/
│   │   ├── 2026-07-02-handoff.md
│   │   ├── 2026-07-16-handoff-session-end-verify.md
│   │   ├── 2026-07-21-plan-audit.md
│   │   └── 2026-07-29-multivendor-skill-sot.md
│   ├── MULTIVENDOR_SKILL_DISTRIBUTION.md
│   ├── patterns/
│   │   ├── PAT-001-ps-statusline-encoding.md
│   │   ├── PAT-002-ps-convertto-json-hook-traps.md
│   │   ├── PAT-003-verify-inherited-premise.md
│   │   ├── PAT-004-single-source-of-truth-doctrine.md
│   │   ├── PAT-005-plugin-install-vs-enable.md
│   │   ├── PAT-006-ps-file-replace-null-backup.md
│   │   ├── PAT-007-reparse-ancestor-containment.md
│   │   └── PAT-008-resolve-git-exe-before-wrapper.md
│   ├── PRD.md
│   ├── state/
│   │   ├── blockers.md
│   │   ├── learnings.md
│   │   └── next-task.md
│   └── YOHAN_AGENT_KIT_MIGRATION.md
├── dotfiles/
│   └── claude/
│       └── settings.json
├── fixtures/
│   ├── agent-kit-session-results.example.json
│   ├── agent-kit-transaction-results.example.json
│   └── design-context-html-slice/
│       ├── app.js
│       ├── context/
│       ├── evidence/
│       ├── index.html
│       ├── README.md
│       ├── source.json
│       ├── styles.css
│       └── vendor/
├── GEMINI.md
├── goals/
│   ├── 1-multivendor-skill-sot.md
│   ├── 10-claude-auto-session-title.md
│   ├── 11-design-team.md
│   ├── 12-design-team-taste-workflow.md
│   ├── 13-design-team-elicitation-hardening.md
│   ├── 14-design-team-session-continuity.md
│   ├── 15-session-operations-skills.md
│   ├── 2-design-to-html-multivendor.md
│   ├── 3-design-context-html-slice.md
│   ├── 4-agent-asset-registry.md
│   ├── 5-yohan-agent-kit-identity.md
│   ├── 6-versioned-release-store.md
│   ├── 7-knowledge-intake.md
│   ├── 8-two-machine-four-vendor-validation.md
│   ├── 9-vendor-payload-chain-attestation.md
│   └── _meta.md
├── plugins/
│   ├── critical-thinking/
│   │   ├── agents/
│   │   ├── AGENTS.md
│   │   ├── commands/
│   │   ├── GEMINI.md
│   │   ├── hooks/
│   │   └── skills/
│   ├── statusline/
│   │   └── skills/
│   ├── workflow/
│   │   └── skills/
│   └── yohan-core/
│       ├── agents/
│       ├── CLAUDE.md
│       ├── commands/
│       ├── hooks/
│       ├── output-styles/
│       ├── references/
│       └── skills/
├── README.md
├── registry/
│   ├── assets.yaml
│   ├── release-bundles.json
│   └── vendor-smoke-probes.json
├── RULES.md
├── scripts/
│   ├── agent-kit-hook.mjs
│   ├── antigravity-adapter.mjs
│   ├── Build-AgentKit.mjs
│   ├── Build-AssetCatalog.mjs
│   ├── check-goal-1.mjs
│   ├── check-goal-10.mjs
│   ├── check-goal-11.mjs
│   ├── check-goal-12.mjs
│   ├── check-goal-13.mjs
│   ├── check-goal-14.mjs
│   ├── check-goal-2.mjs
│   ├── check-goal-3.mjs
│   ├── check-goal-4.mjs
│   ├── check-goal-5.mjs
│   ├── check-goal-6.mjs
│   ├── check-goal-7.mjs
│   ├── check-goal-8.mjs
│   ├── Get-AgentAssetDrift.ps1
│   ├── Invoke-VendorSmoke.ps1
│   ├── Manage-AgentIntake.ps1
│   ├── Manage-AgentKit.ps1
│   ├── Manage-MultivendorSkills.ps1
│   ├── Manage-ProductDesignContext.ps1
│   ├── New-SkillManifest.ps1
│   ├── Record-DesignDecision.ps1
│   ├── Resolve-DesignContext.ps1
│   ├── Restore-ExternalSkills.ps1
│   ├── Scan-AgentAssets.ps1
│   ├── Test-AgentKitCompatibility.ps1
│   ├── Test-DesignToHtmlEnvironment.ps1
│   ├── Test-SessionEndTimeout.ps1
│   ├── verify-design-context-html.mjs
│   └── windows-powershell-env.mjs
├── skills/
│   ├── adr-cycle/
│   │   ├── agents/
│   │   ├── references/
│   │   └── SKILL.md
│   ├── design-team/
│   │   ├── agents/
│   │   ├── references/
│   │   └── SKILL.md
│   ├── design-to-html/
│   │   ├── agents/
│   │   ├── references/
│   │   └── SKILL.md
│   ├── dump-gate/
│   │   └── SKILL.md
│   ├── goal-cycle/
│   │   ├── agents/
│   │   ├── reference.md
│   │   └── SKILL.md
│   ├── html-doc/
│   │   ├── assets/
│   │   └── SKILL.md
│   ├── master-orchestrator/
│   │   └── SKILL.md
│   ├── morning-merge-check/
│   │   └── SKILL.md
│   ├── notion-inbox-pickup/
│   │   └── SKILL.md
│   ├── overnight-vhk-auto/
│   │   └── SKILL.md
│   ├── planning-diagrams/
│   │   └── SKILL.md
│   ├── research-brief/
│   │   └── SKILL.md
│   ├── restart-safe-handoff/
│   │   ├── agents/
│   │   └── SKILL.md
│   ├── runtime-incident-investigator/
│   │   ├── agents/
│   │   └── SKILL.md
│   ├── secret-pr-guard/
│   │   └── SKILL.md
│   ├── session-card/
│   │   └── SKILL.md
│   ├── source-command-routing-review/
│   │   └── SKILL.md
│   ├── supervised-session-conductor/
│   │   ├── agents/
│   │   └── SKILL.md
│   ├── thought-to-prompt/
│   │   └── SKILL.md
│   ├── vhk-auto/
│   │   └── SKILL.md
│   └── yohan-start/
│       └── SKILL.md
└── tests/
    ├── AgentKitCompatibility.Tests.ps1
    ├── AutoSessionTitle.Tests.ps1
    ├── Build-AgentKit.Tests.ps1
    ├── ContextHint.Tests.ps1
    ├── DesignContext.Tests.ps1
    ├── DesignToHtmlInvocation.Tests.ps1
    ├── fixtures/
    │   ├── fake-agy.ps1
    │   └── session-operations-adversarial.json
    ├── Invoke-VendorSmoke.Tests.ps1
    ├── Manage-AgentIntake.Tests.ps1
    ├── Manage-AgentKit.Tests.ps1
    ├── Manage-MultivendorSkills.Tests.ps1
    ├── Manage-ProductDesignContext.Tests.ps1
    ├── New-SkillManifest.Tests.ps1
    ├── Scan-AgentAssets.Tests.ps1
    ├── Test-DesignToHtmlEnvironment.Tests.ps1
    └── Test-SessionEndTimeout.Tests.ps1
```

## VHK CLI 명령어

- `vhk gate — 아이디어 검증`
- `vhk start — 새 프로젝트 시작 마법사`
- `vhk bootstrap — Cursor/에이전트 배선 bootstrap (cursor)`
- `vhk init — 하네스 파일 생성`
- `vhk recap — 오늘 한 일 정리 + ADR 분리`
- `vhk sync — RULES.md → 규칙 파일 동기화`
- `vhk check — RULES.md 규칙 점검`
- `vhk secure — 보안 스캔 (시크릿 유출 검사)`
- `vhk cloud — .vhk 클라우드 백업·복원 (push/pull)`
- `vhk ship — 배포 체크리스트 + 회고`
- `vhk doctor — 개발 환경 점검 (+ --strict 드리프트 게이트)`
- `vhk save — git 저장 (add → commit → push)`
- `vhk undo — 최근 커밋 되돌리기`
- `vhk restore — sync 백업 복원`
- `vhk status — 프로젝트 상태 대시보드`
- `vhk stats — 통계 대시보드 — 패스율/차단율/진화 적용율 (읽기 전용)`
- `vhk diff — Git 변경사항 한국어 요약`
- `vhk diff-cover — 이번 변경이 테스트로 커버됐는지 측정 (자문형)`
- `vhk mcp — MCP 서버 시작 (stdio)`
- `vhk mcp-init — Cursor·Claude Desktop MCP 설정 생성`
- `vhk inject-bootstrap — tier S harness (ecosystem · CORE-RULES · context · mcp.example)`
- `vhk deploy — 프로덕션 배포 (자동 감지)`
- `vhk env — .env → .env.example 동기화`
- `vhk env-check — 필수 환경변수 누락 검사`
- `vhk publish — npm 배포 (버전 범프 → 빌드 → 테스트)`
- `vhk design — 디자인 토큰 생성`
- `vhk design-palette — 컬러 팔레트 프리셋 선택`
- `vhk theme — 다크/라이트 모드 CSS 생성`
- `vhk ref — 레퍼런스 URL 관리 (add/list/open)`
- `vhk harness — 통합 품질 점검 (lint+type+test+build)`
- `vhk audit — 보안 취약점 감사 (npm audit)`
- `vhk migrate — 패키지 매니저 전환 (npm/yarn/pnpm)`
- `vhk update — VHK CLI 셀프 업데이트`
- `vhk context — 프로젝트 맥락 파일 생성 (.vhk/context.md)`
- `vhk mode — Safety Mode 조회/변경 (lite|standard|strict)`
- `vhk verify — 검증 게이트 실행 + 증거 기록`
- `vhk cost — 비용·예산 가드 — add/check/budget (자문형)`
- `vhk preflight — 출고 전 안전점검 (2FA·shim·env·lint·타입·테스트·git, 치명 시 차단)`
- `vhk testmap — test-first 매핑 점검 (변경 기능 ↔ 테스트 누락 경고)`
- `vhk worktree — worktree 가드 — 생성 시 env/설정 자동 복사·누락 점검 (add/check)`
- `vhk standup — 아침 브리핑 (어제 한 일 + 오늘 추천 goal + 미해결)`
- `vhk today — 저녁 자축·회고 (오늘 커밋·완료 goal 카운트 + 격려)`
- `vhk review — 적대적 자기검증 (거짓완료 의심 탐지)`
- `vhk receipt — 증거 영수증 — 4대 기계증거로 거짓완료 판정 (block/caution/pass)`
- `vhk mission — 미션 계약 — 작업 목표·허용/금지 범위 선언·검증`
- `vhk context-show — 컨텍스트 파일 내용 출력`
- `vhk memory — 기억 관리 v2 (decisions/failures/successes)`
- `vhk recall — 기억 회상 (자연어 키워드 검색 — RFC 0049)`
- `vhk brief — 프로젝트 요약 보고서 생성`
- `vhk loop-brief — 루프 1틱 앵커 생성 (의도+goal1+교훈+STOP)`
- `vhk remind — 치명 규칙 재주입 (RULES.md NON-NEGOTIABLE/Forbidden 압축)`
- `vhk content — 콘텐츠 초안 프롬프트 (풀사이클 뒷단 — 콘텐츠/마케팅)`
- `vhk launch — 런칭 게시물 프롬프트 (풀사이클 뒷단 — 런칭)`
- `vhk ops — 운영 회고 프롬프트 (풀사이클 뒷단 — 운영)`
- `vhk sell — 판매 카피 프롬프트 (풀사이클 뒷단 — 판매)`
- `vhk work — AI 작업 시작/이어하기 (+ handoff)`
- `vhk goal — Goal 단계별 미션 관리`
- `vhk blocker — 블로커 기록 (3건 누적 시 HARD_STOP)`
- `vhk learn — 교훈 기록 → memory v2 단일 SoT`
- `vhk win — 성공 기록 → memory successes (reinforce 입력)`
- `vhk autonomy-log — 자율 루프 런 시작/종결 기록 (완주율 계측, #373)`
- `vhk watch — 무인 세션 정지 감시 — idle 초과 시 텔레그램·콘솔 알림`
- `vhk resume — .vhk/HARD_STOP 해제 (--confirm 필요)`
- `vhk pattern — 반복 패턴 감지·목록 (avoid/reinforce)`
- `vhk evolve — 패턴 → 7일 룰 후보 표시·사람 승인·되돌리기`
- `vhk loop — 자가진화 조율 1틱 — 다음 한 수 (읽기 전용)`
- `vhk seo — SEO·수익 대시보드 (init: 사이트 등록 + 자격증명 보관)`
- `vhk config — vhk 사용자 설정 (set-rules-file: 사용자 규칙 YAML, 재시작 불필요)`

## Active Goal

- **id**: 5
- **title**: Yohan Agent Kit 정체성 전환
- **status**: IN_PROGRESS
- **priority**: P0
- **file**: goals\5-yohan-agent-kit-identity.md

## Active Blockers

- [ ] 2026-07-30 AGY CLI 1.1.8은 표준 `~/.gemini/config/skills`의 adr-cycle·goal-cycle을 새 세션에서 발견하지 못함 — 조건부 fallback 두 junction의 별도 사용자 승인 대기. Claude Code 자동·명시·부정 호출은 주간 한도 리셋(2026-08-01 15:00 Asia/Seoul) 후 검증 대기.
- [ ] 2026-07-31 위 fallback junction 승인은 집행됐으나 AGY 1.1.8 런타임이 `~/.gemini/antigravity-cli/skills`도 주입하지 않아 반증됨 — `~/.gemini/skills` 물리 생성 어댑터의 구현 PR·머지와 정확한 전역 변경 재승인 뒤 AGY 명시·자동·부정 호출을 재검증한다. 기존 두 fallback junction은 새 승인 전까지 유지한다. Claude Code 검증 대기도 유지한다.

---

_생성: 2026. 8. 23. 오후 11:19:38_
_vhk-context-git: 50c87a3fd5eeb21a20b7f9234a3438afb957e8d7_
