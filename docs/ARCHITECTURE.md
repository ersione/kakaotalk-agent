# Agent architecture

`kakaotalk-agent`는 로그인된 KakaoTalk macOS 앱에서 메시지를 수신하고 발신하는 로컬
Swift CLI입니다. 수신은 로컬 SQLCipher DB, 발신은 macOS Accessibility(AX) API를
사용하며 KakaoTalk 서버 프로토콜을 구현하지 않습니다.

```text
                         kakaotalk-agent
                  +---------------------------+
KakaoTalk DB ---->| DB discovery / SQLCipher |----> JSONL message events
                  | DatabaseWatcher           |
                  |                           |
JSON send request | ChatWindowResolver        |----> KakaoTalk AX windows
----------------->| composer / send pipeline  |
                  +---------------------------+
```

## Module layout

```text
native/Sources/
  KakaoDBCore/
    Database/       SQLCipher DB 탐색·열기·쿼리
    Models/         채팅방·메시지 모델
    Sync/           log ID 기반 신규 메시지 watcher
  KakaoTalkBridge/
    Accessibility/  AXUIElement wrapper와 입력 액션
    KakaoTalk/       앱·채팅창·composer 탐색
    Database/        계정 DB 검증과 인증 캐시
    Commands/        db-discover, db-watch, send 등 CLI 진입점
```

## Receive path

1. `db-discover`가 KakaoTalk container의 DB 후보와 로컬 회원번호를 탐색합니다.
2. `db-status <user-id>`가 기기 UUID와 회원번호로 파생한 키를 검증합니다.
3. 검증된 DB 경로와 키를 `~/.config/kakaotalk-agent/db-auth.json`에 권한 `0600`으로
   캐시합니다.
4. `db-watch`가 `NTChatMessage.logId`를 cursor로 사용해 신규 행을 폴링합니다.
5. 메시지를 한 줄씩 JSONL로 stdout에 출력합니다.

DB는 항상 read-only로 열며, KakaoTalk 앱이 비활성 상태여도 수신 감시를 계속할 수 있습니다.

## Send path

1. 채팅방 표시 이름으로 이미 열린 `AXWindow`를 찾습니다.
2. 대상 창 안에서 composer `AXTextArea`를 해석하고 `AXValue`로 문자열을 설정합니다.
3. `--background-safe`에서는 앱을 활성화하지 않고 KakaoTalk 내부의 focused window와
   focused UI element만 대상 composer에 맞춥니다.
4. composer 주변의 `전송` 버튼 `AXPress`를 우선 시도합니다.
5. 필요하면 버튼 좌표의 PID-targeted click과 PID-targeted Return을 순서대로 시도합니다.
6. composer가 비워졌는지로 전송 수락을 검증하고 JSON 결과와 exit code를 반환합니다.

여러 채팅방을 교차해 발송할 수 있지만 AX 포커스 상태를 공유하므로 `send` 호출은 항상
직렬화해야 합니다.

## Process and protocol boundary

- `db-watch`: 장기 실행 JSONL producer
- `send --json`: 요청당 하나의 JSON 결과를 반환하는 단기 프로세스
- stdout: 기계가 파싱하는 JSON/JSONL
- stderr: 준비 상태와 AX 진단

외부 소비자는 Swift 모듈을 직접 불러오지 않고 [`PROTOCOL.md`](PROTOCOL.md)의 stdio 계약으로만
통신합니다.
