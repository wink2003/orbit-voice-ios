# Main Orbit Health — SwiftUI UX (DEV concept)
  
Scope: presentation-only expansion of existing Medical section, see [family-ai#379](https://github.com/wink2003/orbit-family-ai/issues/379).
Target: `apps/orbit-voice-ios/VoiceAgent/App/MedicalExperienceView.swift`, linked from `OrbitMoreView.swift`.

## Current wired surfaces

- More → Здоров’я → Health Dashboard. No second shell or second navigation stack.
- Server-authorized subject picker, including allowed records of non-account relatives. Profiles are never merged or inferred by name.
- Existing `MedicalAPI.subjects()` and `MedicalAPI.summary(id)` are the **only** live reads. Existing `MedicalSubjectView` remains the destination for record creation, deletion and secure document download/share.
- Overview, medications, appointments, diagnoses/history, documents (local search/filter) and future-services hub.
- Light/dark colors from `Routes05Tokens`, accessible buttons, native back behavior.
- Errors `medical_disabled`, `medical_adult_required`, and summary access failures fail closed: no cached data from another person, no fallback fixtures in release builds.

## Future modules: intentionally **NOT IMPLEMENTED**

Measurements/charts, lab results, prescriptions, vaccinations, symptoms, medical passport, care plans, provider directory, insurance, visit preparation, medication adherence log, and selective exports.
Each feature currently opens an explanatory design screen labelled `PROЄКТУЄТЬСЯ`; it performs **no write** and does not use dummy clinical measurements.

Future modules require separate backend design, data provenance, per-person ACL, audit, confirmation for consequential actions, and scoped owner approval.
Current `MedMedication.schedule` is **prescription schedule**, not a log that a dose was taken. Never infer adherence.
No HealthKit, Apple Health, third-party clinics, messaging, Chat/Voice, or Agent access was introduced.

## Device UX acceptance checklist

- More → Здоров’я opens new root; back and app dock work.
- Server disabled/adult-required: locked explanation only, no medical data or fictitious demo records.
- Access to one person does not reveal another person's records; changing profile clears old data before reload.
- Overview and real tabs render empty/loaded/error states; refresh does not cross person scope.
- Medications/appointments/diagnoses/documents show API records without hidden writes; current add, delete, and secure file operations remain in existing detail.
- Search/filter applies only to authorized loaded document metadata.
- All 12 planned modules clearly state they are inactive and do not provide functional medical advice.
- Light/dark, iPhone 12 width, larger Dynamic Type, VoiceOver targets, long German/UA titles.

## Evidence/status

The PR is DEV-only and not a release request. A successful unsigned GitHub Actions build (if obtained) is CODE/CI_VERIFIED only; iPhone acceptance remains PHYSICAL_DEVICE_NOT_VERIFIED. No production write or backend migration authorized.
