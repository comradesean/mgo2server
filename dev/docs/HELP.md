# The help / TIPS panel

The panel that opens over a screen with a title, a body, a page counter and L1/R1 to page through
it. **It is not a lobby command.** No id in the TCP protocol carries it; the client fetches a plain
text document over HTTP, per topic, and parses two tags out of it.

That is worth stating plainly because two features were misdiagnosed as lobby data before this was
traced. Community Support was assumed to be a `0x4bxx` or `0x49xx` command and is a document
(`1_25`). The Personal Data tips panel was assumed to be the **news list**, and every news row was
replaced to test it — which changed nothing, because the panel was showing the probe's fallback stub
for a path we did not serve.

## The URL

Format string `%shelp/%d_%d.txt` at `0xE0B6A0`, built at `0x7F8E50`, with a **single call site** at
`0x887208`. The two numbers are a **category** and a **topic id**, so the request is:

```
GET http://<web host>/us/mgo2/help/<category>_<id>.txt
```

Our copies live in `dev/runtime/www/us/mgo2/help/` and are served as static files like the policy
document (see `SETUP.md`).

The category is not free-form — there are exactly two producers:

| category | comes from | address |
| --- | --- | --- |
| `0` | `OpenHelp(id)`, an explicit call with the topic id | `0x88616C` |
| `1` | a **per-screen context id**, set from game data rather than passed in | `0x886010` |

Known topics, correlated live by matching the probe's access log against the screen being opened.
**Eighteen are served as of 2026-07-30**; the screen identification is tier 2 (observed request),
the body text of each is ours.

| document | screen | body |
| --- | --- | --- |
| `1_5.txt` | Register Character | written |
| `1_9.txt` | Automatching Lobby | written |
| `1_10.txt` | Free Battle | placeholder |
| `1_11.txt` | Training | placeholder |
| `1_24.txt` | Clan | placeholder |
| `1_25.txt` | **Edit Emblem** | placeholder |
| `1_27.txt` | Edit Clan Notice | placeholder |
| `1_30.txt` | Personal Data | written |
| `1_31.txt` | Appearance Settings | placeholder |
| `1_33.txt` | Friend List | placeholder |
| `1_34.txt` | Block List | placeholder |
| `1_37.txt` | Photo Album | placeholder |
| `1_39.txt` | Automatching Lobby | written |
| `1_43.txt` | Game Name | placeholder |
| `1_45.txt` | Drebin Points | placeholder |
| `1_48.txt` | Novice Training | placeholder |
| `1_49.txt` | Join Combat Training | placeholder |
| `1_50.txt` | Combat Training | placeholder |

**`1_25` was recorded here as Community Support** from the 2026-07-27 correlation, and is Edit
Emblem. Corrected 2026-07-30 (operator-confirmed). Two consequences worth carrying forward:

- The **Konami-disclaimer text** that file used to hold — private non-commercial revival, not
  operated by or affiliated with Konami, contact the operator — **is now in no document at all**.
  If that statement should appear somewhere, it needs a home and an id.
- **Which id Community Support actually uses is once again unknown.** The access log names every
  document the client asks for, so opening that screen answers it in one request.

`1_9` and `1_39` are byte-identical Automatching Lobby documents. Two ids reaching the same screen
is expected — category-1 ids come from a per-screen context value in game data (`0x886010`), and
nothing says that mapping is injective.

## The document format

Parser `0x886BCC`. It understands **exactly two tags**, and nothing else:

| tag | effect |
| --- | --- |
| `<title>...</title>` | fills the panel's title node |
| `<page-break>` | emits a literal `0x0C` byte into the body |

Everything else is body text, verbatim. There is no markup, no escaping and no attribute parsing —
an unrecognised angle bracket is just text.

**Pages are split on the `0x0C` byte, and the page counter is `page-breaks + 1`, parsed from the
document.** This is the part that matters operationally: the counter and the L1/R1 affordance are
properties of the *file*, not of the request. Serving one page per file — which is what we did
first — yields a document with zero page-breaks, so the panel renders a single page with no counter
and no L1/R1, which is exactly the symptom that was observed.

Limits enforced by the parser:

- a page caps at **2048 bytes**; leading whitespace on each page is trimmed
- **16 pages maximum**
- the document must contain **no NUL bytes**
- the whole document must be **≤ 32768 bytes**

## What the server can and cannot choose

- **Ours:** the title node, the body text, and how many pages there are.
- **Not ours: the panel's caption.** It is lobby string **1011** for category 1 and **1010** for
  category 0, selected **by category alone** — no field in the document reaches it. The server
  cannot change the word "TIPS".

That split is worth keeping straight because it is a *presentation* claim in the sense `CLAUDE.md`
uses, and it has been checked against the binary rather than assumed.

## Example

```
<title>REGISTER CHARACTER</title>
Before you can begin playing the game,
you need to create your character.
<page-break>
This will be your alter ego in
the METAL GEAR ONLINE world,
so think carefully about what kind of
character you want.
```

Two pages, counter reads 1/2, L1/R1 active, caption "TIPS", title "REGISTER CHARACTER".

## Open

Which topic ids exist beyond the three above is unenumerated. `0x886010` reads the category-1 id
out of game data per screen, so the full set is discoverable from that table rather than by
guessing — and in the meantime the HTTP access log names every document the client asks for, which
is how these three were found.
