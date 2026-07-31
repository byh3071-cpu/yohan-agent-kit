---
id: PAT-008
패턴명: 도구가 PATH 선두의 재귀 git.cmd wrapper를 다시 호출함
카테고리: git
증상: |
  PowerShell 자동화에서 Git 명령이 `Maximum setlocal recursion level reached`와 함께 실패하거나, 동일한 wrapper가 반복 호출된다. 터미널에서 직접 실행한 Git과 자동화 내부 Git의 동작이 다르다.
원인: |
  호스트 애플리케이션이 명령 귀속이나 관찰을 위해 PATH 선두에 `git.cmd` wrapper를 넣었다. 자동화가 bare `git`을 실행하면 실제 `git.exe`보다 wrapper가 먼저 선택되고, wrapper가 다시 bare `git`을 호출할 경우 자신을 재귀 실행한다.
해결: |
  Git을 호출하는 PowerShell 도구는 `Get-Command git.exe -CommandType Application -All`로 실제 실행 파일 후보를 찾고 존재하는 첫 `.exe`의 절대경로를 사용한다. PATH나 Git 전역 설정은 바꾸지 않는다. 찾지 못하면 fail-closed하고, 테스트에서는 실패하는 `git.cmd`를 PATH 선두에 둔 상태에서도 실제 `git.exe`로 정본 검사가 성공하는지 고정한다.
적용조건: Windows 호스트 애플리케이션·IDE·오케스트레이터가 PATH에 명령 wrapper를 주입하는 환경의 PowerShell Git 자동화
출처프로젝트: yohan-cc-skills
태그: [windows, powershell, git, path, wrapper, recursion, orca]
발견일: 2026-07-31
출처DevLog: "2026-07-29 adr-cycle·goal-cycle 멀티벤더 정본화"
---

# PAT-008 — wrapper보다 실제 git.exe를 명시적으로 선택

## 핵심 한 줄

Windows 자동화에서 bare `git`은 실제 Git이라는 보장이 없다. 호스트가 PATH에 wrapper를 주입할 수 있으면 `git.exe` 실행 파일을 해석해 절대경로로 호출한다.

## 실패하기 쉬운 순서

1. Orca나 IDE가 터미널 명령 귀속용 `git.cmd`를 PATH 선두에 둔다.
2. PowerShell 도구가 bare `git`을 실행한다.
3. wrapper가 다시 bare `git`을 호출하면서 같은 wrapper로 돌아온다.
4. Git 정본 검사가 실행되기 전에 배치 파일의 `setlocal` 재귀 한도에서 실패한다.

## 검증 방법

- 실패 코드만 반환하는 가짜 `git.cmd`를 테스트 PATH 선두에 둔다.
- 같은 프로세스에서 `Get-Command git.exe -CommandType Application -All`이 실제 실행 파일을 선택하는지 확인한다.
- 정본 worktree·index blob 검사가 통과하고 가짜 wrapper의 출력이 결과에 섞이지 않는지 확인한다.
- 테스트 뒤 PATH를 원래 프로세스 값으로 복원한다.

## 한계

이 패턴은 PATH wrapper 재귀만 피한다. 선택된 `git.exe` 자체의 신뢰성이나 실행 파일 교체 공격을 검증하려면 서명·고정 경로·해시 정책이 별도로 필요하다.
