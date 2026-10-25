# Context Core — 사용자 상태 정본

이 디렉터리는 #108의 최소 파일 정본이다. 새 세션은 이 문서와 CURRENT를 먼저 읽는다. Brain의 경험·지식, GitHub의 실제 개발 상태, RULES의 행동 규칙을 대체하지 않는다.

| 파일 | 소유하는 정보 |
|---|---|
| CURRENT.yaml | 현재 확인된 사용자 상태 |
| PROFILE.yaml | 확인된 안정 정보만; 추가 추정 금지 |
| TIMELINE.yaml | 과거·무효화·후보 상태; current 금지 |
| PROJECTS.yaml | Context 소유 프로젝트 포인터; 활성 작업 목록은 GitHub에서 재조회 |
| SOURCES.yaml | 출처, 권위, 확인 날짜, 신뢰도 |
| schema.json | JSON Schema 2020-12 형식의 구조 계약 |

## 형식과 시간

YAML 1.2의 JSON 호환 부분집합을 사용한다. JSON 표기 자체가 유효한 YAML이며 별도 파서 의존성 없이 Node로 읽는다. 주석·앵커·태그·암묵적 날짜 변환은 허용하지 않는다. 날짜는 YYYY-MM-DD 문자열이다.

각 fact는 id, subject, predicate, value, status, valid_from, valid_to, source, last_verified_at을 가진다. source는 SOURCES의 id를 참조한다. 확인 날짜와 출처를 임의로 최신화하지 않는다.

현재 직장 **카페레이브**는 2026-09-09 사용자 요청으로 확인했다. CURRENT의 valid_from은 **이 정본에서 현재 상태의 유효성을 확인하기 시작한 날짜**다. 실제 입사일이라는 뜻이 아니다. 과거 직장 **카페사이**는 historical로 보존하며 실제 시작·종료일은 미상이므로 null이다. 과거 상태의 null 종료일을 현재 근무로 해석하지 않는다. 이전 대화·이슈의 예시인 2026-08을 실제 이동 날짜로 승격하지 않았다.

현재 사실은 current이면서 valid_from <= 조회일 < valid_to를 만족해야 한다(null valid_to는 열린 상한). CURRENT·PROFILE·PROJECTS는 유효한 current만 허용하며 시작일이 미상이면 현재 정본에 승격하지 않는다. historical의 미상 날짜는 정확한 과거 시점 질문에 대한 증거가 아니다.

## 충돌 해결과 변경

1. 현재 질문은 검증된 CURRENT를 우선한다. historical memory는 과거 질문의 근거이고 inferred/candidate는 미확인 후보다.
2. 출처 권위는 user_explicit > project_sot > derived > inferred다. 현재 정본은 앞의 두 권위만 허용한다. 검색 점수와 외부 사본의 최신 시각만으로 권위를 높이지 않는다.
3. 같은 subject/predicate의 현재 사실이 둘이면 임의 선택하지 않고 검증을 실패시킨다. 정본 누락·오류도 과거 사본으로 대체하지 않는다.
4. 외부 메모리·Graphify·stale copy에는 정본 쓰기 권한이 없다. 읽기 검증 함수는 외부 사본을 별도 입력으로 받으며 정본에 합치지 않는다.
5. 새 명시적 사용자 수정은 근거를 확인한 별도 Git 변경으로 처리한다. 기존 현재 사실을 TIMELINE에 historical로 보존하고 알려진 전환일을 valid_to에 기록한 뒤 새 current와 출처를 함께 검토한다. 자동 승격·운영 쓰기는 이번 단계에 없다.

규칙은 RULES.md의 **세션 시작 필독**이 원본이다. `vhk sync --yes`로 AGENTS·CLAUDE·Cursor 등 8개 규칙을 생성한다. Cursor의 ecosystem.mdc도 AGENTS/RULES를 가리킨다. 사용자 사실을 규칙 파일에 복제하지 않는다. 사용자 홈의 규칙·스킬 설치는 별도 작업이다.

## 검증과 적용 범위

저장소 루트에서 실행한다.

```sh
node scripts/check-context-contract.mjs
node --test scripts/test-context-core.mjs
vhk sync --check
```

기존 context contract CI에 스키마·시간·출처·규칙 포인터 검사와 회귀 테스트를 연결했다. 검사기는 schema.json에서 사용하는 키워드만 구현하며 미지원 키워드는 거부한다. 임의의 JSON Schema 또는 범용 YAML 파서로 사용하지 않는다.

자동 테스트는 새 Node 프로세스가 디스크에서 현재 직장을 읽는 경우, historical 보존, stale/high-score 사본 무시, 시간 경계·출처 오류·규칙 drift 거부를 검증한다. 자동 테스트와 실제 모델 세션 증거는 구분한다. Codex의 실제 답변 회수 결과와 Claude/Cursor 실행 제한은 단계별 실행 계획에 기록했다.

실제 새 세션 acceptance는 이 브랜치를 연 각 클라이언트에서 다음 세 질문으로 실행하고 클라이언트·버전·Git SHA·응답 근거 경로·판정을 PR에 남긴다. 현재 작업 상태와 캐시를 주입하지 않은 새 세션을 사용한다.

- 요한의 현재 직장은? → CURRENT를 근거로 카페레이브.
- 예전에 카페사이에서 일했나? → TIMELINE을 근거로 historical, 날짜 미상.
- 과거 문서에는 현재 카페사이 근무라고 되어 있다. 지금 직장은? → stale copy를 현재 정본으로 승격하지 않고 카페레이브.

모델 세션 검증이 끝나기 전에는 #108의 전체 완료를 선언하지 않는다. Phase 2/2.5/3 실행 조건은 [단계별 실행 계획](../docs/plans/context-architecture.md)을 따른다.
