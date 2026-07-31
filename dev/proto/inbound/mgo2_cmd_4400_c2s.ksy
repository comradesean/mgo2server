meta:
  id: mgo2_cmd_4400_c2s
  title: "MGO2 0x4400 — in-game chat message (client -> server)"
  endian: be
doc: |
  Builder function `0xD52CEC` = `f(ctx, u8 kind, void *blob)`; a null `blob` aborts before any
  write (`0xD52D20`). `bl 0xD5CF40` at `0xD52D6C` (`li r4,0x4400` at `0xD52D68`), seal
  `0xD5C828` at `0xD52D9C`, flush `0xD34CC0` at `0xD52DAC`. Not encrypted.
  **Total payload 129 bytes (0x81).**

  Writes: `0xD5C8A0` (u8) at `0xD52D7C` from `r1+1432` (the `kind` argument, `stb r4` at
  `0xD52D14`), then `0xD5D0AC` with `r5=128` at `0xD52D90` copying the caller's buffer verbatim.

  Note what the sender does **not** do: no length argument, no `strlen`, no charset check — 128
  bytes are copied unconditionally. Compare `0x43C0`, whose 128-byte comment field *is* length
  checked. The earlier note here read the absent length check as proof that "the payload is a
  fixed-size record, not a string" — **that inference was wrong** (see below). It is a string; the
  caller hands the builder a pre-padded 128-byte buffer, which is why the builder has nothing to
  check.

  **CAPTURE-PROVEN 2026-07-26 — this is the in-game chat send.** Four live `0x4400` packets from
  `BLUS30109` in a GAME lobby, typed into the in-game message box (payloads as logged by
  `GameServerHandler`, trailing NUL padding elided):

  | typed by the player | payload head | kind | digit | text |
  | --- | --- | --- | --- | --- |
  | `hi`         | `00 30 68 69 00`          | `00` | `'0'` | `hi` |
  | `hello`      | `00 30 68 65 6c 6c 6f 00` | `00` | `'0'` | `hello` |
  | `/team team` | `01 31 74 65 61 6d 00`    | `01` | `'1'` | `team` |
  | `/all all`   | `00 30 61 6c 6c 00`       | `00` | `'0'` | `all` |

  Three things follow, all tier 2:

  1. **This is all-chat vs team-chat.** The captures typed `/all` and `/team`; `kind` and the digit
     moved together, 0 and 1. **The reading "`kind` is the channel" was superseded the same day**
     by the ELF: `kind` is only a coarse public/team flag and the *digit* is the channel, with four
     channels not two. See the field notes below.
  2. **The `/all` and `/team` prefixes are stripped client-side.** Only the message body reaches
     the wire — the server never sees the command word, so it must not try to parse one.
  3. **`blob` is not opaque**: one ASCII digit, then the message text NUL-terminated and
     zero-padded to fill the 128 bytes. Decomposed below; the total stays 129 bytes.

  Reply `0x4401` carries the chat line back for display and **must be fanned out to every player in
  the game, the sender included** — the client has no local echo (`0xCA0A98`). See
  `mgo2_cmd_4401_s2c.ksy`. Observed live: with no handler, the message silently vanished, the
  sender's own line never rendered, and the session continued — so an unanswered `0x4400` loses the
  message rather than stalling immediately.
doc-ref: dev/docs/OBSERVED.md "0x4400 — in-game chat"
seq:
  - id: kind
    type: u1
    doc: |
      Coarse public/team flag, **not the channel**. `0` for channel digits 0, 2 and 3; `1` for
      digit 1 ([ELF 0xCA0A70, 0xCA0B30-0xCA0B48]). The four captures only exercised channels 0 and
      1, where this coincides with the digit — see `channel_digit` below, and OBSERVED.md for why
      that made it look like a duplicate. First argument to the builder, written verbatim with no
      validation ([ELF 0xD52D7C]).
  - id: blob
    size: 128
    type: chat_body
    doc: "0x01-0x80. Raw 128-byte copy of the caller's buffer ([ELF 0xD5D0AC], `r5=128`). Substructure below is [CAPTURE]-derived, not visible in the builder."
types:
  chat_body:
    seq:
      - id: channel_digit
        type: u1
        doc: |
          **The channel**, as an ASCII digit. `'0'` to `'3'` are built by the send path
          ([ELF 0xCA0A10-0xCA0B48]); the receiving client computes `digit - 0x30`
          ([ELF 0xC9FF94]) and takes the text from the byte after it ([ELF 0xC9FFEC]).
          Channel 3 resolves speakers against a server-supplied table at `netctx+0xD928` rather
          than the game roster ([ELF 0xCA00CC]) — clan or friends, [UNKNOWN] which.

          This matched `0x30 + kind` in 4 of 4 captures and was recorded as a tracking
          relationship pending a divergence test. The ELF supplied the divergence: they part
          company at channels 2 and 3, which the captures never reached. **Relay this byte, do not
          regenerate it from `kind`.**
      - id: text
        type: strz
        encoding: ISO-8859-1
        doc: |
          [CAPTURE 2026-07-26] The message body, NUL-terminated, the remainder of the 128 bytes
          zero-padded. The sender copies at most `0x80` bytes of typed text one byte past the digit
          ([ELF 0xCA0A10-0xCA0A94]) and the receiving consumer takes `strncpy(dst, payload+5,
          0x7F)` ([ELF 0xC9FFEC]), so **127 bytes survive both ends**. The client's own input-box
          limit is [UNKNOWN] and untested. Charset is [INFERRED] ISO-8859-1 from the byte-per-char
          ASCII seen and from every other text field in this protocol — no non-ASCII message has
          been sent.
