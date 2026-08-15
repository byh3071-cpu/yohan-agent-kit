# Yohan Agent Kit 정체성 전환 감사

날짜: 2026-08-14
근거: yohan-brain ADR-024 Accepted

## GitHub 전환 증거

- 이전 저장소: `byh3071-cpu/yohan-cc-skills`
- 현재 저장소: `byh3071-cpu/yohan-agent-kit`
- GitHub repository ID: `1272396648` (이름 변경 전후 동일)
- 기존 URL 조회: 새 저장소로 redirect 확인
- 기존 Draft PR #74: 새 저장소 URL에서 유지 확인
- 로컬 `origin`: `https://github.com/byh3071-cpu/yohan-agent-kit.git`

## 의도적으로 유지한 호환 표면

- `.claude-plugin/marketplace.json`의 Marketplace 이름 `yohan-cc-skills`
- plugin ID `yohan-core`, `workflow`, `critical-thinking`, `statusline`
- 첫 호환 릴리스의 `@yohan-cc-skills` 설치 suffix
- release-store cutover 전 로컬 checkout 폴더 `C:\Users\Public\dev\automation\yohan-cc-skills`
- Marketplace cache 경로와 과거 감사·로그의 기존 이름

## 계약 연결

- Brain 계약 커밋: `37068a625d85bb3955579a04d87cc0f5c503c823`
- Brain PR #194: merge commit `caf83175aa0466c063ac98d6c0764b67b2866cb7`
- Merge parents: base `06e8b2ece815f6bf9f23aec3d327c6ff52b4fdb8` + head `3257e5cf1610e869e19a16f73f5622fd188e0e35`
- Ancestry: Brain 계약 커밋이 `master`에서 도달 가능함을 확인했다.
- 디자인 resolver/recording 실행 소유자: `yohan-agent-kit`
- Agent Kit resolver/recorder는 위 Brain 커밋을 exact ref로 고정한다.

Brain PR #194의 선행 병합은 완료됐다. Agent Kit PR #74는 전체 회귀와 별도 사람 게이트를 통과한 뒤 병합한다.
