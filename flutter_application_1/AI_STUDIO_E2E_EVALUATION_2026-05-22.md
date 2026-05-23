# AI Studio E2E Evaluation - 2026-05-22

## Scope

Measured the StudySpace AI Studio quiz-generation path from the point a user starts generation to the point quiz results are produced by the backend generation service.

The live production `/api/ai/*` endpoint requires a Firebase ID token, so the timing probes used the same backend Phase-1 generation service directly with real Supabase/R2 storage resources. This exercises the same extraction, topic inventory, generation, validation, and output path used by the app after the request reaches the backend.

## Resources Tested

| Case | Resource ID | Title | Subject | PDF pages | Storage source |
| --- | --- | --- | --- | ---: | --- |
| Typed PDF baseline | `ceb55453-54f9-4d64-8d70-c4df0b7c95c7` | `Toxicants Detailed.pdf` | Environmental Chemistry | 7 | `file.mystudyspace.me` |
| Handwritten COLD notes | `1513e5a0-236a-420e-9777-2366faf6c338` | `COLD UNIT 2 PART 1.pdf` | Computer Organization and Logic Design | 15 | `file.mystudyspace.me` |

Similar COLD PDFs found for future multi-PDF question-paper tests:

| Resource ID | Title | Pages | Extracted text chars |
| --- | --- | ---: | ---: |
| `3f33e37b-4d3d-47b9-b2f8-4c2e8bfa3477` | `COLD Unit 2 PART 2 K map.pdf` | 13 | 12,411 |
| `8c24c6be-6767-47d8-ab88-ff1689021bd4` | `COLD Unit 1 Part 1 Number System.pdf` | 31 | 4,320 |
| `fd140798-03b6-41b3-adee-c4423e4ac2c1` | `COLD UNIT 1 Part 2.pdf` | 6 | 6,327 |

## E2E Timing

| Run | OCR | Result | Time to result |
| --- | --- | --- | ---: |
| Toxicants typed PDF | On | Completed with 11 quiz questions | 598.2s |
| COLD handwritten PDF | On | Stopped after extraction stayed pending for >10 minutes | >600s, no result |
| COLD handwritten PDF | Off, before text restore | Completed with 1 quiz question | 324.1s |
| COLD handwritten PDF | Off, after text restore from RAG chunks | Completed with 2 quiz questions | 295.8s |

## Quality Evaluation

Scores are 1-5 unless stated otherwise.

| Parameter | Toxicants typed PDF | COLD handwritten PDF |
| --- | --- | --- |
| Helpfulness | 4 | 1 |
| Relevance to provided material | 4 | 1 |
| Diversified topics from PDF | 4 | 1 |
| Questions vs pages | 11 questions / 7 pages, good density | 2 questions / 15 pages, unacceptable density |
| Hardness | Medium-high; mostly scenario and inference questions | Low; questions are about page-marker artifacts |
| Unique questions by topic | 11/11 appear unique | 0 useful COLD-topic questions |
| Use of similar PDFs | Not applicable for single-PDF baseline | Similar COLD PDFs were discoverable, but the tested single-PDF path did not use them |

## Typed PDF Result Quality

The Toxicants run produced 11 multiple-choice questions across pollutant sources, blue-baby syndrome, carcinogenesis, cancer epidemiology, indoor pollutants, cadmium toxicity, smoking as a teratogen, persistent pesticides, aflatoxin, and teratogenicity factors.

Strengths:
- Questions are mostly exam-oriented and scenario-based.
- Options are plausible and consistently structured.
- The questions are relevant to toxicants and environmental-health material.

Issues:
- Backend validation returned `QUIZ_TOPIC_COVERAGE_TOO_LOW:1/5`.
- Backend skipped full-document structured quiz generation for a large source: `QUIZ_STRUCTURED_SKIPPED_LARGE_SOURCE`.
- Result count is good for 7 pages, but backend validation still considers topic coverage weak.

## Handwritten COLD Result Quality

The handwritten COLD PDF exposed a serious extraction/generation issue.

Observed failures:
- OCR-on generation did not leave extraction within the test window.
- OCR-off generation used `pdfium_hybrid` extraction and produced page-marker text like `-- 1 of 15 --`.
- Generated questions were about PDF/page markers, not COLD concepts.
- Validation errors included:
  - `QUIZ_TOO_SHORT`
  - `QUIZ_TOPIC_COVERAGE_TOO_LOW`
  - `QUIZ_STRUCTURED_GENERATION_FAILED`
  - ungrounded page-marker questions

This is not acceptable for handwritten notes. The RAG index has useful COLD content for the same resource, including Boolean identities, De Morgan's theorem, minterms/maxterms, canonical SOP/POS, logic gates, universal gates, XOR/XNOR, and NAND/NOR implementations. The AI Studio extraction path did not use that indexed text successfully.

## Data Integrity Finding

During the COLD probe, the backend extraction path overwrote `resources.extracted_text` with the bad 215-character page-marker extraction. I restored it from the indexed `rag_chunks` for `rag_files.id = c8787e08-6eb0-4664-93da-fd5a43e10bf5`, restoring 30 chunks and 23,381 characters.

This should be fixed in the backend: do not replace a useful `resources.extracted_text` value with a shorter or lower-quality extraction.

## Recommendations

1. For PDF AI generation, prefer indexed RAG chunks when they exist and are richer than live extraction output.
2. Add a quality gate before `syncResourceExtractedText`: reject replacements that are dramatically shorter or mostly page markers.
3. Add a handwritten/OCR regression test using `COLD UNIT 2 PART 1.pdf`.
4. Add a multi-PDF COLD evaluation using Unit 1 Part 1, Unit 1 Part 2, Unit 2 Part 1, and Unit 2 Part 2 K-map.
5. Surface backend validation errors in AI Studio instead of showing low-quality generated questions as successful results.

## Verification Commands

App tests passed:

```powershell
flutter test -r expanded test\admin_access_test.dart
flutter test -r expanded test\backend_api_service_test.dart test\ai_question_paper_parser_test.dart test\pdf_generation_smoke_test.dart
```

`flutter analyze` was attempted but did not finish within the 5-minute timeout in this workspace.

Probe logs are in `D:\StudyspaceProjects\studyspace-backend`:

- `tmp_ai_studio_toxicants_probe.log`
- `tmp_ai_studio_cold_unit2_probe.log`
- `tmp_ai_studio_cold_unit2_noocr_probe.log`
- `tmp_ai_studio_cold_unit2_restored_noocr_probe.log`

The reusable local probe wrapper is `scripts/ai-studio-phase1-probe.js`.
