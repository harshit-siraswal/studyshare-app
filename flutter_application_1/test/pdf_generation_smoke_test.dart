import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/ai_question_paper.dart';
import 'package:flutter_application_1/services/summary_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates branded summary, quiz, and flashcard PDFs', () async {
    final service = SummaryPdfService();

    final summaryBytes = await service.generateSummaryPdfBytes(
      title: 'Biology Chapter 4',
      subtitle: 'AI Summary',
      summary: '''
Cellular respiration is the process through which cells convert glucose into usable energy in the form of ATP. The chapter moves through glycolysis, pyruvate oxidation, the Krebs cycle, and oxidative phosphorylation.

- Glycolysis occurs in the cytoplasm and produces a net gain of 2 ATP and 2 NADH.
- Pyruvate oxidation links glycolysis with the Krebs cycle and forms acetyl-CoA.
- The Krebs cycle produces NADH, FADH2, and GTP in the mitochondrial matrix.
- Oxidative phosphorylation generates the largest ATP yield through chemiosmosis.

Aerobic respiration uses oxygen as the final electron acceptor, while anaerobic pathways rely on fermentation to regenerate NAD+ for glycolysis.
''',
    );

    final quizBytes = await service.generateQuestionPaperPdfBytes(
      paper: AiQuestionPaper(
        title: 'Biology Chapter 4 - Practice Quiz',
        subject: 'Biology Ch. 4',
        semester: '2',
        branch: 'General',
        instructions: const ['Answer all questions'],
        generatedAt: DateTime.now(),
        pyqCount: 0,
        questions: [
          AiQuestionPaperQuestion(
            question: 'Where does glycolysis take place in a eukaryotic cell?',
            options: [
              'Mitochondrial matrix',
              'Cytoplasm',
              'Nucleus',
              'Endoplasmic reticulum',
            ],
            correctIndex: 1,
            explanation:
                'Glycolysis takes place in the cytoplasm and does not require the mitochondria.',
            source: AiQuestionPaperSource(title: 'Biology Chapter 4'),
          ),
          AiQuestionPaperQuestion(
            question: 'Which stage of cellular respiration produces the most ATP?',
            options: [
              'Glycolysis',
              'Pyruvate oxidation',
              'Krebs cycle',
              'Oxidative phosphorylation',
            ],
            correctIndex: 3,
            explanation:
                'Oxidative phosphorylation drives the largest ATP output through the electron transport chain and chemiosmosis.',
            source: AiQuestionPaperSource(title: 'Biology Chapter 4'),
          ),
        ],
      ),
    );

    final flashcardBytes = await service.generateFlashcardsPdfBytes(
      title: 'Biology Chapter 4 - Flashcards',
      flashcards: const [
        FlashcardPdfEntry(
          term: 'Glycolysis',
          definition:
              'The metabolic pathway in the cytoplasm that converts glucose into pyruvate and yields a net 2 ATP and 2 NADH.',
        ),
        FlashcardPdfEntry(
          term: 'Krebs Cycle',
          definition:
              'A cyclic series of reactions in the mitochondrial matrix that produces NADH, FADH2, and GTP.',
        ),
        FlashcardPdfEntry(
          term: 'Chemiosmosis',
          definition:
              'The flow of H+ ions through ATP synthase that powers ATP production.',
        ),
      ],
    );

    expect(summaryBytes.length, greaterThan(0));
    expect(quizBytes.length, greaterThan(0));
    expect(flashcardBytes.length, greaterThan(0));
  });
}
