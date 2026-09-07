# Orbit Interpreter fixture review

Status: `PROPOSED_FOR_HUMAN_APPROVAL`

This review is offline and pre-inference. The historical draft at
`VoiceAgent/InterpreterLab/interpreter-fixtures-draft.json` is unchanged.

## Summary

| Review status | Count |
|---|---:|
| Ready unchanged (`NONE`) | 21 |
| Minor revision | 3 |
| Major revision | 6 |
| Blocker remaining | 0 |

The six major revisions address deterministic scoreability: two implicit
evening times, two yearless weekday/date combinations, an ambiguous Amt
deadline, and a malformed mixed-script code-switch token. The proposed file
also adds normalized semantic metadata and explicit risk levels.

## Risk balance

| Risk | UA→DE | DE→UA | Total |
|---|---:|---:|---:|
| LOW | 3 | 3 | 6 |
| MEDIUM | 4 | 4 | 8 |
| HIGH | 8 | 8 | 16 |

HIGH means a polarity, quantity, date/time, correction, fictional dose, or
multi-clause action error can be severe. The fictional medical fixtures are
only 2/30; the benchmark is not a medical corpus.

## Category balance

Each direction contains one fixture in every category below, except NUMBERS,
which has two. This gives 15 fixtures per direction and comparable difficulty:

`SHORT_EVERYDAY` 2, `FAST_SHORT_RESPONSE` 2, `NUMBERS` 4,
`DATE_TIME` 2, `NEGATION` 2, `MEDICAL_FICTIONAL` 2, `SCHOOL` 2,
`AMT_BUREAUCRACY` 2, `PROPER_NAMES` 2, `SELF_CORRECTION` 2,
`COLLOQUIAL/COLLOQUIAL_UKRAINIAN` 2, `CODE_SWITCH` 2,
`LONG_SENTENCE` 2, `INTERRUPTION_FALSE_START` 2.

## Fixture-by-fixture review

| ID | Direction/category | Source-language review | Reference review | Risk | Status | Reviewer note |
|---|---|---|---|---|---|---|
| `uk-de-everyday-01` | UA→DE / everyday | Natural polite Ukrainian. | Natural formal German. | LOW | NONE | Accept as written. |
| `uk-de-everyday-02` | UA→DE / fast response | Proposed wording makes evening explicit. | Proposed `nach fünf Uhr abends` is natural. | HIGH | MAJOR | Original “після п'ятої” was time-of-day ambiguous. |
| `uk-de-numbers-01` | UA→DE / numbers | Natural bureaucratic wording; формуляр is plausible. | Preserves 15-versus-50 contrast. | HIGH | NONE | Either quantity changing is severe. |
| `uk-de-numbers-02` | UA→DE / numbers | Natural spoken decimal comparison. | Natural German decimal comma; exact values preserved. | HIGH | NONE | 38.7/37.8 reversal is severe. |
| `uk-de-date-01` | UA→DE / date/time | Proposed year removes weekday ambiguity. | Proposed German date is natural. | HIGH | MAJOR | Exact normalized value: 2024-05-14 14:30. |
| `uk-de-negation-01` | UA→DE / negation | Natural formal imperative. | Correct polarity and temporal adverb. | HIGH | NONE | Polarity reversal is severe. |
| `uk-de-medical-01` | UA→DE / fictional medical | Explicitly fictional; plausible test instruction. | Natural and preserves 1.5 ml plus after/before relation. | HIGH | NONE | Dose or timing change is severe; not medical advice. |
| `uk-de-school-01` | UA→DE / school | Natural parent/teacher sentence. | `Heft` is ordinary German school usage. | MEDIUM | NONE | Names and tomorrow are critical. |
| `uk-de-amt-01` | UA→DE / Amt | Proposed Monday deadline is unambiguous. | Proposed German deadline is natural. | MEDIUM | MAJOR | Original “до наступного тижня” was under-specified. |
| `uk-de-names-01` | UA→DE / names | Plausible fictional name/place phrase. | Translated place-name rendering is acceptable if identity remains stable. | MEDIUM | NONE | Transliteration versus translation is not itself failure. |
| `uk-de-correction-01` | UA→DE / correction | Natural spoken self-correction. | German preserves superseded Thursday and final Friday. | HIGH | NONE | Final actionable day is Friday. |
| `uk-de-colloquial-01` | UA→DE / colloquial | Natural colloquial Ukrainian; feminine past form is intentional. | Natural conversational German; gender need not be explicit. | LOW | NONE | Do not penalize stylistic paraphrase. |
| `uk-de-codeswitch-01` | UA→DE / code-switch | German institutional noun is a plausible code-switch. | Preserving `Terminzettel` is the intended behavior. | LOW | NONE | Preserve meaning, not arbitrary lexical choice. |
| `uk-de-long-01` | UA→DE / long | Natural multi-clause instruction. | Preserves bus deadline, negation, names, and message ordering. | HIGH | NONE | Do not drop “not walk; call me”. |
| `uk-de-false-start-01` | UA→DE / false start | Plausible spoken repair; appointment meaning is recoverable. | Natural German repair. | MEDIUM | MINOR | Proposed facts make final intent explicit. |
| `de-uk-everyday-01` | DE→UA / everyday | Natural polite German. | Natural Ukrainian institutional wording. | LOW | NONE | Accept equivalent polite greeting. |
| `de-uk-everyday-02` | DE→UA / fast response | Proposed wording makes evening explicit. | Proposed Ukrainian preserves after-17:00. | HIGH | MAJOR | Original “nach fünf” was time-of-day ambiguous. |
| `de-uk-numbers-01` | DE→UA / numbers | Spoken German 1,500 is unambiguous; written dot is locale-sensitive. | Ukrainian thousands spacing is natural. | HIGH | NONE | Score numeric value 1500, never typography alone. |
| `de-uk-numbers-02` | DE→UA / numbers | Natural decimal contrast. | Natural Ukrainian decimal comma. | HIGH | NONE | Exact decimals are critical. |
| `de-uk-date-01` | DE→UA / date/time | Relative tomorrow is understandable; Monday exclusion is explicit. | Natural Ukrainian. | HIGH | MINOR | Add normalized relative-date/exclusion facts. |
| `de-uk-negation-01` | DE→UA / negation | Natural medical-like statement without real data. | Exact negative allergy meaning preserved. | HIGH | NONE | Polarity reversal is severe. |
| `de-uk-medical-01` | DE→UA / fictional medical | Explicitly fictional; quantity and timing are clear. | Natural Ukrainian and exact 50 mg. | HIGH | NONE | Dose, after, and not-before are severe facts. |
| `de-uk-school-01` | DE→UA / school | Natural German school request. | Natural Ukrainian parent-letter wording. | MEDIUM | NONE | Deadline and names must remain. |
| `de-uk-amt-01` | DE→UA / Amt | Natural German bureaucracy vocabulary. | `довідка про реєстрацію` is a reasonable target rendering. | MEDIUM | NONE | Missing documents must remain missing. |
| `de-uk-names-01` | DE→UA / names | Plausible fictional place-like names. | Transliteration is natural and identity-preserving. | MEDIUM | NONE | Do not require a particular Cyrillic spelling. |
| `de-uk-correction-01` | DE→UA / correction | Natural repair with exact time. | Preserves final Thursday and 17:00. | HIGH | NONE | Wednesday is superseded. |
| `de-uk-colloquial-01` | DE→UA / colloquial | Natural colloquial German; `trödeln` is intentionally informal. | Natural Ukrainian paraphrase. | LOW | MINOR | Add explicit train-delay condition. |
| `de-uk-codeswitch-01` | DE→UA / code-switch | Original hybrid `Zошит` is malformed; proposed `зошит` is intentional code-switch. | Ukrainian target is natural. | LOW | MAJOR | Preserve semantic school-notebook meaning, not script artifact. |
| `de-uk-long-01` | DE→UA / long | Proposed year makes date deterministic; remaining German is natural. | Proposed Ukrainian preserves not-send versus call-before relation. | HIGH | MAJOR | Exact date and action contrast are critical. |
| `de-uk-false-start-01` | DE→UA / false start | Natural incomplete-start repair. | Natural Ukrainian; final application/next-week intent preserved. | MEDIUM | NONE | Do not score the abandoned fragment as final intent. |

## Severe-failure rules

For all fixtures marked HIGH, treat these as severe: polarity reversal or
omitted negation; changed numeric value or fictional dose; changed date/time;
replacing a corrected final value with its superseded value; reversing before/
after/until; changing a critical person/document/place identity; or omitting a
prohibited-versus-required action.

## Target-specific semantic audit

### Negation

Affected IDs include `uk-de-numbers-01`, `uk-de-numbers-02`,
`uk-de-negation-01`, `uk-de-medical-01`, `uk-de-correction-01`,
`uk-de-long-01`, `de-uk-numbers-01`, `de-uk-numbers-02`, `de-uk-date-01`,
`de-uk-negation-01`, `de-uk-medical-01`, `de-uk-correction-01`, and
`de-uk-long-01`. `NOT_X_BUT_Y` cases must preserve the final instruction and
the excluded/superseded value.

### Numbers, dates, and times

- 15 and 50 remain distinct integers.
- 1,5 and 38,7 are decimal values 1.5 and 38.7; punctuation is not the
  semantic score.
- 1.500 is the integer 1500 in the German source, contrasted with 150.
- `uk-de-date-01` and `de-uk-long-01` normalize to 2024-05-14.
- 14:30, 17:00, and before 15:00 are exact times.
- “after five in the evening” normalizes to after 17:00.
- “tomorrow” remains a relative semantic value and must not be scored as a
  fixed calendar date without a recording anchor.

### Self-correction

- `uk-de-correction-01`: Thursday → superseded; Friday → final.
- `de-uk-correction-01`: Wednesday → superseded; Thursday at 17:00 → final.
- False-start fixtures retain only the repaired final intent as actionable.

### Medical-like content

`uk-de-medical-01` and `de-uk-medical-01` are fictional translation-test
sentences. They contain no family health data and must not be interpreted as
medical advice. Dose, unit, and temporal relation are explicit severe facts.

### Code switching

`Terminzettel` is intentionally German inside Ukrainian and should remain
semantically identifiable; lexical translation is acceptable if the appointment
slip meaning is preserved. `зошит` is intentionally Ukrainian inside German;
the malformed hybrid `Zошит` is corrected in proposed v1. Do not penalize
script-preserving versus explanatory paraphrase when identity and meaning are
unchanged.

## Proposed artifacts

- Proposed manifest: `interpreter-fixtures-proposed-v1.json`
- Change log: `interpreter-fixtures-diff.json`
- This review: `interpreter-fixtures-review.md`

No artifact is frozen. The user must approve proposed v1 before any hash or
pre-inference ground-truth record is created.
