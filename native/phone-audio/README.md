# Remote microphone transport

The library behind `src/base/UPhoneAudio.pas`. It keeps a TLS WebSocket open to
the relay, registers a room, takes the phone's offer for a WebRTC data channel
and queues the PCM packets that arrive on either route until the game polls
them. Everything that has to be fast or has to speak TLS lives here; room code,
player slot and pitch stay in Pascal.

Taken from [UltraStar Community Edition](https://github.com/UltraStar-CE/USCE)
(GPL-2.0), which also runs the relay at `usdx.at`. Only the file that tests the
relay socket was left out, because this fork does not use that ABI.

## Build

Needs CMake 3.22+, a C++17 compiler, OpenSSL development files and Git - CMake
downloads libdatachannel and nlohmann/json itself and links them statically, so
the finished library needs nothing but the system C++ runtime.

```sh
tools/build-phone-audio.sh
```

The script writes `game/libusce-phone-audio.dylib` (or `.so`/`.dll`) next to the
game binary, which is where `UPhoneAudio` looks for it, and also drops it into
`UltraStar Deluxe.app/Contents/MacOS` when that bundle exists. `[Remote]
Library=` in `config.ini` overrides the path.

Without the library the game starts as before and logs one warning when
`[Remote] Microphone=On`; nothing else changes.
