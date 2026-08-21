# 클로드 코드 셋업 핸드오프 지시서

> **사용법:** 새 머신/세션에서 클로드 코드를 열고 "이 파일대로 순서대로 실행해줘. 단 Notion 토큰 입력과 GitHub 토큰 폐기는 내가 직접 한다"고 시키면 된다.

## 미션
요한 AI 1인기업 자동화 시스템(yohan-core 플러그인 + 멀티머신 0세팅 동기화)을 각 머신에 배포·검증하고, 레포 보안 예외를 처리한다. 순서대로 실행하되 **토큰 입력·GitHub 토큰 폐기는 사용자가 직접** 한다.

## 환경 전제 (반드시 준수)
| 항목 | 값 |
|---|---|
| OS·셸 | **Windows PowerShell** (bash 금지) |
| GitHub 계정 | byh3071-cpu |
| dev 루트 | `C:\Users\Public\dev` |
| 비밀값 | **DPAPI 머신 귀속 — AI/채팅 거치지 말 것** |
| 마켓플레이스 소스 | byh3071-cpu/yohan-agent-kit (Marketplace namespace는 첫 호환 릴리스까지 yohan-cc-skills) |

## 이미 완료 (재실행·중복 커밋 금지)
| 커밋 | 내용 |
|---|---|
| `cc4ff5f` (yohan-cc-skills/main) | yohan-core 플러그인 22파일 |
| `89dace6` (boot-auto-pull-setup/main) | Setup-Machine.ps1 · Sync-ClaudeSettings.ps1 · repos.json 정정 |

## 실행 순서

### STEP 0 — 선행 확인
```powershell
Test-Path C:\Users\Public\dev\yohan-ecosystem\yohan-cc-skills
Test-Path C:\Users\Public\dev\automation\boot-auto-pull-setup
```
둘 다 `True` → STEP 1. 하나라도 `False` → boot-auto-pull-setup의 `Setup-HomePC.ps1` 먼저.

### STEP 1 — 머신 세팅 (머신당 1회)
```powershell
cd C:\Users\Public\dev\automation\boot-auto-pull-setup
git pull
powershell -ExecutionPolicy Bypass -File .\Setup-Machine.ps1
```
> ⚠️ **토큰 입력창이 뜨면 사용자가 직접 타이핑.** 클로드 코드는 NOTION_TOKEN 값을 묻거나 대신 입력하지 말 것. (EXECUTION LOG db id는 선택 — 엔터 스킵 가능.)

### STEP 2 — 마켓 등록 + 검증
```text
claude plugin marketplace add byh3071-cpu/yohan-agent-kit
/plugin marketplace update
/flow "test: README 오타 하나 고쳐보기"
```
검증: `~/.claude/settings.json` 생성 / `/flow` explorer→planner→critic→shipper 흐름 / `git push` 시 critic-gate ask.

### STEP 3 — 레포 보안 예외 (아래 프롬프트, 해당 레포에서만)

**③ changeopradar — PAT 제거**
```text
이 레포의 git 리모트 URL에 PAT 토큰이 박혀 있어. 안전하게 제거해줘.
1) git remote -v 로 origin 확인
2) URL에 토큰이 있으면: git remote set-url origin https://github.com/byh3071-cpu/changeopradar.git
3) git config --list 에 토큰 흔적(ghp_ / github_pat_) 있는지 확인 후 제거
4) git log -p 에서 토큰이 과거 커밋에 올라간 적 있는지 grep 점검 — 있으면 보고만 하고 멈춰
끝나면 어떤 토큰을 폐기해야 하는지 알려줘.
```
→ 이후 사용자가 GitHub → Settings → Developer settings → Personal access tokens 에서 Revoke.

**④ challengs-os — .env 보호**
```text
이 레포의 .env 가 git 추적 밖에서 노출 위험이 있어. 보호해줘.
1) git ls-files 로 .env 추적 여부 확인
2) .gitignore 에 .env, .env.* 추가(없으면 생성)
3) 이미 추적 중이면 git rm --cached .env (파일 보존)
4) 값 지운 .env.example 생성
5) 과거 커밋에 .env 올라갔으면 보고만 하고 멈춰
```

**⑤ yohan-brain — 공통 메모리 (선택)**
```text
이 레포를 요한 공통 메모리 소스로 삼을 거야. ./CLAUDE.md 를 만들어서
요한의 작업 원칙(반말·두괄식·교차검증·비용 라우팅 Haiku/Sonnet/Opus)을 요약하고,
yohan-core 플러그인의 CLAUDE.md 와 중복되지 않게 이 레포 고유 지식만 담아줘.
```

### STEP 4 — 일상·유지보수
- 일상: `/flow "작업"` → critic 통과 → push
- 수정: yohan-core 고쳐 push → 각 머신 `/plugin marketplace update`
- 새 머신/레포: 머신은 STEP 0~2 1회, 레포는 자동 상속(할 일 없음)

## 절대 규칙 (가드레일)
- 토큰·비밀값을 채팅으로 입력받지 말 것 (DPAPI Read-Host로 사용자 직접).
- `git push` 전 critic 검증 통과 필수.
- `.env` · `secrets/**` · `*.pem` · `*.key` 읽지 말 것.
- "이미 완료" 커밋 재실행·중복 커밋 금지.
- Windows PowerShell 기준. bash 문법 금지.

## 깊은 맥락 (Notion — 사람이 참고)
- **클로드 코드 도입 설계도** — 도입 근거·아키텍처·전체 설계
- **yohan-core 플러그인 골격** — 실제 플러그인 파일 초안

---
_이 파일은 Notion 핸드오프 지시서와 동기화됨._
