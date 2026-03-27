import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/utils/ai_question_paper_parser.dart';

void main() {
  group('parseAiQuestionPaper', () {
    test('parses nested quiz payloads with wrapped results', () {
      const rawResponse = '''
{
  "data": {
    "title": "Operating Systems Mock Test",
    "subject": "Operating Systems",
    "instructions": [
      {"text": "Answer all questions."},
      "Choose one option."
    ],
    "mcqs": [
      {
        "question": "Which scheduler picks the next process?",
        "choices": {
          "A": "CPU scheduler",
          "B": "Assembler",
          "C": "Compiler",
          "D": "Loader"
        },
        "correct_answer": "Option A",
        "explanation": "The CPU scheduler selects the next process."
      },
      {
        "prompt": "Which memory is fastest?",
        "answers": [
          {"text": "Cache"},
          {"text": "Disk"},
          {"text": "Tape"},
          {"text": "DVD"}
        ],
        "solution": "Cache"
      }
    ]
  }
}
''';

      final parsed = parseAiQuestionPaper(
        rawResponse: rawResponse,
        semester: '4',
        branch: 'cse',
        fallbackSubject: '',
        contextResourceCount: 2,
      );

      expect(parsed, isNotNull);
      expect(parsed!.subject, 'Operating Systems');
      expect(parsed.title, 'Operating Systems Mock Test');
      expect(
        parsed.instructions,
        containsAll(<String>['Answer all questions.', 'Choose one option.']),
      );
      expect(parsed.questions, hasLength(2));
      expect(parsed.questions.first.options.first, 'CPU scheduler');
      expect(parsed.questions.first.correctIndex, 0);
      expect(parsed.questions.last.correctIndex, 0);
    });

    test('parses fenced top-level arrays and normalizes answers', () {
      const rawResponse = '''
```json
[
  {
    "text": "Which layer handles routing?",
    "options": ["A) Network", "B) Session", "C) Transport", "D) Physical"],
    "answer": "A"
  },
  {
    "question_text": "Which topology uses a central hub?",
    "options": "A) Star\nB) Bus\nC) Ring\nD) Mesh",
    "correct": "1"
  }
]
```
''';

      final parsed = parseAiQuestionPaper(
        rawResponse: rawResponse,
        semester: '3',
        branch: 'ece',
        fallbackSubject: 'Computer Networks',
        contextResourceCount: 1,
      );

      expect(parsed, isNotNull);
      expect(parsed!.subject, 'Computer Networks');
      expect(parsed.questions, hasLength(2));
      expect(parsed.questions[0].options[0], 'Network');
      expect(parsed.questions[0].correctIndex, 0);
      expect(parsed.questions[1].options[0], 'Star');
      expect(parsed.questions[1].correctIndex, 0);
    });

    test('recovers partial question-paper json blocks', () {
      const rawResponse = '''
StudyShare draft:
{
  "title": "DBMS Quiz",
  "subject": "DBMS",
  "questions": [
    {
      "question": "Which normal form removes partial dependency?",
      "options": ["1NF", "2NF", "3NF", "BCNF"],
      "answer": "2NF"
    },
    {
      "question": "Which key uniquely identifies a row?",
      "options": ["Foreign key", "Primary key", "Composite key", "Candidate key"],
      "answer": "Primary key"
    }
  ]
Trailing note that breaks full JSON parsing.
''';

      final parsed = parseAiQuestionPaper(
        rawResponse: rawResponse,
        semester: '5',
        branch: 'cse',
        fallbackSubject: '',
        contextResourceCount: 3,
      );

      expect(parsed, isNotNull);
      expect(parsed!.subject, 'DBMS');
      expect(parsed.questions, hasLength(2));
      expect(parsed.questions[0].correctIndex, 1);
      expect(parsed.questions[1].correctIndex, 1);
    });
  });

  group('decodeStructuredJsonMap', () {
    test('decodes strict json maps used for subject inference', () {
      const raw = '```json {"subject":"Discrete Mathematics"} ```';
      final decoded = decodeStructuredJsonMap(raw);

      expect(decoded, isNotNull);
      expect(decoded!['subject'], 'Discrete Mathematics');
    });
  });
}
