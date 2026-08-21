# Repository architecture

## 권장 공개 구조

장기적으로는 두 저장소가 가장 관리하기 좋습니다.

```text
public: kakaotalk-local-bridge
  Swift CLI + DB reader + AX sender + JSON/JSONL protocol + docs

private: louis-kakaotalk-bot
  personal config + commands + NAS URL + deployment + logs + secrets
```

두 프로젝트가 공유해야 하는 실행 파일 경로와 계정 선택은
`~/.config/kakaotalk-agent/config.json`에 두고, DB 파생 키는 같은 디렉터리의
`db-auth.json`에 분리합니다. 봇 저장소에는 방과 명령 정책만 둡니다.

공개 저장소는 카카오톡과 외부 프로그램 사이의 범용 로컬 에이전트 역할만 담당합니다.
비공개 저장소는 특정 방, 발신자, URL, 계정 이메일과 실제 응답 정책을 담당합니다.

## 분리하는 이유

- 공개 코드에 개인 이메일·회원번호·방 ID·내부 URL이 섞일 위험 감소
- 브리지 프로토콜 버전과 봇 기능 배포 주기를 독립적으로 관리
- 다른 사용자가 Node.js 없이도 원하는 언어로 JSONL을 소비 가능
- AX/DB 관련 이슈와 개인 봇 명령 관련 이슈 분리
- 브리지에는 공개 라이선스, 비공개 봇에는 별도 정책 적용 가능

## 분리 시점

현재 로컬 프로젝트는 이미 두 폴더로 분리했습니다. 공개 전에는 다음 항목을 마무리합니다.

- `db-discover`, `db-watch`, `send --json` 인터페이스 버전 고정
- 새 macOS 계정에서 최초 설치 절차 재검증
- 최소 한 번의 버전 태그와 바이너리 배포 방식 결정
- 공개 저장소의 루트 라이선스 결정

분리할 때 TypeScript 봇이 Swift 소스를 import하지 않게 합니다. 릴리스 바이너리 또는 Homebrew
formula를 설치한 뒤 stdio JSON/JSONL로만 통신하는 것이 저장소 사이의 안정적인 경계입니다.
