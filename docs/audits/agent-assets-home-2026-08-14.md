# 집 PC Agent 자산 read-only 감사 — 2026-08-14

## 결론

- `scripts/Scan-AgentAssets.ps1`은 사용자 홈을 읽기만 하고 JSON을 stdout으로 반환했다.
- 표준 탐색 위치 19개 중 16개가 존재했으며 관찰 235개를 모두 taxonomy 값으로 분류했다.
- 원시 목록은 PC 상태이므로 Git에 저장하지 않았다. 이 문서는 정제된 후보·이상 징후와 재현 명령만 보존한다.
- API key, token, 로그인 세션이 있을 수 있는 설정 파일은 이름만 `secretBoundaries`로 선언하고 내용과 hash를 읽지 않았다.

## 집계

| 분류 | 수 | 의미 |
| --- | ---: | --- |
| `UNKNOWN` | 174 | 출처·라이선스·정본이 확인되지 않아 승격 금지 |
| `DUPLICATE` | 43 | 다른 정본을 바라보는 설치 view 또는 junction |
| `PROJECT_SPECIFIC` | 2 | 소유 프로젝트에 남겨야 하는 자산의 vendor view |
| `LOCAL_ONLY` | 14 | vendor가 관리하는 plugin cache provider |
| `LEGACY` | 2 | target이 사라진 junction |

`UNKNOWN`은 누락 상태가 아니다. 근거가 부족하다는 사실을 보존하는 명시적 분류이며 lifecycle은 `candidate`를 넘지 못한다.

## 정제된 후보와 이상 징후

| 자산 | 안전한 위치 | 분류 | lifecycle | 근거 |
| --- | --- | --- | --- | --- |
| `html-doc` | `home://.claude/skills/html-doc` | `UNKNOWN` | `candidate` | physical skill, Git 출처·license 표기 없음, SKILL hash `4ce488ac...e0a45e` |
| `planning-diagrams` | `home://.cursor/skills/planning-diagrams` | `UNKNOWN` | `candidate` | physical skill, Git 출처·license 표기 없음, SKILL hash `31c5c66d...7f30c` |
| `competitive-brief` | `home://.cursor/skills/competitive-brief` | `LEGACY` | `deprecated` | target이 사라진 junction |
| `interview-me` | `home://.cursor/skills/interview-me` | `LEGACY` | `deprecated` | target이 사라진 junction |
| `yohan-instagram-cardnews` | `project://yohan-studio/skills/yohan-instagram-cardnews` | `PROJECT_SPECIFIC` | `candidate` | vendor view 두 곳이 같은 프로젝트 소유 Skill을 가리킴 |

사용자가 언급한 Superpowers HTML 자산과 `html-doc`의 동일성은 입증되지 않았다. 노트북에서 source URL, plugin version, license, hash를 다시 확인하기 전에는 같은 자산이라고 가정하지 않는다.

## 일반 Subagent 후보

다음 네 역할은 Claude Code, Cursor, Codex, Antigravity 위치에서 동일한 Markdown hash가 관찰됐다. 반복 설치 사실은 일반화 후보 근거이지만 정본 위치와 license가 아직 확정되지 않았으므로 모두 `candidate`다.

| 역할 | 동일 파일 hash |
| --- | --- |
| `merge-advisor` | `62479f16...b82a6` |
| `prompt-auditor` | `f3a86837...0b60` |
| `prompt-forge` | `a5adbc94...70d7` |
| `research-scout` | `cd2d4896...a3d5` |

승격 기준은 “여러 vendor에 복사돼 있음”이 아니라 다음 모두다.

1. 두 개 이상 프로젝트에서 역할·입력·완료 조건이 반복 검증됨
2. 프로젝트 비밀·제품 문맥·절대경로가 제거됨
3. 공통 역할 정의와 vendor adapter의 책임이 분리됨
4. provenance와 license가 확인됨
5. 사람이 `approved`를 명시함

프로젝트 전용 Subagent는 소유 프로젝트에 남고 Agent Kit에는 reference나 registry link만 둔다.

## Command와 Hook 후보

- `home://.claude/commands/goal.md`와 Cursor 변형은 공통 Skill 승격 가능성을 평가하되 vendor 실행 문법은 adapter로 분리한다.
- `home://.claude/commands/routing-review.md`는 Claude 전용 candidate다.
- `home://.claude/hooks/session-title-hook.cjs`는 공통 제목 결정 로직과 vendor 이벤트 바인딩을 분리할 candidate다.

## 보안 경계

다음 종류는 MCP endpoint나 token이 포함될 수 있어 scanner가 내용을 읽지 않는다.

- `home://.claude.json`
- `home://.claude/settings.json`
- `home://.codex/config.toml`
- `home://.cursor/mcp.json`
- `home://.gemini/settings.json`

Agent Kit Registry에는 환경변수 **이름**만 기록하며 값은 기록하지 않는다.

## 재현

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\scripts\Scan-AgentAssets.ps1 `
  -OutputFormat PrettyJson
```

이 명령은 stdout만 사용한다. 향후 Goal 7이 승인된 로컬 Inbox writer를 제공하기 전까지 script 내부 파일 쓰기는 금지한다.
