# Client error codes and their messages

The client turns a server error code into an on-screen message through a table it carries
itself. Nothing about that is guessable — sending a code that is *nearly* right produces a
confidently wrong sentence, which is how we spent a session telling players their clan could not
be found when the emblem was merely on cooldown.

This document is generated from the retail binary. Regenerate with
`dev/tools/dump_error_table.py`.

## How a code becomes a sentence

```
server sends result code
  -> per-op error block in the dispatcher     (0xA7DCEC-0xA7E9A8, and near-identical copies)
  -> dialogId                                  chosen by an explicit `cmpwi` chain
  -> 0x885A08(dialogId, code, ctx)             raises the dialog
  -> 0xB8F988                                  linear-scans the table at 0x106D714
  -> {u32 dialogId, i32 ordinal}               664 entries; ordinal -1 marks a section
  -> 0x240708(groupHash, ordinal)              fetches the string
```

Sections below 32 resolve against `MGO_ERROR_RES_LOBBY` (name at `0xE1FD30`), whose strings are
registered in the lobby script `scenerio.gcl` as `-s[1d914] [3d915] $strres:21368 $strres:21898`:
control base **21368**, text base **21898**. A control entry is
`06 <groupHash LE24> 06|0d <itemHash LE24>` followed by six per-language offsets
(`0xC0|n` for n < 64, `01 <u16 LE>`, or `02 <u8>`).

Entries come in two shapes, and the difference is not visible in their structure: some carry a
Japanese variant first, so the order is JP, EN, FR, DE, IT, ES; others begin at English, giving
EN, FR, DE, IT, ES. Reading slot 1 unconditionally puts French in about a third of the table, so
the generator skips slot 0 only when it is Japanese. So

```
stringId(EN) = 21898 + <the English slot> of control file (21368 + ordinal)
```

**Positive control.** Character creation replies `-260`, which the dispatcher maps to dialog 2626,
table index 177, ordinal 148, control file 21516, EN offset 811, string **22709** — *"Desired
character name is already in use."* That is exactly what the client shows, so the chain is proved
rather than assumed.

## Codes worth sending

Recovered from the dispatcher's `cmpwi` chains. These are the client's own codes: send them
raw, not masked with `GameError.MASK`.


### `0x4b01` — create clan  <sub>0xA7E680</sub>

| code | string | message |
| --- | --- | --- |
| `-1206` | 24018 | Conditions to create clan have not been met.\nUnable to create clan. |
| `-1200` | 23994 | A clan with that name already exists.\nUnable to create clan. |
| `-1230` | 24036 | You are currently banned from creating a clan.\nUnable to create clan. |
| `-1231` | 24012 | Comment contains an invalid word.\nUnable to create clan. |
| `-1233` | 24006 | Clan name contains an invalid character or word.\nUnable to create clan. |
| `-262` | 24006 | Clan name contains an invalid character or word.\nUnable to create clan. |
| `-160` | 24030 | A network server error has occurred.\nUnable to create clan. |
| `-24` | 24000 | Clan name is not long enough.\nUnable to create clan. |

### `0x4b05` — disband clan  <sub>0xA7E74C</sub>

| code | string | message |
| --- | --- | --- |
| `-1205` | 24340 | A fixed amount of time must pass in order to disband the clan.\nUnable to disband clan. |
| `-1207` | — | _(dialogId not recovered)_ |
| `-1203` | — | _(dialogId not recovered)_ |

### `0x4b51` — set clan emblem  <sub>0xA7E410</sub>

| code | string | message |
| --- | --- | --- |
| `-1216` | 24382 | A fixed amount of time must pass in order for the emblem to be updated. |
| `-1215` | 24065 | Use of the clan emblem is currently forbidden. |
| `-1218` | 24415 | You do not have emblem editing rights. |
| `-1207` | 23970 | Unable to locate designated clan. |
| `-160` | 24406 | A network server error has occurred.\nUnable to update clan emblem. |

### `0x4b43` — apply to join clan  <sub>0xA7E43C</sub>

Recovered by hand from the disassembly, 2026-07-27. The block is **total** — it ends in a
catch-all, so every result code produces a sentence.

| code | string | message |
| --- | --- | --- |
| `-1217` | 24131 | This clan is already full.\nUnable to apply to join clan. |
| `-1201` | 24143 | You are already a member of another clan.\nUnable to apply to join clan. |
| `-1207` | 24155 | Unable to locate designated clan, or clan may be disbanded.\nUnable to apply to join clan. |
| `-160` | 24107 | A network server error has occurred.\nUnable to apply to join clan. |
| _(any other)_ | 24101 | Unable to apply to join clan. |

**Five of this screen's sentences cannot be reached through a result code.** DialogIds 6454,
6455, 6456, 6458 and 6460 are never loaded into `r3` anywhere in the binary — including *"A fixed amount of time must pass in
order to apply to join a clan."* (6458) and *"You are on the clan leader's Block List."* (6454). No
result code produces them, so a server-side join cooldown or block-list refusal has to settle for
the generic 24101. Carrying the text is not the same as being able to show it; check this table
before designing a refusal around a sentence you found in a string dump.

Note the scope of that claim, because it is narrower than it first reads: it is about the
**result-code path**, which is the only path this server controls. It is not a proof that the
sentences can never appear. `li r22,6458` appears at `0x756438` and `0x758318` inside a large
per-screen struct initializer that installs whole families of dialogIds, so 6458 *is* installed
somewhere as a screen-level message id. Whether a client-side pre-check or some other display
route can raise it was not traced, and until it is, "the server cannot show this" is the honest
statement rather than "the client cannot show this".

Why the generator missed this block, when it read its neighbours: `CODES` is hand-maintained from
reading `cmpwi` chains, and this block is only eight instructions long with just one `li` inside
it. `bgt cr7,0xA7E924` sends everything above `-1207` to a continuation 0x4E0 bytes away, past
several other operations; `-1217`'s `li` lives in a shared trampoline pool at `0xA7E7A0`; and
`-160` takes two hops through `0xA7E808`, itself shared with the mail block. Automating this needs
a real CFG walk from each block entry to the `0x885A08` tail — and it should record each block's
default path, which the hand-maintained list omits everywhere.

### `0x4801` — send mail (per recipient)  <sub>0x8EFD40</sub>

| code | string | message |
| --- | --- | --- |
| `-830` | 23809 | The receiver has blocked incoming mail. |
| `-810` | — | _(dialogId not recovered)_ |
| `-801` | — | _(dialogId not recovered)_ |
| `-802` | — | _(dialogId not recovered)_ |
| `-831` | — | _(dialogId not recovered)_ |
| `-832` | — | _(dialogId not recovered)_ |
| `-1230` | — | _(dialogId not recovered)_ |

### `0x3103` — delete character  <sub>0x94F60C</sub>

| code | string | message |
| --- | --- | --- |
| `-268` | 22787 | A fixed amount of time must pass in order to delete a character.\nUnable to delete character. |
| `-1212` | 22769 | You are the leader of a clan.\nEither disband the clan or assign another character as leader. |
| `-241` | 22733 | This character cannot currently be used. |
| `-260` | 22709 | Desired character name is already in use.\nUnable to register character. |

## The full table

Every entry whose section resolves to `MGO_ERROR_RES_LOBBY`. The dialogId is what the
dispatcher selects; the string is what the player reads.

| dialogId | ordinal | string | message |
| --- | --- | --- | --- |
| 0 | 0 | 21900 | Error |
| 1 | 1 | 21905 | An error has occurred. |
| 2 | 2 | 21911 | A network error has occurred. |
| 3 | 3 | 21917 | A network server error has occurred. |
| 16 | 4 | 21923 | Improper data. |
| 17 | 5 | 21929 | Improper parameter. |
| 18 | 6 | 21935 | Conflict with information on server. |
| 19 | 7 | 21941 | Improper data.\nUnable to communicate with server. |
| 20 | 8 | 21947 | Improper parameter.\nUnable to communicate with server. |
| 21 | 9 | 21953 | Conflict with information on server.\nUnable to communicate with server. |
| 128 | 10 | 21959 | A compatible device is not properly connected to your PS3™ system. |
| 129 | 11 | 21965 | Disconnected from the network. |
| 261 | 12 | 21899 |  |
| 262 | 13 | 21899 |  |
| 268 | 14 | 21973 | Unable to read game settings data. |
| 269 | 15 | 21899 |  |
| 275 | 16 | 21899 |  |
| 384 | 17 | 21979 | System cache has been corrupted.\nPress the PS button and quit the game. |
| 516 | 14 | 21973 | Unable to read game settings data. |
| 517 | 18 | 21899 |  |
| 522 | 19 | 21899 |  |
| 523 | 20 | 21987 | Unable to save game settings data. |
| 527 | 20 | 21987 | Unable to save game settings data. |
| 768 | 34 | 21899 |  |
| 1285 | 12 | 21899 |  |
| 1286 | 13 | 21899 |  |
| 1293 | 12 | 21899 |  |
| 1294 | 35 | 21899 |  |
| 1301 | 36 | 21899 |  |
| 1303 | 37 | 21899 |  |
| 1304 | 38 | 22074 | Unable to connect to network. |
| 1305 | 38 | 22074 | Unable to connect to network. |
| 1306 | 39 | 21899 |  |
| 1307 | 40 | 22081 | A network cable is not connected.\nUnable to connect to network. |
| 1308 | 41 | 22087 | Network connection has been canceled. |
| 1309 | 65 | 22213 | Disconnected from the network.\nReturning to Title Screen. |
| 1310 | 66 | 22219 | Unable to connect to server.\nReturning to Title Screen. |
| 1682 | 42 | 22093 | Unable to conduct UDP Port check. |
| 1683 | 43 | 22099 | Cannot "Create Game" with the current network environment. |
| 1792 | 44 | 22105 | Unable to connect to server. |
| 1793 | 44 | 22105 | Unable to connect to server. |
| 1794 | 44 | 22105 | Unable to connect to server. |
| 1795 | 3 | 21917 | A network server error has occurred. |
| 1796 | 3 | 21917 | A network server error has occurred. |
| 1797 | 3 | 21917 | A network server error has occurred. |
| 1798 | 44 | 22105 | Unable to connect to server. |
| 1799 | 44 | 22105 | Unable to connect to server. |
| 1800 | 11 | 21965 | Disconnected from the network. |
| 1801 | 21 | 21993 | Security certificate has either expired or has not been enabled.\n(Your PS3™ system clock may not be set correctly.) |
| 1802 | 22 | 21999 | Security certificate has either expired or has not been enabled.\n(Your PS3™ system clock may not be set correctly.)\nContinue connecting? |
| 1803 | 23 | 22004 | Security certificate has either expired or has not been enabled.\n(Your PS3™ system clock may not be set correctly.)\nContinue processing? |
| 1808 | 61 | 22204 | This game cannot be played without agreeing to the Terms of Use. |
| 1824 | 86 | 22339 | Your use of some of the game's services is currently limited. |
| 1840 | 24 | 22010 | You cannot use the chat services because of the parental control restrictions set on your PLAYSTATION®Network account. |
| 1841 | 25 | 22016 | You cannot use the voice chat services because of the parental control restrictions set on your PLAYSTATION®Network account. |
| 1842 | 26 | 22022 | You cannot use preset codec messages because of the parental control restrictions set on your PLAYSTATION®Network account. |
| 1843 | 27 | 22028 | You cannot use the mail services because of the parental control restrictions set on your PLAYSTATION®Network account. |
| 1844 | 28 | 22034 | You cannot use some services because of the parental control restrictions set on your PLAYSTATION®Network account. |
| 1845 | 29 | 22040 | You cannot use some communication services because of the parental control restrictions set on your PLAYSTATION®Network account. |
| 1846 | 30 | 22046 | You cannot use the online service because\nof the parental control restrictions set on your PLAYSTATION®Network account. |
| 1847 | 31 | 22052 | You have signed out from the\nPLAYSTATION®Network. |
| 1856 | 32 | 22058 | Unable to save game data. |
| 1857 | 33 | 22064 | Unable to load game data. |
| 2048 | 45 | 22109 | GAME ID is not long enough.\nGAME IDs must be between 8 and 32 characters. |
| 2049 | 46 | 22115 | Password is not long enough.\nPasswords must be between 4 and 16 characters. |
| 2050 | 46 | 22115 | Password is not long enough.\nPasswords must be between 4 and 16 characters. |
| 2051 | 47 | 22121 | Current password is not long enough.\nPasswords must be between 6 and 15 characters.\n |
| 2052 | 48 | 22127 | New password is not long enough.\nPasswords must be between 6 and 15 characters. |
| 2053 | 49 | 22133 | The new password you have entered is the same as your current password.\nEnter a password different from your current password. |
| 2054 | 50 | 22139 | New password confirmation does not match.\nPlease type the same password in both boxes. |
| 2058 | 53 | 22156 | Unable to change password. |
| 2059 | 21 | 21993 | Security certificate has either expired or has not been enabled.\n(Your PS3™ system clock may not be set correctly.) |
| 2071 | 53 | 22156 | Unable to change password. |
| 2072 | 54 | 22162 | The Account ID or current password is incorrect.\nUnable to change password. |
| 2073 | 46 | 22115 | Password is not long enough.\nPasswords must be between 4 and 16 characters. |
| 2077 | 55 | 22168 | Unable to delete Account ID. |
| 2078 | 21 | 21993 | Security certificate has either expired or has not been enabled.\n(Your PS3™ system clock may not be set correctly.) |
| 2089 | 55 | 22168 | Unable to delete Account ID. |
| 2090 | 56 | 22174 | The Account ID or password is incorrect.\nUnable to delete account. |
| 2091 | 45 | 22109 | GAME ID is not long enough.\nGAME IDs must be between 8 and 32 characters. |
| 2092 | 46 | 22115 | Password is not long enough.\nPasswords must be between 4 and 16 characters. |
| 2093 | 51 | 22145 | Password confirmation does not match.\nPlease type the same password in both boxes. |
| 2094 | 52 | 22150 | Character name is not long enough.\nNames must be between 3 and 15 characters. |
| 2098 | 57 | 22180 | Unable to create account. |
| 2099 | 21 | 21993 | Security certificate has either expired or has not been enabled.\n(Your PS3™ system clock may not be set correctly.) |
| 2112 | 57 | 22180 | Unable to create account. |
| 2113 | 58 | 22186 | Player name contains an invalid character or word. \nUnable to create account. |
| 2114 | 59 | 22192 | Desired Account ID is already in use.\nUnable to create account. |
| 2115 | 60 | 22198 | Desired character name is already in use.\nUnable to create account. |
| 2116 | 11 | 21965 | Disconnected from the network. |
| 2117 | 110 | 22481 | GAME ID and character name are identical.\nEnter separate names for GAME ID and character name. |
| 2118 | 77 | 22285 | GAME ID has been locked due to 3 unsuccessful password entries.\nYou will not be able to login temporarily. |
| 2119 | 79 | 22297 | This GAME ID cannot currently be used. |
| 2120 | 84 | 22327 | Someone is currently logged in with this GAME ID. |
| 2121 | 180 | 22901 | Unable to acquire character information. |
| 2122 | 181 | 22907 | A network server error has occurred.\nUnable to acquire character information. |
| 2128 | 62 | 21899 |  |
| 2129 | 63 | 21899 |  |
| 2130 | 64 | 21899 |  |
| 2131 | 78 | 22291 | Visit the KONAMI ID Portal (https://id.konami.net) and select "Unlock GAME ID". You may also change your password here. |
| 2304 | 11 | 21965 | Disconnected from the network. |
| 2305 | 44 | 22105 | Unable to connect to server. |
| 2306 | 3 | 21917 | A network server error has occurred. |
| 2307 | 3 | 21917 | A network server error has occurred. |
| 2309 | 3 | 21917 | A network server error has occurred. |
| 2310 | 3 | 21917 | A network server error has occurred. |
| 2311 | 3 | 21917 | A network server error has occurred. |
| 2312 | 44 | 22105 | Unable to connect to server. |
| 2313 | 67 | 22225 | Unable to locate the lobby you are trying to jump to.\nUnable to jump. |
| 2314 | 44 | 22105 | Unable to connect to server. |
| 2315 | 44 | 22105 | Unable to connect to server. |
| 2317 | 3 | 21917 | A network server error has occurred. |
| 2318 | 3 | 21917 | A network server error has occurred. |
| 2319 | 44 | 22105 | Unable to connect to server. |
| 2320 | 68 | 22231 | Unable to login to server. |
| 2321 | 69 | 22237 | The GAME ID or password is incorrect.\nUnable to login to server. |
| 2322 | 70 | 22243 | Someone has already logged in using this GAME ID.\nUnable to login to server. |
| 2323 | 3 | 21917 | A network server error has occurred. |
| 2324 | 3 | 21917 | A network server error has occurred. |
| 2325 | 3 | 21917 | A network server error has occurred. |
| 2327 | 3 | 21917 | A network server error has occurred. |
| 2328 | 3 | 21917 | A network server error has occurred. |
| 2330 | 3 | 21917 | A network server error has occurred. |
| 2331 | 3 | 21917 | A network server error has occurred. |
| 2332 | 44 | 22105 | Unable to connect to server. |
| 2333 | 72 | 22255 | Lobby is full.\nUnable to connect to lobby. |
| 2334 | 71 | 22249 | Unable to connect to lobby. |
| 2335 | 73 | 22261 | Lobby is full.\nUnable to jump. |
| 2336 | 74 | 22267 | Unable to connect to lobby.\nUnable to jump. |
| 2337 | 71 | 22249 | Unable to connect to lobby. |
| 2338 | 74 | 22267 | Unable to connect to lobby.\nUnable to jump. |
| 2339 | 71 | 22249 | Unable to connect to lobby. |
| 2340 | 75 | 22273 | You must login again to connect to the lobby.\nPlease disconnect from the network. |
| 2341 | 71 | 22249 | Unable to connect to lobby. |
| 2342 | 74 | 22267 | Unable to connect to lobby.\nUnable to jump. |
| 2343 | 3 | 21917 | A network server error has occurred. |
| 2344 | 3 | 21917 | A network server error has occurred. |
| 2345 | 3 | 21917 | A network server error has occurred. |
| 2346 | 3 | 21917 | A network server error has occurred. |
| 2347 | 3 | 21917 | A network server error has occurred. |
| 2348 | 71 | 22249 | Unable to connect to lobby. |
| 2349 | 74 | 22267 | Unable to connect to lobby.\nUnable to jump. |
| 2350 | 71 | 22249 | Unable to connect to lobby. |
| 2351 | 74 | 22267 | Unable to connect to lobby.\nUnable to jump. |
| 2352 | 71 | 22249 | Unable to connect to lobby. |
| 2353 | 44 | 22105 | Unable to connect to server. |
| 2354 | 11 | 21965 | Disconnected from the network. |
| 2355 | 76 | 22279 | You cannot login to this lobby. |
| 2561 | 3 | 21917 | A network server error has occurred. |
| 2562 | 89 | 22356 | Unable to acquire online news. |
| 2563 | 90 | 22362 | A network server error has occurred.\nUnable to acquire online news. |
| 2568 | 91 | 22368 | Unable to download messages from the server. |
| 2569 | 91 | 22368 | Unable to download messages from the server. |
| 2570 | 91 | 22368 | Unable to download messages from the server. |
| 2571 | 91 | 22368 | Unable to download messages from the server. |
| 2572 | 91 | 22368 | Unable to download messages from the server. |
| 2573 | 91 | 22368 | Unable to download messages from the server. |
| 2576 | 3 | 21917 | A network server error has occurred. |
| 2592 | 3 | 21917 | A network server error has occurred. |
| 2593 | 3 | 21917 | A network server error has occurred. |
| 2624 | 146 | 22697 | Unable to register character. |
| 2625 | 147 | 22703 | A network server error has occurred.\nUnable to register character. |
| 2626 | 148 | 22709 | Desired character name is already in use.\nUnable to register character. |
| 2627 | 147 | 22703 | A network server error has occurred.\nUnable to register character. |
| 2628 | 149 | 22715 | Character name contains an invalid character or word. \nUnable to register character. |
| 2629 | 150 | 22721 | Unable to select character. |
| 2630 | 151 | 22727 | A network server error has occurred.\nUnable to select character. |
| 2631 | 150 | 22721 | Unable to select character. |
| 2640 | 152 | 22733 | This character cannot currently be used. |
| 2641 | 156 | 22757 | You are currently banned from registering a character.\nUnable to register character. |
| 2656 | 159 | 22775 | Unable to delete character. |
| 2657 | 160 | 22781 | A network server error has occurred.\nUnable to delete character. |
| 2658 | 158 | 22769 | You are the leader of a clan.\nEither disband the clan or assign another character as leader. |
| 2659 | 161 | 22787 | A fixed amount of time must pass in order to delete a character.\nUnable to delete character. |
| 2660 | 152 | 22733 | This character cannot currently be used. |
| 2672 | 164 | 22805 | Unable to purchase character. |
| 2673 | 165 | 22811 | A network server error has occurred.\nUnable to purchase character. |
| 2674 | 163 | 22799 | You do not have enough Metal Gear Points. |
| 2675 | 167 | 22823 | You do not have enough Metal Gear Points. %d points are needed to make purchase. |
| 2676 | 3 | 21917 | A network server error has occurred. |
| 2677 | 3 | 21917 | A network server error has occurred. |
| 2816 | 92 | 22374 | Unable to connect to host. |
| 2817 | 92 | 22374 | Unable to connect to host. |
| 2818 | 92 | 22374 | Unable to connect to host. |
| 2819 | 93 | 22380 | Maximum number of characters already reached.\nUnable to connect to host. |
| 2820 | 94 | 22386 | Password is incorrect.\nUnable to connect to host. |
| 2821 | 92 | 22374 | Unable to connect to host. |
| 2822 | 92 | 22374 | Unable to connect to host. |
| 2823 | 92 | 22374 | Unable to connect to host. |
| 2824 | 92 | 22374 | Unable to connect to host. |
| 2825 | 92 | 22374 | Unable to connect to host. |
| 2826 | 114 | 22505 | You do not own the map this host is using.\nUnable to connect to host. |
| 2827 | 120 | 22541 | You do not meet the criteria for connecting to this host.\nUnable to connect to host. |
| 2828 | 122 | 22553 | You cannot connect to this host due to your Level. |
| 2829 | 125 | 22571 | Unable to acquire game list. |
| 2830 | 126 | 22577 | A network server error has occurred.\nUnable to acquire game list. |
| 2831 | 128 | 22589 | Unable to acquire host information. |
| 2832 | 129 | 22595 | A network server error has occurred.\nUnable to acquire host information. |
| 2833 | 130 | 22601 | This Combat Training session is not currently\naccepting applicants. |
| 2944 | 96 | 22398 | Game rules and map have not been set.\nPlease set game rules and map. |
| 2945 | 111 | 22487 | Other characters will not be able to join if you "Create Game" with the current network environment. |
| 3073 | 3 | 21917 | A network server error has occurred. |
| 3074 | 109 | 22475 | Designated character has been deleted and no longer exists. |
| 3075 | 3 | 21917 | A network server error has occurred. |
| 3088 | 131 | 22607 | Search field does not contain enough characters.\nField text must be between 3 and 15 characters. |
| 3089 | 132 | 22613 | Too many search results have been found. Only a portion of the results will be shown.\n |
| 3090 | 133 | 22619 | Unable to locate that character. |
| 3091 | 134 | 22625 | Unable to search for character. |
| 3092 | 135 | 22631 | A network server error has occurred.\nUnable to search for character. |
| 3200 | 136 | 22637 | Your Friend List is full.\nErase a registered character before adding. |
| 3201 | 137 | 22643 | Your Block List is full.\nErase a registered character before adding. |
| 3202 | 141 | 22667 | A network server error has occurred.\nUnable to delete from Block List. |
| 3203 | 141 | 22667 | A network server error has occurred.\nUnable to delete from Block List. |
| 3204 | 141 | 22667 | A network server error has occurred.\nUnable to delete from Block List. |
| 3205 | 138 | 22649 | A network server error has occurred.\nUnable to add to Friend List. |
| 3206 | 138 | 22649 | A network server error has occurred.\nUnable to add to Friend List. |
| 3207 | 138 | 22649 | A network server error has occurred.\nUnable to add to Friend List. |
| 3208 | 139 | 22655 | A network server error has occurred.\nUnable to delete from Friend List. |
| 3209 | 139 | 22655 | A network server error has occurred.\nUnable to delete from Friend List. |
| 3210 | 139 | 22655 | A network server error has occurred.\nUnable to delete from Friend List. |
| 3211 | 140 | 22661 | A network server error has occurred.\nUnable to add to Block List. |
| 3212 | 140 | 22661 | A network server error has occurred.\nUnable to add to Block List. |
| 3213 | 140 | 22661 | A network server error has occurred.\nUnable to add to Block List. |
| 3329 | 3 | 21917 | A network server error has occurred. |
| 3330 | 3 | 21917 | A network server error has occurred. |
| 3331 | 3 | 21917 | A network server error has occurred. |
| 3332 | 3 | 21917 | A network server error has occurred. |
| 3333 | 97 | 22404 | Currently, there are no joinable games matching the desired rules. |
| 3334 | 123 | 22559 | Currently, there are no joinable games matching the desired conditions. |
| 3335 | 124 | 22565 | Currently, there are no joinable games matching the desired criteria. |
| 3336 | 127 | 22583 | You are currently banned from creating and joining games. |
| 3584 | 3 | 21917 | A network server error has occurred. |
| 3585 | 3 | 21917 | A network server error has occurred. |
| 3586 | 3 | 21917 | A network server error has occurred. |
| 3587 | 98 | 22410 | Unable to locate the host you are trying to jump to.\nUnable to jump. |
| 3588 | 99 | 22416 | Search field is empty.\nEnter text in the search field. |
| 3590 | 3 | 21917 | A network server error has occurred. |
| 3591 | 108 | 22469 | Too many search results have been found.\nLimit the search criteria and try again. |
| 3592 | 3 | 21917 | A network server error has occurred. |
| 3594 | 3 | 21917 | A network server error has occurred. |
| 3595 | 3 | 21917 | A network server error has occurred. |
| 3596 | 3 | 21917 | A network server error has occurred. |
| 3597 | 3 | 21917 | A network server error has occurred. |
| 3598 | 3 | 21917 | A network server error has occurred. |
| 3599 | 100 | 22422 | Unable to locate host. |
| 3600 | 3 | 21917 | A network server error has occurred. |
| 3601 | 3 | 21917 | A network server error has occurred. |
| 3602 | 3 | 21917 | A network server error has occurred. |
| 3603 | 3 | 21917 | A network server error has occurred. |
| 3604 | 93 | 22380 | Maximum number of characters already reached.\nUnable to connect to host. |
| 3605 | 102 | 22434 | Level restrictions are not satisfied.\nUnable to connect to host. |
| 3606 | 95 | 22392 | You are on the host's Block List.\nUnable to connect to host. |
| 3607 | 94 | 22386 | Password is incorrect.\nUnable to connect to host. |
| 3840 | 3 | 21917 | A network server error has occurred. |
| 3841 | 3 | 21917 | A network server error has occurred. |
| 3842 | 3 | 21917 | A network server error has occurred. |
| 3843 | 103 | 22439 | Game name is not long enough.\nGame names must be between 3 and 15 characters. |
| 3844 | 104 | 22445 | Password Lock is not long enough.\nPassword Locks must be between 3 and 15 characters. |
| 3845 | 105 | 22451 | A network server error has occurred.\nUnable to create game. |
| 3846 | 105 | 22451 | A network server error has occurred.\nUnable to create game. |
| 3847 | 106 | 22457 | Game name contains an invalid character or word. \nUnable to create game. |
| 3848 | 107 | 22463 | Comment contains an invalid word.\nUnable to create game. |
| 3849 | 105 | 22451 | A network server error has occurred.\nUnable to create game. |
| 3850 | 105 | 22451 | A network server error has occurred.\nUnable to create game. |
| 3851 | 105 | 22451 | A network server error has occurred.\nUnable to create game. |
| 3852 | 105 | 22451 | A network server error has occurred.\nUnable to create game. |
| 4096 | 142 | 22673 | Unable to acquire Friend List. |
| 4097 | 143 | 22679 | A network server error has occurred.\nUnable to acquire Friend List. |
| 4098 | 142 | 22673 | Unable to acquire Friend List. |
| 4099 | 144 | 22685 | Unable to acquire Block List. |
| 4100 | 145 | 22691 | A network server error has occurred.\nUnable to acquire Block List. |
| 4101 | 144 | 22685 | Unable to acquire Block List. |
| 4128 | 172 | 22853 | Unable to update skills. |
| 4129 | 173 | 22859 | A network server error has occurred.\nUnable to update skills. |
| 4130 | 172 | 22853 | Unable to update skills. |
| 4144 | 174 | 22865 | Unable to update character information. |
| 4145 | 175 | 22871 | A network server error has occurred.\nUnable to update character information. |
| 4146 | 176 | 22877 | Unable to acquire match history.  |
| 4147 | 177 | 22883 | A network server error has occurred.\nUnable to acquire match history.  |
| 4148 | 178 | 22889 | Unable to acquire Tournament/Survival history. |
| 4149 | 179 | 22895 | A network server error has occurred.\nUnable to acquire Tournament/Survival history.  |
| 4150 | 180 | 22901 | Unable to acquire character information. |
| 4151 | 181 | 22907 | A network server error has occurred.\nUnable to acquire character information. |
| 4152 | 182 | 22913 | Character comment contains an invalid word.\nUnable to acquire character information. |
| 4153 | 183 | 22919 | You do not currently own any gear in the selected category. |
| 4154 | 109 | 22475 | Designated character has been deleted and no longer exists. |
| 4367 | 3 | 21917 | A network server error has occurred. |
| 4384 | 170 | 22841 | Unable to acquire ranking data. |
| 4385 | 171 | 22847 | A network server error has occurred.\nUnable to acquire ranking data. |
| 4609 | 3 | 21917 | A network server error has occurred. |
| 4610 | 3 | 21917 | A network server error has occurred. |
| 4864 | 198 | 23009 | Unable to acquire list showing information on games in progress. |
| 4865 | 199 | 23015 | A network server error has occurred.\nUnable to acquire list showing information on games in progress. |
| 4866 | 200 | 23021 | Unable to acquire information on games in progress. |
| 4867 | 201 | 23027 | A network server error has occurred.\nUnable to acquire information on games in progress. |
| 4868 | 202 | 23033 | This game is currently not available. |
| 4869 | 203 | 23039 | This game is currently not open. |
| 4870 | 204 | 23045 | Unable to acquire lobby information. |
| 4871 | 205 | 23051 | A network server error has occurred.\nUnable to acquire lobby information. |
| 4880 | 194 | 22985 | Training Mode is currently not available. |
| 4881 | 195 | 22991 | Training Mode is currently not open. |
| 4882 | 196 | 22997 | Combat Training is currently not available. |
| 4883 | 197 | 23003 | Combat Training is currently not open. |
| 4928 | 184 | 22925 | Automatching is currently not available. |
| 4929 | 185 | 22931 | Automatching is currently not open. |
| 4930 | 186 | 22937 | Unable to start automatching. |
| 4931 | 187 | 22943 | A network server error has occurred.\nUnable to start automatching. |
| 4932 | 188 | 22949 | Unable to cancel automatching. |
| 4933 | 189 | 22955 | A network server error has occurred.\nUnable to cancel automatching. |
| 4934 | 190 | 22961 | Unable to find opponent. |
| 4944 | 191 | 22967 | Unable to create game for automatching. |
| 4945 | 192 | 22973 | The host was unable to create game for automatching. |
| 4946 | 193 | 22979 | Unable to connect to game for automatching. |
| 5120 | 210 | 23081 | Unable to create team. |
| 5121 | 211 | 23087 | A network server error has occurred.\nUnable to create team. |
| 5122 | 210 | 23081 | Unable to create team. |
| 5123 | 212 | 23093 | Team name is not long enough.\nTeam names must be between 3 and 15 characters. |
| 5124 | 213 | 23099 | Team name contains an invalid character or word.\nUnable to create team. |
| 5125 | 214 | 23105 | Comment contains an invalid word.\nUnable to create team. |
| 5136 | 215 | 23111 | Unable to change rules. |
| 5137 | 216 | 23117 | A network server error has occurred.\nUnable to change rules. |
| 5138 | 215 | 23111 | Unable to change rules. |
| 5139 | 230 | 23201 | Unable to change team's clan affiliation settings. |
| 5140 | 231 | 23207 | A network server error has occurred.\nUnable to change team's clan affiliation settings. |
| 5141 | 232 | 23213 | Your use of some clan service features is currently limited.\nUnable to change team's clan affiliation settings. |
| 5142 | 233 | 23219 | You are not a clan member.\nUnable to change team's clan affiliation settings. |
| 5143 | 217 | 23123 | Unable to kick player. |
| 5144 | 218 | 23129 | A network server error has occurred.\nUnable to kick player. |
| 5145 | 219 | 23135 | Designated character is not on the team.\nUnable to kick. |
| 5146 | 217 | 23123 | Unable to kick player. |
| 5147 | 220 | 23141 | Unable to select whether to approve/disapprove entry.  |
| 5148 | 221 | 23147 | A network server error has occurred.\nUnable to select whether to approve/disapprove entry.  |
| 5149 | 222 | 23153 | Team has already confirmed entry.\nUnable to select whether to approve/disapprove entry.  |
| 5150 | 223 | 23159 | Not enough Metal Gear Points.\nUnable to approve entry. |
| 5151 | 220 | 23141 | Unable to select whether to approve/disapprove entry.  |
| 5152 | 224 | 23165 | You have already left the team.\nUnable to select whether to approve/disapprove entry.  |
| 5153 | 225 | 23171 | Unable to confirm entry. |
| 5154 | 226 | 23177 | A network server error has occurred.\nUnable to confirm entry. |
| 5155 | 227 | 23183 | Other players have not approved entry.\nUnable to confirm entry. |
| 5156 | 228 | 23189 | Not enough Metal Gear Points.\nUnable to confirm entry. |
| 5157 | 225 | 23171 | Unable to confirm entry. |
| 5158 | 229 | 23195 | Not enough team members.\nUnable to confirm entry. |
| 5168 | 234 | 23225 | Unable to leave team. |
| 5169 | 235 | 23231 | A network server error has occurred.\nUnable to leave team. |
| 5170 | 236 | 23237 | You have already left the team.\nUnable to leave team. |
| 5171 | 234 | 23225 | Unable to leave team. |
| 5172 | 237 | 23243 | Unable to disband team. |
| 5173 | 238 | 23249 | A network server error has occurred.\nUnable to disband team. |
| 5174 | 239 | 23255 | The team is in battle.\nUnable to disband team. |
| 5175 | 237 | 23243 | Unable to disband team. |
| 5200 | 3 | 21917 | A network server error has occurred. |
| 5201 | 3 | 21917 | A network server error has occurred. |
| 5202 | 3 | 21917 | A network server error has occurred. |
| 5203 | 242 | 23273 | Unable to acquire team information. |
| 5204 | 243 | 23279 | A network server error has occurred.\nUnable to acquire team information. |
| 5205 | 242 | 23273 | Unable to acquire team information. |
| 5206 | 244 | 23285 | Unable to locate team.\nUnable to acquire team information. |
| 5207 | 245 | 23291 | Maximum number of players already reached.\nUnable to join team. |
| 5208 | 246 | 23297 | You are on the team leader's Block List.\nUnable to join team. |
| 5209 | 247 | 23303 | Unable to acquire team leader player information. |
| 5210 | 248 | 23309 | A network server error has occurred.\nUnable to acquire team leader information. |
| 5211 | 247 | 23303 | Unable to acquire team leader player information. |
| 5212 | 249 | 23315 | Unable to join team. |
| 5213 | 250 | 23321 | A network server error has occurred.\nUnable to join team. |
| 5214 | 251 | 23327 | Unable to locate team.\nUnable to join team. |
| 5215 | 252 | 23333 | New members cannot currently join the team.\nUnable to join team. |
| 5216 | 253 | 23339 | Password is incorrect.\nUnable to join team. |
| 5217 | 249 | 23315 | Unable to join team. |
| 5248 | 254 | 23345 | Unable to update team information. |
| 5249 | 255 | 23351 | A network server error has occurred.\nUnable to update team information. |
| 5250 | 256 | 23357 | You have already left the team.\nUnable to update team information. |
| 5251 | 257 | 23363 | Team has already been disbanded.\nUnable to update team information. |
| 5252 | 254 | 23345 | Unable to update team information. |
| 5264 | 271 | 23447 | Unable to acquire game entry information. |
| 5265 | 272 | 23453 | A network server error has occurred.\nUnable to acquire game entry information. |
| 5266 | 271 | 23447 | Unable to acquire game entry information. |
| 5267 | 273 | 23459 | Unable to delete game entry information. |
| 5268 | 274 | 23465 | A network server error has occurred.\nUnable to delete game entry information. |
| 5269 | 273 | 23459 | Unable to delete game entry information. |
| 5270 | 275 | 23471 | Your game entry information was not found on the server.\nUnable to delete game entry information. |
| 5271 | 276 | 23477 | Unable to acquire team entry information. |
| 5272 | 277 | 23483 | A network server error has occurred.\nUnable to acquire team entry information. |
| 5273 | 278 | 23489 | Unable to locate team.\nUnable to acquire team entry information. |
| 5274 | 279 | 23495 | You have already left the team.\nUnable to acquire team entry information. |
| 5275 | 276 | 23477 | Unable to acquire team entry information. |
| 5276 | 280 | 23501 | Unable to rejoin team. |
| 5277 | 281 | 23506 | A network server error has occurred.\nUnable to rejoin team. |
| 5278 | 282 | 23511 | You have already left the team.\nUnable to rejoin team. |
| 5279 | 283 | 23517 | Unable to locate team.\nUnable to rejoin team. |
| 5280 | 280 | 23501 | Unable to rejoin team. |
| 5296 | 206 | 23057 | You do not meet the criteria for joining this team.\nUnable to join team. |
| 5297 | 207 | 23063 | You do not own the map this team is using.\nUnable to join team. |
| 5298 | 209 | 23075 | You cannot join this team due to your Level. |
| 5299 | 288 | 23545 | There are currently no joinable teams that\nmatch your Conditions criteria. |
| 5300 | 289 | 23551 | There are currently no joinable teams that\nmatch your criteria. |
| 5312 | 258 | 23369 | You are currently banned from team competitions.\nUnable to create team. |
| 5313 | 259 | 23375 | You are currently banned from team competitions.\nUnable to join team. |
| 5314 | 261 | 23387 | You are currently unable to use team competition services. |
| 5328 | 264 | 23405 | Unable to start autoteam formation. |
| 5329 | 265 | 23411 | A network server error has occurred.\nUnable to start autoteam formation. |
| 5330 | 266 | 23417 | You are currently banned from team competitions.\nUnable to start autoteam formation. |
| 5331 | 267 | 23423 | Unable to cancel autoteam formation. |
| 5332 | 268 | 23429 | A network server error has occurred.\nUnable to cancel autoteam formation. |
| 5333 | 269 | 23435 | Unable to find players wanting to form autoteam. |
| 5334 | 270 | 23441 | Unable to form autoteam. |
| 5344 | 284 | 23522 | Unable to reply to invite message. |
| 5345 | 285 | 23528 | A network server error has occurred.\nUnable to reply to invite message. |
| 5376 | 292 | 23569 | Unable to cancel Tournament. |
| 5377 | 293 | 23575 | A network server error has occurred.\nUnable to cancel Tournament. |
| 5378 | 294 | 23581 | Tournament has already started.\nUnable to cancel Tournament. |
| 5379 | 292 | 23569 | Unable to cancel Tournament. |
| 5380 | 295 | 23587 | Tournament has already finished.\nUnable to cancel Tournament. |
| 5392 | 290 | 23557 | Tournament is currently not available. |
| 5393 | 291 | 23563 | Tournament is currently not open. |
| 5408 | 296 | 23593 | Unable to acquire Tournament list. |
| 5409 | 297 | 23599 | A network server error has occurred.\nUnable to acquire Tournament list. |
| 5410 | 298 | 23605 | Unable to acquire Tournament information. |
| 5411 | 299 | 23611 | A network server error has occurred.\nUnable to acquire Tournament information. |
| 5412 | 300 | 23617 | Unable to locate designated Tournament.\nUnable to acquire Tournament information. |
| 5413 | 301 | 23623 | An error has occurred in the Tournament. |
| 5414 | 303 | 23635 | Unable to connect to Tournament match. |
| 5415 | 302 | 23629 | Unable to create Tournament match. |
| 5504 | 304 | 23641 | Survival is currently not available. |
| 5505 | 305 | 23647 | Survival is currently not open. |
| 5520 | 306 | 23653 | Unable to acquire Survival list. |
| 5521 | 307 | 23659 | A network server error has occurred.\nUnable to acquire Survival list. |
| 5522 | 308 | 23665 | Unable to cancel Survival. |
| 5523 | 309 | 23671 | A network server error has occurred.\nUnable to cancel Survival. |
| 5524 | 310 | 23677 | An error has occurred in Survival. |
| 5525 | 311 | 23683 | Unable to connect to Survival match. |
| 5526 | 312 | 23689 | Unable to create Survival match. |
| 5888 | 313 | 23695 | You have already applied for entry into this game.\nUnable to create team. |
| 5889 | 314 | 23701 | You have already applied for entry into this game.\nUnable to join team. |
| 5890 | 315 | 23707 | An error has occurred in the Official Tournament. |
| 5891 | 316 | 23713 | Unable to connect to Official Tournament match. |
| 5892 | 317 | 23719 | Unable to create Official Tournament match. |
| 6144 | 318 | 23725 | Unable to acquire mailbox. |
| 6145 | 319 | 23731 | A network server error has occurred.\nUnable to acquire mailbox. |
| 6146 | 318 | 23725 | Unable to acquire mailbox. |
| 6147 | 320 | 23737 | Unable to acquire mail. |
| 6148 | 321 | 23743 | A network server error has occurred.\nUnable to acquire mail. |
| 6149 | 320 | 23737 | Unable to acquire mail. |
| 6150 | 322 | 23749 | Unable to locate designated mail.\nUnable to acquire mail. |
| 6151 | 323 | 23755 | Unable to delete mail. |
| 6152 | 324 | 23761 | A network server error has occurred.\nUnable to delete mail. |
| 6153 | 323 | 23755 | Unable to delete mail. |
| 6154 | 325 | 23767 | Unable to locate designated mail.\nUnable to delete mail. |
| 6155 | 326 | 23773 | Unable to create mail. |
| 6156 | 327 | 23779 | Unable to send mail. |
| 6157 | 328 | 23785 | A network server error has occurred.\nUnable to send mail. |
| 6158 | 329 | 23791 | Improper address entered.\nUnable to send mail. |
| 6159 | 330 | 23797 | Receiver's mailbox is full.\nUnable to send mail. |
| 6160 | 331 | 23803 | You are on the receiver's Block List.\nUnable to send mail. |
| 6161 | 327 | 23779 | Unable to send mail. |
| 6176 | 332 | 23809 | The receiver has blocked incoming mail. |
| 6177 | 333 | 23815 | You are currently unable to use mail services. |
| 6192 | 341 | 23863 | Mail subject contains an invalid word.\nUnable to send mail. |
| 6193 | 342 | 23869 | Mail message contains an invalid word.\nUnable to send mail. |
| 6194 | 343 | 23875 | Mail subject and message contains invalid words.\nUnable to send mail. |
| 6195 | 344 | 23881 | Mail subject field is blank.\nUnable to send mail. |
| 6196 | 345 | 23887 | Mail message field is blank.\nUnable to send mail. |
| 6197 | 346 | 23893 | Mail subject and message fields are blank.\nUnable to send mail. |
| 6272 | 347 | 23899 | You are currently unable to use chat services. |
| 6304 | 355 | 23946 | You are currently unable to use voice chat services. |
| 6400 | 356 | 23952 | You do not meet the criteria for joining this clan.\nUnable to join clan. |
| 6401 | 357 | 23958 | You do not meet the criteria for creating a clan.\nUnable to create clan. |
| 6402 | 358 | 23964 | You cannot join this clan due to your Level. |
| 6403 | 358 | 23964 | You cannot join this clan due to your Level. |
| 6404 | 359 | 23970 | Unable to locate designated clan. |
| 6405 | 360 | 23976 | Designated player has already left clan. |
| 6406 | 362 | 23988 | You are not clan leader. |
| 6407 | 361 | 23982 | You are not a clan member. |
| 6408 | 363 | 23994 | A clan with that name already exists.\nUnable to create clan. |
| 6409 | 364 | 24000 | Clan name is not long enough.\nUnable to create clan. |
| 6410 | 365 | 24006 | Clan name contains an invalid character or word.\nUnable to create clan. |
| 6411 | 366 | 24012 | Comment contains an invalid word.\nUnable to create clan. |
| 6412 | 367 | 24018 | Conditions to create clan have not been met.\nUnable to create clan. |
| 6413 | 368 | 24024 | Unable to create clan. |
| 6414 | 369 | 24030 | A network server error has occurred.\nUnable to create clan. |
| 6415 | 370 | 24036 | You are currently banned from creating a clan.\nUnable to create clan. |
| 6416 | 371 | 24042 | You are currently banned from using clan services. |
| 6417 | 372 | 24048 | You are currently unable to use clan services. |
| 6418 | 373 | 24054 | Your use of some clan services is currently limited. |
| 6419 | 374 | 24060 | Your use of some clan service features is currently limited. |
| 6420 | 375 | 24065 | Use of the clan emblem is currently forbidden. |
| 6421 | 376 | 24071 | Use of the clan emblem is currently limited. |
| 6448 | 377 | 24077 | Unable to acquire clan information. |
| 6449 | 378 | 24083 | A network server error has occurred.\nUnable to acquire clan information. |
| 6450 | 379 | 24089 | Unable to update clan information. |
| 6451 | 380 | 24095 | A network server error has occurred.\nUnable to update clan information. |
| 6452 | 381 | 24101 | Unable to apply to join clan. |
| 6453 | 382 | 24107 | A network server error has occurred.\nUnable to apply to join clan. |
| 6454 | 383 | 24113 | You are on the clan leader's Block List.\nUnable to apply to join clan. |
| 6455 | 384 | 24119 | Clan leader has declined accepting your entry application. |
| 6456 | 385 | 24125 | Clan leader unable to accept your entry application.\nUnable to apply to join clan. |
| 6457 | 386 | 24131 | This clan is already full.\nUnable to apply to join clan. |
| 6458 | 387 | 24137 | A fixed amount of time must pass in order to apply to join a clan.\nUnable to apply to join clan. |
| 6459 | 388 | 24143 | You are already a member of another clan.\nUnable to apply to join clan. |
| 6460 | 389 | 24149 | Unable to locate designated clan.\nUnable to apply to join clan. |
| 6461 | 390 | 24155 | Unable to locate designated clan, or clan may be disbanded.\nUnable to apply to join clan. |
| 6462 | 391 | 24161 | Unable to cancel clan entry. |
| 6463 | 392 | 24167 | A network server error has occurred.\nUnable to cancel clan entry. |
| 6464 | 393 | 24173 | Unable to leave clan. |
| 6465 | 394 | 24179 | A network server error has occurred.\nUnable to leave clan. |
| 6466 | 395 | 24185 | Unable to approve entry application. |
| 6467 | 396 | 24191 | A network server error has occurred.\nUnable to approve entry application. |
| 6468 | 397 | 24197 | The applicant has already canceled their clan entry application. |
| 6469 | 398 | 24203 | Unable to decline entry application. |
| 6470 | 399 | 24209 | A network server error has occurred.\nUnable to decline entry application. |
| 6471 | 400 | 24197 | The applicant has already canceled their clan entry application. |
| 6496 | 401 | 24215 | Unable to update clan comment. |
| 6497 | 402 | 24221 | A network server error has occurred.\nUnable to update clan comment. |
| 6498 | 403 | 24227 | Clan comment contains an invalid word.\nUnable to update clan comment. |
| 6499 | 404 | 24233 | Unable to update clan notice. |
| 6500 | 405 | 24239 | A network server error has occurred.\nUnable to update clan notice. |
| 6501 | 406 | 24245 | Clan notice contains an invalid word.\nUnable to update clan notice. |
| 6502 | 407 | 24250 | Unable to assign emblem editing rights. |
| 6503 | 408 | 24256 | A network server error has occurred.\nUnable to assign emblem editing rights. |
| 6504 | 409 | 24262 | Player is ineligible.\nUnable to assign emblem editing rights. |
| 6505 | 410 | 24268 | Designated player has already left clan.\nUnable to assign emblem editing rights. |
| 6506 | 411 | 24274 | Unable to revoke emblem editing rights. |
| 6507 | 412 | 24280 | A network server error has occurred.\nUnable to revoke emblem editing rights. |
| 6508 | 413 | 24286 | Unable to assign new leader. |
| 6509 | 414 | 24292 | A network server error has occurred.\nUnable to assign new leader. |
| 6510 | 415 | 24298 | Player is ineligible.\nUnable to assign new leader. |
| 6511 | 416 | 24304 | Designated player has already left clan.\nUnable to assign new leader. |
| 6512 | 417 | 24310 | Unable to banish clan member. |
| 6513 | 418 | 24316 | A network server error has occurred.\nUnable to banish clan member. |
| 6514 | 419 | 24322 | Designated player has already left clan.\nUnable to banish clan member. |
| 6515 | 420 | 24328 | Unable to disband clan. |
| 6516 | 421 | 24334 | A network server error has occurred.\nUnable to disband clan. |
| 6517 | 422 | 24340 | A fixed amount of time must pass in order to disband the clan.\nUnable to disband clan. |
| 6518 | 423 | 24346 | Unable to acquire clan roster. |
| 6519 | 424 | 24352 | A network server error has occurred.\nUnable to acquire clan roster. |
| 6520 | 425 | 24358 | Unable to acquire clan list. |
| 6521 | 426 | 24364 | A network server error has occurred.\nUnable to acquire clan list. |
| 6522 | 427 | 24370 | Unable to acquire clan emblem. |
| 6523 | 428 | 24376 | A network server error has occurred.\nUnable to acquire clan emblem. |
| 6524 | 429 | 24382 | A fixed amount of time must pass in order for the emblem to be updated. |
| 6525 | 430 | 24388 | Unable to acquire clan entry application list. |
| 6526 | 431 | 24394 | A network server error has occurred.\nUnable to acquire clan entry application list. |
| 6527 | 432 | 24400 | Unable to update clan emblem. |
| 6528 | 433 | 24406 | A network server error has occurred.\nUnable to update clan emblem. |
| 6529 | 436 | 24415 | You do not have emblem editing rights. |
| 6560 | 437 | 24421 | Emblem data is corrupted. |
| 6561 | 438 | 24427 | Unable to save emblem. |
| 6562 | 439 | 24433 | Unable to delete emblem. |
| 6563 | 440 | 24439 | Not enough space on the hard disk. Could not save emblem. |
| 6564 | 441 | 24445 | Not enough space on the hard disk. |
| 6565 | 442 | 24451 | Not enough space on the hard disk. %d KB are required to save emblem. |
| 6576 | 443 | 24457 | Unable to locate that clan. |
| 6577 | 444 | 24463 | Unable to search for clan. |
| 6578 | 445 | 24469 | A network server error has occurred.\nUnable to search for clan. |
| 6592 | 446 | 24475 | Join Comment is blank.\nUnable to apply to join clan. |
| 6593 | 447 | 24481 | Join Comment contains an invalid word.\nUnable to apply to join clan. |
| 7936 | 11 | 21965 | Disconnected from the network. |

### Blank messages

17 rows resolve to a string id that carries no text. Those are real ids, not decode failures — the
extraction has the surrounding ids and simply nothing at that one, which is what an unused slot in a
locale block looks like. Treat a blank as "this dialogId exists but the retail build shipped no
English string for it", and do not send its code expecting a message.

## Not resolved

72 of 628 entries belong to sections 32
(`MGO_ERROR_RES_GAME`, name at `0xE1FD18`) and 33 (`MGO_ERROR_RES_GMINFO`, `0xE1FD00`). Those two
groups are not registered in the lobby script, so their control and text bases are unknown and their
ordinals cannot be turned into strings from the lobby extraction alone. They are in-game errors
rather than lobby ones, so the bases are presumably registered in a stage script under
`dev/analysis/strings/` other than `lobby`; finding them is the whole remaining work.

