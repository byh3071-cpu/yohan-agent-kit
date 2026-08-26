---
name: youtube-summary
description: YouTube를 Focus Feed knowledge_jobs → NotebookLM 근거 → yohan-brain 검토 후보로 지식화할 때. "지식 대기열 처리해줘", "영상 브레인에 넣어줘", "유튜브 지식화", "이 영상 정리해줘", "영상 넣어줘", "영상 요약 승인" 트리거. 옛 yt-dlp→wiki/트리플 원샷 경로는 쓰지 않는다.
---

# youtube-summary — YouTube → 검토 후보 (얇은 진입점)

> 상세 계약은 **yohan-brain이 SoT**. 이 파일은 실행 순서만 담는다.
> 정본: `docs/specs/knowledge-capture-workflow-v0.md` · `memory/decisions/2026-07-27-focus-feed-knowledge-capture-p0.md` · `docs/specs/KNOWLEDGE-WORKFLOW-P0-AGENT-PLAN.md`

## 원칙

- 대기열 정본 = Focus Feed `knowledge_jobs`. 원문 도구 = NotebookLM D0 Inbox. 지식 정본 = 사람 승인 뒤 `memory/ingest/` RESOURCE·SUMMARY.
- 기본은 dry-run. `--execute`와 승인은 요한이 **처리/실행/승인**을 말했을 때만.
- P0 승인은 RESOURCE·SUMMARY만. wiki·트리플·역전파·Notion 자동 쓰기 금지.
- 자막 전문·쿠키·키를 Git·Notion·PR·세션 로그에 넣지 않는다.

## 먼저 확인

1. URL이면 YouTube watch URL로 정규화한다. 지식화가 아직이면 Focus Feed **지식화** 버튼 또는 `/capture`로 대기열에 넣으라고 안내한다. NotebookLM에 직접 올리지 않는다.
2. UI를 못 쓰면 아래만 만들어 붙여넣게 한다.

```text
채널: {채널명 또는 확인 필요}
제목: {영상 제목 또는 확인 필요}
URL: {표준 YouTube URL}
소스 가이드:
- {설명란의 핵심 문맥}
- {유의미한 타임라인·공식 링크}
```

3. 명령은 **yohan-brain 루트**에서 돌린다. cwd가 아니면 절대경로로 찾는다(`…/yohan-ecosystem/yohan-brain`). 못 찾으면 요한에게 묻는다.
4. `package.json`에 `knowledge:pickup` / `knowledge:approve`가 없으면 이 checkout은 계약 미탑재다. 추측 요약·yt-dlp로 우회하지 말고 멈춘다.

## 처리

### 1. 상태 확인 (외부 쓰기 없음)

```text
npm run knowledge:pickup -- --limit 1
```

대기열·NotebookLM·환경 변수 중 뭐가 준비됐고 뭐가 막혔는지 짧게 보고한다. 키 없음·인증 실패면 멈춘다. 값은 출력하지 않는다.

### 2. 후보 생성 (요한이 처리/실행을 명시한 때만)

```text
npm run knowledge:pickup -- --execute --limit 1
```

- `--limit`은 1|2|3만. 한 세션 최대 3건.
- 공개 자막·타임스탬프·품질 게이트 실패는 `action_required`. 제목·URL만으로 내용을 만들지 않는다.
- 성공하면 `memory/inbox/knowledge-review/` 경로와 품질 점수·불확실성만 보여 준다.

### 3. 승인 (요한이 승인한다고 명시한 때만)

```text
npm run knowledge:approve -- --job {uuid} --approve
```

`--stdin`은 ADR-017이 Accepted가 아니면 쓰지 않는다. 완료 뒤 RESOURCE·SUMMARY 경로만 보고한다. wiki·허브·Git·Notion을 이 단계에서 고치지 않는다.

## 금지

- yt-dlp 자동 실행·설치. 개인 로컬 캐시 예외는 요한이 **한 번** 명시한 뒤에만, 전문 영구 저장 없이.
- NotebookLM 실패를 다른 추출기로 조용히 우회.
- 커밋·MCP 재인증·Supabase migration·키 교체. 각각 사람 게이트.
- 운영 canary 실패 row를 되돌리거나 품질 기준을 낮추기.

## 짧은 보고

```text
상태: 캡처됨 | 검토 후보 생성 | 보류 | 승인 완료
근거: 자막·타임스탬프 충족 여부 / 품질 점수
다음: 검토 | 보류 사유 해결 | 승인
```
