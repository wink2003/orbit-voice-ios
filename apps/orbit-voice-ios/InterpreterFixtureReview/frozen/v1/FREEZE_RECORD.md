# Orbit Interpreter benchmark v1 freeze record

Status: `FROZEN_PRE_INFERENCE_V1`

The reviewed `interpreter-fixtures-proposed-v1.json` was explicitly approved
for freezing in the user request. This freeze record was created at
`2026-09-07T12:24:25Z` on branch `codex/interpreter-phase1-build-gate`, HEAD
`8ff6658a3bd9f9a02272736002e532d65e9b1f3c`.

## Dataset

- 30 fixtures total
- 15 Ukrainian → German
- 15 German → Ukrainian
- LOW risk: 6
- MEDIUM risk: 8
- HIGH risk: 16
- Approved minor revisions: 3
- Approved major revisions: 6
- Remaining blockers: 0

## Scoring authority

Scoring is semantic, not literal. Critical semantic facts and severe-failure
rules have priority over reference wording. Natural paraphrases are accepted
when they preserve meaning.

Relative dates such as tomorrow, завтра, morgen, and next week remain relational
semantics relative to the utterance context. Any absolute replay anchor belongs
in run metadata and does not alter the fixture.

Numbers are scored by underlying value, not punctuation. Negation, modality,
before/after/until relations, corrected final values, fictional dosage and
quantity, and critical identities are safety-sensitive. Medical-like content is
fictional translation-test content only.

This dataset was frozen before the first Orbit Interpreter Azure/Gemini
benchmark inference.

## SHA256

Hashes are SHA256 of exact UTF-8 file bytes.

| Artifact | SHA256 |
|---|---|
| Original draft | `68cd1ff30c08865bc87f970fcb42bb19626d3fbdfc92b3f3b6bd5078b56471a5` |
| Proposed manifest | `96b93b1e48d10b6089816a8ff1bb38b6bc39a7710d915e0171fe3f89d903311e` |
| Review diff | `f03f555ca338f08cf01b02dbdc3edac9f4387e9632a2aa0f94d15997d4769594` |
| Human review | `50a15b294e512e4533d926357f3251ce6cdd8ac06ca699cb9ca1fa284666880b` |
| Frozen manifest | `2c34f2f15e4972196ef25b4d79c0c43a62a0485a8dbdc8c49dceebab54890582` |
| Scoring policy | `834afbd28a19d1595c1c98181fe409d660a8c6d48959656d5876773b5b8b22f8` |
| Provenance | `08beb841510fdd9c839bf4b1ebc9593987f1594f102dd2ff197862c71f4047cf` |

Combined provenance hash:

`f8fe7e9914895823587e395b4692264e50fb9cc3abad88ccfee7c83a8e4f196c`

Combined input order is:

```text
frozen_manifest_sha256 + "\n" + scoring_policy_sha256 + "\n" + provenance_sha256
```

The provenance hash is calculated before the combined hash is recorded here,
so there is no circular dependency.

## Provider and release gates

- Azure Interpreter calls before freeze: 0
- Gemini Interpreter calls before freeze: 0
- External translation/judge calls: 0
- No provider credentials embedded in iOS
- No physical iPhone Interpreter test
- No production writes
- No IPA, SideStore, signing, or version/build changes

Version 1 must not be silently edited. Any later correction must be created as
`frozen/v2/` with an explicit v1→v2 diff and new hashes.
