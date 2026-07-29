meta:
  id: mgo2_cmd_4107_s2c
  title: "MGO2 0x4107 — personal scores (reply 4/4 of the 0x4102 burst, terminal)"
  endian: be
doc: |
  Two 73-slot u32 records with one shared layout: record 1 cumulative, record 2 weekly
  (the stats screen's cumulative/weekly toggle; [CONFIRMED fingerprint v9]). TERMINAL
  packet of the burst — its parser (0xd3db1c) unconditionally completes wait slot 0x16
  (0xd3e4b0), so it must be sent last; without it the client stalls into FFFFFF60.

  36 of 73 slots are [CONFIRMED] by the v5 fingerprint (value = slot number rendered on
  screen; time slots verified arithmetically via hh:mm:ss rendering of seconds).
  Mode-page placement of some slots (e.g. Bases Conquered on the Base page) is pure UI —
  every slot is a single global value. Several slots feed client-side medal thresholds
  (dev/docs/OBSERVED.md, "Titles and medals").
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats"
seq:
  - id: status
    type: u4
    doc: "Observed 0."
  - id: cumulative
    type: personal_scores
    doc: "Record 1 — lifetime."
  - id: weekly
    type: personal_scores
    doc: "Record 2 — weekly period; reset cadence is server/operator policy."
types:
  personal_scores:
    doc: "73 u32 slots, named by 1-based wire slot. unknown_NN = position exact, meaning unestablished (fp value 1000+NN / 2000+NN surfaced nowhere)."
    seq:
      - id: consecutive_kills
        type: u4
        doc: "slot 1. [CONFIRMED] Medal source: 5/10/25."
      - id: consecutive_deaths
        type: u4
        doc: "slot 2. [CONFIRMED]"
      - id: unknown_03
        type: u4
        doc: "slot 3. [UNKNOWN] — candidate: consecutive headshots (medal 3/10/30 observed live, source slot unpinned)."
      - id: suicides
        type: u4
        doc: "slot 4. [CONFIRMED]"
      - id: times_stunned
        type: u4
        doc: "slot 5. [CONFIRMED]"
      - id: friendly_kills
        type: u4
        doc: "slot 6. [CONFIRMED]"
      - id: friendly_stuns
        type: u4
        doc: "slot 7. [CONFIRMED]"
      - id: salutes
        type: u4
        doc: "slot 8. [CONFIRMED]"
      - id: radio_message_uses
        type: u4
        doc: "slot 9. [CONFIRMED] (\"Preset Radio Message Uses\")"
      - id: text_chat_uses
        type: u4
        doc: "slot 10. [CONFIRMED] (UI label \"Text Chase Uses\" — sic)"
      - id: cqc_attacks_given
        type: u4
        doc: "slot 11. [CONFIRMED]"
      - id: cqc_attacks_taken
        type: u4
        doc: "slot 12. [CONFIRMED]"
      - id: rolls
        type: u4
        doc: "slot 13. [CONFIRMED]"
      - id: envg_seconds
        type: u4
        doc: "slot 14. [CONFIRMED] Seconds; rendered hh:mm:ss."
      - id: dedicated_host_seconds
        type: u4
        doc: "slot 15. [CONFIRMED] Seconds."
      - id: catapult_uses
        type: u4
        doc: "slot 16. [CONFIRMED]"
      - id: boosts_given
        type: u4
        doc: "slot 17. [CONFIRMED]"
      - id: falling_deaths
        type: u4
        doc: "slot 18. [CONFIRMED]"
      - id: trap_catches
        type: u4
        doc: "slot 19. [CONFIRMED] (\"Times Caught in Trap\")"
      - id: scans_performed
        type: u4
        doc: "slot 20. [CONFIRMED]"
      - id: cardboard_box_seconds
        type: u4
        doc: "slot 21. [CONFIRMED] Seconds."
      - id: cardboard_box_uses
        type: u4
        doc: "slot 22. [CONFIRMED]"
      - id: melee_hits
        type: u4
        doc: "slot 23. [CONFIRMED]"
      - id: unknown_24
        type: u4
        doc: "slot 24. [UNKNOWN]"
      - id: consecutive_survivals_tdm
        type: u4
        doc: "slot 25. [CONFIRMED] Shown on the TDM page. Medal source: 2/4/6."
      - id: bases_conquered
        type: u4
        doc: "slot 26. [CONFIRMED] Base page."
      - id: sop_destabilizer_uses
        type: u4
        doc: "slot 27. [CONFIRMED] Base page. Medal source: ~50/100/200."
      - id: gako_saved
        type: u4
        doc: "slot 28. [CONFIRMED] Rescue page."
      - id: gako_defended
        type: u4
        doc: "slot 29. [CONFIRMED] Rescue page."
      - id: unknown_30
        type: u4
        doc: "slot 30. [UNKNOWN]"
      - id: fully_defended_matches
        type: u4
        doc: "slot 31. [CONFIRMED] Rescue page."
      - id: unknown_32
        type: u4
        doc: "slot 32. [UNKNOWN]"
      - id: unknown_33
        type: u4
        doc: "slot 33. [UNKNOWN]"
      - id: unknown_34
        type: u4
        doc: "slot 34. [UNKNOWN]"
      - id: unknown_35
        type: u4
        doc: "slot 35. [UNKNOWN]"
      - id: soldiers_trained
        type: u4
        doc: "slot 36. [CONFIRMED] Medal source: 10/100/300."
      - id: unknown_37
        type: u4
        doc: "slot 37. [UNKNOWN]"
      - id: unknown_38
        type: u4
        doc: "slot 38. [UNKNOWN]"
      - id: unknown_39
        type: u4
        doc: "slot 39. [UNKNOWN]"
      - id: unknown_40
        type: u4
        doc: "slot 40. [UNKNOWN]"
      - id: unknown_41
        type: u4
        doc: "slot 41. [UNKNOWN]"
      - id: unknown_42
        type: u4
        doc: "slot 42. [UNKNOWN]"
      - id: unknown_43
        type: u4
        doc: "slot 43. [UNKNOWN]"
      - id: unknown_44
        type: u4
        doc: "slot 44. [UNKNOWN]"
      - id: unknown_45
        type: u4
        doc: "slot 45. [UNKNOWN]"
      - id: training_seconds
        type: u4
        doc: "slot 46. [CONFIRMED] Seconds (\"Training Mode Time\")."
      - id: instructor_seconds
        type: u4
        doc: "slot 47. [CONFIRMED] Seconds (\"Combat Training Time (Instructor)\")."
      - id: student_seconds
        type: u4
        doc: "slot 48. [CONFIRMED] Seconds (\"Combat Training Time (Student)\")."
      - id: unknown_49
        type: u4
        doc: "slot 49. [UNKNOWN]"
      - id: unknown_50
        type: u4
        doc: "slot 50. [UNKNOWN]"
      - id: unknown_51
        type: u4
        doc: "slot 51. [UNKNOWN]"
      - id: unknown_52
        type: u4
        doc: "slot 52. [UNKNOWN]"
      - id: unknown_53
        type: u4
        doc: "slot 53. [UNKNOWN]"
      - id: unknown_54
        type: u4
        doc: "slot 54. [UNKNOWN]"
      - id: unknown_55
        type: u4
        doc: "slot 55. [UNKNOWN]"
      - id: unknown_56
        type: u4
        doc: "slot 56. [UNKNOWN]"
      - id: unknown_57
        type: u4
        doc: "slot 57. [UNKNOWN]"
      - id: unknown_58
        type: u4
        doc: "slot 58. [UNKNOWN]"
      - id: unknown_59
        type: u4
        doc: "slot 59. [UNKNOWN]"
      - id: unknown_60
        type: u4
        doc: "slot 60. [UNKNOWN]"
      - id: unknown_61
        type: u4
        doc: "slot 61. [UNKNOWN]"
      - id: unknown_62
        type: u4
        doc: "slot 62. [UNKNOWN]"
      - id: snake_victories
        type: u4
        doc: "slot 63. [CONFIRMED] Sneaking page (\"Victories as Snake\")."
      - id: knife_kills
        type: u4
        doc: "slot 64. [CONFIRMED]"
      - id: unknown_65
        type: u4
        doc: "slot 65. [UNKNOWN]"
      - id: unknown_66
        type: u4
        doc: "slot 66. [UNKNOWN]"
      - id: snake_kills
        type: u4
        doc: "slot 67. [CONFIRMED] Sneaking page."
      - id: unknown_68
        type: u4
        doc: "slot 68. [UNKNOWN]"
      - id: unknown_69
        type: u4
        doc: "slot 69. [UNKNOWN]"
      - id: unknown_70
        type: u4
        doc: "slot 70. [UNKNOWN]"
      - id: unknown_71
        type: u4
        doc: "slot 71. [UNKNOWN]"
      - id: snake_seconds
        type: u4
        doc: "slot 72. [CONFIRMED] Seconds (\"Total Time (Playing) as Snake\")."
      - id: unknown_73
        type: u4
        doc: "slot 73. [UNKNOWN]"
