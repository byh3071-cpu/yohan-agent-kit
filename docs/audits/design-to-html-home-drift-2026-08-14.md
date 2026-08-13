# design-to-html 집 PC 읽기 전용 drift 감사

검사일: 2026-08-14
검사 방식: `Check`만 사용. Install·Restore·사용자 홈 쓰기 없음.

## 비교 기준

- 노트북 인계 branch: `feat/design-to-html-skill`
- 노트북 인계 commit: `6fdc99a035ed1fe552323982de74e70807dc71ce`
- 집 PC canonical checkout: 같은 branch와 commit, clean worktree
- design-to-html manifest digest: `7C634939CFD4C45D5F9D6EB5BE939C44A289BC43445AEBBFE12C5457E6EF4134`

## 결과

| 계층 | 집 PC 판정 | 근거 |
| --- | --- | --- |
| 멀티벤더 스킬 | `Healthy` | Agents·Claude·AgyStandard junction 3개가 집 PC canonical checkout을 정확히 가리키고 manifest digest가 인계 commit과 일치 |
| 격리 작업 branch 비교 | 내용 drift 없음 | canonical `skills/design-to-html/`과 격리 worktree의 같은 디렉터리를 byte 비교했으며 차이 없음 |
| Product Design context | `Healthy`, `owned` | 생성 digest `C32B1B6A8B0E989CCA020A271222B9850B38CBA0A736309F92D5B2F71376B797`; transaction state `Owned` |
| Brain 필수 파일 | `Present` 2건 | `memory/rules/html-artifact-design.md`, `docs/reference/websites/ai-workspace-context-trust-navigator.md` |
| `product-design` plugin | `Tested` | 계약 `0.1.52`, 감지 `0.1.52` |
| `workflow` plugin | `Tested` | 계약 `0.3.9`, 감지 `0.3.9` |
| `yohan-core` plugin | `Drift` | 계약 `0.3.22`, 감지 `0.3.19`; `TestedVersionMissing` |

## 판정

스킬·Brain·Product Design context에는 내용 drift가 없다. 전체 환경 상태가 `Drift`인 이유는 `yohan-core` 검증 계약 버전이 집 PC 캐시에 없기 때문이다. 이 감사에서는 전역 Install·Restore를 실행하지 않았으므로 플러그인 drift는 남은 사람 게이트다.

격리 worktree를 `RepositoryRoot`로 강제한 스킬 Check는 기존 junction의 canonical source identity가 다르므로 `Conflict`를 반환했다. 실제 설치 canonical checkout을 기준으로 다시 실행한 Check는 `Healthy`였고 두 skill 디렉터리의 byte 비교도 동일했다. 따라서 이 source-identity 차이를 skill 내용 drift로 분류하지 않는다.
