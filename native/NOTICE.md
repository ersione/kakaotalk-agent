# Third-party attribution

The native bridge is derived from [`channprj/kmsg`](https://github.com/channprj/kmsg),
Copyright (c) 2026 Chan Kim, under the MIT License. Its license is included in
`LICENSE.kmsg`.

The project keeps the native Accessibility implementation locally so we can
stabilize and extend the event protocol independently of upstream CLI releases.

The database reader and watcher under `Sources/KakaoDBCore` are derived from
[`silver-flight-group/kakaocli`](https://github.com/silver-flight-group/kakaocli),
Copyright (c) 2026 Silver Flight Group, LLC, under the MIT License. Its license
is included in `LICENSE.kakaocli`.

The background AX send path references
[`JungHoonGhae/openkakao-cli`](https://github.com/JungHoonGhae/openkakao-cli),
Copyright (c) 2026 Lucas (JungHoonGhae), under the MIT License. In particular,
it uses the open-chat composer fast path and sends Return directly to the
KakaoTalk process with `CGEventPostToPid` so the foreground application is not
changed. Its license is included in `LICENSE.openkakao`.

openkakao credits [`silver-flight-group/kakaocli`](https://github.com/silver-flight-group/kakaocli)
for its original AX composer automation and [`steipete/Peekaboo`](https://github.com/steipete/Peekaboo)
for the target-PID event delivery approach. We preserve that provenance here.

[`cskwork/kakao-userid-recover`](https://github.com/cskwork/kakao-userid-recover)
(AGPL) was used only as a development-time diagnostic to validate account-ID
recovery. No source code from that project is included.
