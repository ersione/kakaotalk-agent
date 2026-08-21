# kakaotalk-agent

macOS용 카카오톡 로컬 에이전트/CLI입니다. 공식 Bot API가 아니라 로그인된 KakaoTalk macOS
앱의 로컬 SQLCipher DB와 Accessibility(AX) API를 조합합니다.

- `db-discover`: 로컬 계정 회원번호와 암호화 DB 탐색
- `db-status`: 회원번호에 해당하는 DB 검증과 인증 캐시 생성
- `chats [--ax]`: 채팅방 목록·타입·안 읽은 개수
- `messages [--ax]`: 채팅방 최신 메시지
- `search`, `unread`: 로컬 메시지 검색과 안 읽은 대화
- `watch [--ax]`: 새 메시지를 JSONL로 스트리밍
- `send --json`: 열린 채팅창으로 메시지 전송
- `send --background-safe`: 다른 앱의 포커스를 빼앗지 않는 대상 PID 전송

특정 명령어나 응답 정책은 포함하지 않습니다. 외부 봇은 이 README의 JSON/JSONL
계약으로 연결합니다.

> 비공식 자동화 도구입니다. KakaoTalk 업데이트로 DB 스키마·암호화·AX 트리가 바뀌면
> 동작하지 않을 수 있으며 계정 운영 책임은 사용자에게 있습니다.

## 동작 구조

```text
KakaoTalk SQLCipher DB ──► chats/messages/search/unread/watch ──► JSON/JSONL
KakaoTalk open window ◄── kakaotalk-agent send ◄────── JSON command/result
                              │
                              └─ AXValue + AX focus + AXPress/CGEventPostToPid
```

수신에는 채팅창이 필요 없습니다. 백그라운드 발신은 대상 채팅창이 같은 macOS Space에 열려
있고 최소화되지 않아야 합니다. 안전 모드에서는 창이나 composer를 찾지 못해도 KakaoTalk을
전면 활성화하지 않고 실패합니다.

기본 조회와 감시는 DB를 read-only로 사용합니다. `chats`, `messages`, `watch`에서 실제
KakaoTalk 화면을 기준으로 동작해야 할 때만 `--ax`를 사용합니다. `search`와 `unread`는
DB 전용이고 `send`는 본래 AX 기반입니다.

### 내부 모듈

```text
KakaoDBCore/Database  DB 탐색·SQLCipher·read-only 쿼리
KakaoDBCore/Sync      log_id cursor 기반 watcher
KakaoTalkBridge/AX    채팅창·composer 탐색과 입력
Commands/             CLI와 JSON/JSONL 경계
```

## 요구 사항

- macOS 14 이상
- 로그인된 KakaoTalk macOS 앱
- Xcode Command Line Tools 또는 Xcode
- Homebrew `sqlcipher`, `pkgconf`
- 실행 호스트의 macOS `손쉬운 사용` 권한

```bash
xcode-select --install
brew install sqlcipher pkgconf
```

화면 녹화 권한은 현재 DB 수신과 AX 발신에 원칙적으로 필요하지 않습니다. 다른 Space에서도
창을 찾게 하려면 Dock의 KakaoTalk 아이콘에서 `Options > Assign To > All Desktops`를
설정할 수 있습니다.

## 빌드

```bash
swift build -c release --package-path native
native/.build/release/kakaotalk-agent status
```

Swift가 SQLCipher를 찾지 못하면 다음을 확인합니다.

```bash
pkg-config --modversion sqlcipher
brew --prefix sqlcipher
```

## 로컬 DB 인증 캐시

에이전트는 일반 설정 파일이나 자체 실행 경로를 필요로 하지 않습니다. `db-status`가 검증한
DB 경로와 파생 키만 `~/.config/kakaotalk-agent/db-auth.json`에 권한 `0600`으로 캐시합니다.
실행 바이너리 경로, 사용할 계정, 채팅방·명령 정책은 호출하는 봇이 자신의 설정에서
관리합니다.

## 최초 회원번호와 DB 찾기

카카오 계정 이메일 대신 숫자 회원번호가 DB 키 파생에 사용됩니다.

```bash
native/.build/release/kakaotalk-agent db-discover
native/.build/release/kakaotalk-agent db-discover --json
```

```json
{"accounts":[{"database":"<db-file>","user_id":123456789,"verified":true}],"database_count":1}
```

탐색은 plist 후보, 기존 검증 캐시, 필요시 활성 계정 SHA-512 pre-image 복구를 사용합니다.
최초 실행은 시간이 걸릴 수 있습니다. 여러 계정의 숫자 ID와 이메일 관계는 사용자가 한 번
확인해야 하며 이메일은 암호화 DB 이름만으로 복원할 수 없습니다.

회원번호를 알고 있다면 직접 검증합니다.

```bash
native/.build/release/kakaotalk-agent db-status 123456789 --json
```

파생 DB 키는 같은 디렉터리의 `db-auth.json`에 권한 `0600`으로 별도 캐시됩니다.
`db-auth.json`은 공유하거나 커밋하지 마세요.

## 채팅방·메시지 조회

```bash
native/.build/release/kakaotalk-agent chats --user-id 123456789 --json
native/.build/release/kakaotalk-agent chats --ax --json
native/.build/release/kakaotalk-agent messages --user-id 123456789 --chat-id 12345678901234567 --json
native/.build/release/kakaotalk-agent messages --ax --chat "채팅방 이름" --background-safe --json
native/.build/release/kakaotalk-agent search --user-id 123456789 "검색어" --json
native/.build/release/kakaotalk-agent unread --user-id 123456789 --json
```

DB 채팅방은 `chat_type` (`direct`, `group`, `open`, `unknown`)과 원본
`chat_type_code`를 함께 출력합니다. 현재 검증된 매핑은 `0=direct`, `1=group`, `4=open`이며
나머지는 `unknown`으로 두고 숫자 코드를 보존합니다. DB에 방 이름이 없으면
`chat_name`은 `(unknown)`일 수 있으며, 이때 `chats --ax`로 화면 표시 이름을 확인합니다.

## 메시지 수신

```bash
native/.build/release/kakaotalk-agent watch --user-id 123456789 --interval 0.3
```

이벤트당 JSON 한 줄이 stdout으로 출력됩니다.

```json
{"chat_id":"12345678901234567","chat_type":"open","chat_type_code":4,"is_from_me":false,"log_id":"3912432077316462593","sender":"Alice","sender_id":"987654321","text":"!ping","timestamp":"2026-08-21T18:04:08Z","type":"message"}
```

JavaScript 정밀도 손실을 막기 위해 `chat_id`, `log_id`, `sender_id`는 문자열입니다.
기본 시작점은 실행 시점의 최신 log ID이며 과거 이벤트를 재생하지 않습니다.

`sender`와 `chat_name`은 선택 필드입니다. 일반 채팅에서는 대체로 발신자 표시 이름을 얻을 수
있지만, 1:1 오픈채팅을 포함한 일부 오픈채팅 이벤트는 `sender` 없이 `sender_id`만 제공할 수
있습니다. 소비자는 이름이 항상 존재한다고 가정하면 안 됩니다. 또한 오픈채팅의 `sender_id`는
일반 계정 회원번호와 동일하다고 가정하지 않는 편이 안전합니다.

```bash
native/.build/release/kakaotalk-agent watch --user-id 123456789 --interval 0.3 --since-log-id 3912430000000000000
```

## 메시지 발신

포커스를 빼앗지 않는 권장 방식:

```bash
native/.build/release/kakaotalk-agent send "채팅방 표시 이름" "안녕하세요" \
  --background-safe --keep-window --json
```

```json
{"action":"send","background_safe":true,"chat":"채팅방 표시 이름","dry_run":false,"message":"안녕하세요","status":"sent"}
```

Dry run:

```bash
native/.build/release/kakaotalk-agent send "채팅방 표시 이름" "안녕하세요" \
  --background-safe --json --dry-run
```

사람이 직접 사용하는 복구 모드에서는 `--background-safe`를 빼면 창 탐색 과정에서
KakaoTalk을 활성화할 수 있습니다. 무인 봇은 안전 모드를 권장합니다.

### 여러 채팅방으로 백그라운드 발신

`--background-safe`는 여러 개로 열려 있는 채팅창 사이를 번갈아 발신할 수 있습니다. 각 요청은
채팅방 표시 이름으로 대상 `AXWindow`와 composer를 찾고, KakaoTalk 프로세스 안의 포커스를
그 창과 입력창에 맞춘 뒤 `전송` 버튼 `AXPress`를 우선 사용합니다. 필요하면 대상 PID 좌표
클릭과 Return으로 폴백합니다. 이 과정은 `NSRunningApplication.activate()`를 호출하지 않으므로
현재 사용 중인 다른 앱의 포커스를 빼앗지 않습니다.

다중 채팅방 발신 조건:

- 각 대상 채팅창을 미리 열어 둡니다.
- 창은 최소화하지 않고 현재 macOS Space에서 AX로 보여야 합니다.
- 여러 `send`를 동시에 실행하지 않고 큐에서 직렬화합니다.
- KakaoTalk 버전에 따라 AX 액션의 반환값과 실제 결과가 다를 수 있어 composer가
  비워졌는지로 전송 결과를 검증합니다.

## JSON 프로토콜

- stdout: JSON 또는 JSONL 기계 데이터
- stderr: 준비 상태, AX trace, 진단
- `watch`: 장기 실행 JSONL producer
- `send --json`: 단일 JSON 결과와 프로세스 exit code
- 모든 외부 소비자는 `is_from_me=true`를 무시해 자기 응답 루프를 방지
- AX 발송은 동시에 여러 개 실행하지 말고 직렬화
- 불명확한 전송 오류는 중복 위험 때문에 무한 자동 재시도 금지

성공은 exit code `0`, 실패는 non-zero를 사용합니다. ID는 JavaScript 정밀도 손실을 피하기 위해
JSON 문자열로 전달합니다. `sender` 또는 `chat_name`이 없을 수 있으므로 소비자는 optional로
처리해야 합니다.

## 운영상 제약

- 발신 대상 창이 최소화되거나 다른 Space에 있으면 AX에서 찾지 못할 수 있음
- 동일 표시 이름의 방은 AX 이름 매칭이 모호하므로 고유 이름 권장
- KakaoTalk 업데이트로 DB 또는 AX 호환성이 깨질 수 있음
- DB 키 캐시와 개인 계정 매핑은 공개 저장소에 포함하지 않음

## 참조 및 저작권

- [`channprj/kmsg`](https://github.com/channprj/kmsg) (MIT): Swift AX 브리지 기반
- [`silver-flight-group/kakaocli`](https://github.com/silver-flight-group/kakaocli) (MIT): SQLCipher
  DB 탐색·키 파생·watcher와 AX composer 구조
- [`JungHoonGhae/openkakao-cli`](https://github.com/JungHoonGhae/openkakao-cli) (MIT): 열린
  채팅창 fast path와 `CGEventPostToPid` 기반 비활성 발송
- [`steipete/Peekaboo`](https://github.com/steipete/Peekaboo) (MIT): openkakao가 참조한 대상
  PID 직접 이벤트 전달 방식
- [`cskwork/kakao-userid-recover`](https://github.com/cskwork/kakao-userid-recover) (AGPL):
  개발 중 회원번호 진단에만 사용했으며 코드는 포함하지 않음

세부 고지는 `native/NOTICE.md`와 `native/LICENSE.*`에 있습니다.

## License

이 프로젝트의 자체 코드는 루트 [`LICENSE`](LICENSE)의 MIT License로 배포됩니다. 파생·참조
코드의 저작권과 라이선스는 `native/NOTICE.md`와 각 `native/LICENSE.*`를 따릅니다.
