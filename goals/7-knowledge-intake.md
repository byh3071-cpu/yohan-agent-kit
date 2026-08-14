---
vhk_format: 1
type: goal
id: 7
title: 노하우 Intake와 승격 파이프라인
status: DONE
priority: P0
---

# Goal 7: 노하우 Intake와 승격 파이프라인

## 목적

새 Skill, Agent, Command, Hook, Rule, MCP와 외부 디자인 노하우를 잃지 않되, 비밀정보·중복·라이선스 위험을 Git 정본에 자동 반입하지 않는다.

## Tasks

1. raw 발견 결과를 `~/.yohan-agent-kit/inbox/`에만 보관한다.
2. 후보마다 provenance, license, digest, portability, evidence를 기록한다.
3. 중복·비밀정보·절대경로·라이선스 검사를 수행하고 정제된 후보를 만든다.
4. lifecycle을 candidate → reviewed → approved → released로 제한하고 사람 승인 없이 마지막 두 상태로 갈 수 없게 한다.
5. Draft PR용 산출물은 만들 수 있지만 자동 push는 하지 않는다.

## Completion Check

- [x] Check/Scan은 Git tracked 파일을 수정하지 않는다.
- [x] raw inbox는 저장소 밖에만 있고 `.gitignore`와 검사에서 보호된다.
- [x] secret 또는 license UNKNOWN 후보는 승격할 수 없다.
- [x] 같은 digest 또는 같은 canonical ID 후보는 중복으로 차단된다.
- [x] AI 단독 실행은 lifecycle `reviewed`를 넘지 못한다.
- [x] Draft PR bundle 생성과 push가 분리돼 있다.
- [x] PowerShell 5.1 테스트와 Goal 7 gate가 통과한다.

## 사람 게이트

- 후보 승인·거절
- Draft PR push·생성
