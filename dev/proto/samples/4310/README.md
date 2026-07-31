# Captured `0x4310` host-settings pushes

214 raw payloads from a live `BLUS30109` client, 2026-07-22 to 2026-07-29, one per line:

```
chara_id | lobby subtype | captured_at | payload as hex
```

**Kept because they are the evidence, not because the tool was.** The capture table
(`blob_audit`, briefly `dev_packet_audit`) was removed once the host-settings block was fully
decoded — it was single-purpose and its purpose was served. These rows outlive it.

What was established from them, and can be re-checked here rather than taken on trust:

- the **352-byte length**, against the 345 the last named field implies — every payload is `0x160`
  with the trailing seven zero;
- the **training-lobby correlation**: struct `+824` and `+931` co-vary, and every capture from
  subtypes 7 and 8 zeroes the pair while every other subtype sets it (26 vs 182);
- the **Common Settings toggle bits** that cannot be rebuilt from their booleans — bits 1, 2 and 6.

To re-derive any of it:

```bash
# the pair, by lobby subtype
awk -F'|' '{print $2, substr($4,469,8), substr($4,649,2)}' captures.psv | sort | uniq -c
```

Byte offsets are 1-based into the hex string, so a field at wire offset `N` starts at `2N+1`.
The field map is `dev/proto/inbound/mgo2_cmd_4310_c2s.ksy`.
