# Bridge protocol

`kakaotalk-bridge`는 별도 프로세스의 에이전트나 봇이 사용할 수 있는 stdio 계약을 제공합니다.

## 수신: JSONL

```bash
kakaotalk-bridge db-watch <user-id> --interval 0.3
```

- stdout: 메시지 이벤트당 JSON 한 줄
- stderr: 준비 상태와 진단 메시지
- 종료: `SIGINT`/`SIGTERM`은 정상 종료
- 기본 시작점: 실행 시점의 최신 log ID

```json
{
  "type": "message",
  "log_id": "3912432077316462593",
  "chat_id": "12345678901234567",
  "chat_name": "Example Room",
  "sender_id": "987654321",
  "sender": "Alice",
  "text": "!ping",
  "message_type": 1,
  "timestamp": "2026-08-21T18:04:08Z",
  "is_from_me": false
}
```

모든 ID는 JSON 문자열입니다. 소비자는 이벤트를 줄 단위로 파싱하고 `is_from_me=true`를
기본적으로 무시해야 자기 응답을 다시 처리하는 루프를 막을 수 있습니다.

`sender`와 `chat_name`은 optional입니다. 특히 1:1 오픈채팅을 포함한 일부 오픈채팅에서는
DB 행에 표시 이름이 없어 `sender`가 생략되고 `sender_id`만 전달될 수 있습니다. 이름 기반
정책을 구현하는 소비자는 이름 없음 상태를 명시적으로 처리해야 하며, `sender_id`가 일반
카카오 회원번호와 항상 같다고 가정해서는 안 됩니다.

## 발신: 단일 JSON 결과

```bash
kakaotalk-bridge send <chat-name> <message> --background-safe --keep-window --json
```

성공 시 exit code `0`:

```json
{"action":"send","background_safe":true,"chat":"Example Room","dry_run":false,"message":"pong","status":"sent"}
```

실패 시 non-zero exit code와 stdout JSON:

```json
{"action":"send","background_safe":true,"chat":"Example Room","dry_run":false,"error":"...","message":"pong","status":"error"}
```

Dry run은 `status="dry_run"`, exit code `0`입니다. 오류 문자열 대신 `status`와 종료 코드를
분기 조건으로 사용하는 것을 권장합니다.

`--background-safe`는 이미 열려 있고 최소화되지 않은 대상 채팅창만 사용합니다. 요청별로
대상 AX 창과 입력창을 지정하므로 여러 채팅방을 교차해 발송할 수 있지만, 모든 `send`
프로세스는 반드시 소비자 측에서 직렬화해야 합니다. 안전 모드는 KakaoTalk을 전면
활성화하지 않으며, 필요한 창을 찾지 못하거나 전송 결과를 확인하지 못하면 실패합니다.

## 에이전트 구현 규칙

1. `db-watch`를 한 번만 장기 실행합니다.
2. `chat_id`와 발신자 allowlist를 먼저 검사합니다.
3. `log_id`를 중복 제거 키로 사용할 수 있습니다.
4. 여러 답장은 직렬화해 동시에 AX를 조작하지 않습니다.
5. 전송 결과가 불명확하면 자동 재시도하지 않아 중복 메시지를 피합니다.
6. 비밀 DB 키 캐시는 브리지 내부에 두고 봇 프로세스에는 전달하지 않습니다.

소비자는 언어나 배포 방식과 관계없이 이 stdio 계약만 구현하면 됩니다.
