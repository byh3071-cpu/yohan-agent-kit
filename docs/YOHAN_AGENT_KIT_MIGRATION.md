# Yohan Agent Kit 이름 전환

ADR-024에 따라 GitHub 정본 저장소는 `byh3071-cpu/yohan-agent-kit`이다. 이름 전환은 배포 발견 경로를 한 번에 깨뜨리지 않도록 세 층으로 나눠 진행한다.

## 현재 호환 상태

| 층 | 현재 값 | 상태 |
|---|---|---|
| GitHub 정본 | `byh3071-cpu/yohan-agent-kit` | 전환 완료 |
| Claude Marketplace namespace | `yohan-cc-skills` | 첫 호환 릴리스까지 유지 |
| 개별 plugin ID | `yohan-core`, `workflow`, `critical-thinking`, `statusline` | 유지 |
| 로컬 canonical checkout | `C:\Users\Public\dev\automation\yohan-cc-skills` | release-store cutover 전까지 유지 |
| 향후 release store | `~/.yohan-agent-kit/releases/<release-id>/` | Goal 6에서 구현 |

Marketplace 등록 소스는 새 GitHub 이름을 사용하지만 설치 식별자는 아직 기존 namespace를 사용한다.

```text
claude plugin marketplace add byh3071-cpu/yohan-agent-kit
claude plugin install yohan-core@yohan-cc-skills
```

`dotfiles/claude/settings.json`도 같은 경계를 따른다. `extraKnownMarketplaces.yohan-cc-skills.source.repo`는 `byh3071-cpu/yohan-agent-kit`을 가리키고, `enabledPlugins`의 `@yohan-cc-skills` suffix는 유지한다.

## 전환 순서

1. ADR-024와 Brain 소유권 계약을 먼저 병합한다.
2. 첫 호환 릴리스에서 새 GitHub 소스와 기존 Marketplace namespace 조합을 두 PC에서 검증한다.
3. Goal 6 release store로 설치 입력을 Git checkout에서 분리한다.
4. 사용자 승인 후 Marketplace namespace를 `yohan-agent-kit`으로 바꾸고 제거·재등록 절차를 실행한다.
5. 두 PC 검증 후 로컬 canonical checkout 폴더를 `C:\Users\Public\dev\automation\yohan-agent-kit`으로 바꾼다.

## 롤백

- GitHub 이름 변경 뒤 기존 URL은 GitHub redirect로 새 저장소를 가리킨다.
- 첫 호환 릴리스 전에는 Marketplace namespace와 로컬 경로가 그대로이므로 기존 설치 발견 경로를 되돌릴 필요가 없다.
- 새 GitHub 소스가 실패하면 Marketplace 설정의 `repo`만 GitHub가 허용하는 유효한 소스로 복원하고 plugin ID와 설치 경로는 건드리지 않는다.
- release store 전환 뒤에는 `Manage-AgentKit.ps1 -Mode Restore`의 exact backup ID와 release manifest를 사용한다.

Marketplace 전환, 로컬 폴더 변경, 사용자 홈 쓰기, PR Ready/merge는 각각 사람 승인 게이트다.
