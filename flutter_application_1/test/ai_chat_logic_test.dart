// Quick smoke test for the conversational query detection and
// general-knowledge query detection logic.
// Run with: dart run test/ai_chat_logic_test.dart

void main() {
  // ── _isConversationalQuery equivalents ──────────────────────────────
  const greetings = {
    'hello', 'hi', 'hey', 'hii', 'helo', 'hola', 'hello!', 'hi!', 'hey!',
    'hello there', 'hi there', 'hey there', 'namaste', 'good morning',
    'good afternoon', 'good evening', 'good night',
  };
  const farewells = {
    'bye', 'goodbye', 'bye bye', 'see ya', 'see you', 'thanks', 'thank you',
    'thankyou', 'thank u', 'ty', 'thx', 'ok', 'okay', 'k', 'got it',
    'alright', 'cool', 'nice',
  };
  const metaPhrases = [
    'which model', 'what model', 'which ai', 'what ai',
    'who are you', 'what are you', 'who made you', 'who created you',
    'what can you do', 'what do you do', 'how can you help',
    'how are you', 'how r u', 'how do you do',
    'what is studyshare', 'what is studyai', 'what is study share',
    'are you gpt', 'are you gemini', 'are you claude', 'are you chatgpt',
    'are you perplexity', 'are you openai', 'are you bard', 'are you google',
    'are you anthropic', 'are you llm', 'are you a bot', 'are you an ai',
    'are you human', 'are you real',
    'tell me about yourself', 'introduce yourself',
    'which llm', 'what llm', 'which language model',
  ];

  bool isConversationalQuery(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (greetings.contains(normalized)) return true;
    if (farewells.contains(normalized)) return true;
    for (final phrase in metaPhrases) {
      if (normalized == phrase || normalized.startsWith('$phrase ') ||
          normalized.endsWith(' $phrase') || normalized.contains(' $phrase ')) {
        return true;
      }
    }
    return false;
  }

  bool isGeneralKnowledgeQuery(String prompt) {
    final normalized = prompt.toLowerCase();
    return normalized.contains('gd topic') ||
        normalized.contains('group discussion topic') ||
        normalized.contains('current affair') ||
        normalized.contains('essay topic') ||
        normalized.contains('debate topic') ||
        normalized.contains('trending topic') ||
        normalized.contains('recent news') ||
        normalized.contains('latest news') ||
        normalized.contains('news today') ||
        normalized.contains('what is happening') ||
        normalized.contains('general knowledge') ||
        normalized.contains('gk question') ||
        normalized.contains('interview topic') ||
        normalized.contains('extempore topic');
  }

  // ── Tests ──────────────────────────────────────────────────────────
  var passed = 0;
  var failed = 0;

  void check(String label, bool actual, bool expected) {
    if (actual == expected) {
      passed++;
      print('  ✅ $label');
    } else {
      failed++;
      print('  ❌ $label (got $actual, expected $expected)');
    }
  }

  print('\n=== Conversational Query Detection ===\n');

  // Should match
  check('"hello"', isConversationalQuery('hello'), true);
  check('"Hi"', isConversationalQuery('Hi'), true);
  check('"hey there"', isConversationalQuery('hey there'), true);
  check('"good morning"', isConversationalQuery('good morning'), true);
  check('"thanks"', isConversationalQuery('thanks'), true);
  check('"bye"', isConversationalQuery('bye'), true);
  check('"ok"', isConversationalQuery('ok'), true);
  check('"which model are you using"', isConversationalQuery('which model are you using'), true);
  check('"what ai is this"', isConversationalQuery('what ai is this'), true);
  check('"who are you"', isConversationalQuery('who are you'), true);
  check('"are you chatgpt"', isConversationalQuery('are you chatgpt'), true);
  check('"what can you do"', isConversationalQuery('what can you do'), true);
  check('"how are you"', isConversationalQuery('how are you'), true);
  check('"tell me about yourself"', isConversationalQuery('tell me about yourself'), true);
  check('"which llm do you use"', isConversationalQuery('which llm do you use'), true);

  // Should NOT match (academic queries)
  check('"explain photosynthesis"', isConversationalQuery('explain photosynthesis'), false);
  check('"what is osmosis"', isConversationalQuery('what is osmosis'), false);
  check('"generate question paper"', isConversationalQuery('generate question paper'), false);
  check('"summarize this pdf"', isConversationalQuery('summarize this pdf'), false);
  check('"tell me about polymers"', isConversationalQuery('tell me about polymers'), false);
  check('"what are the types of reactions"', isConversationalQuery('what are the types of reactions'), false);
  check('"from my notes explain chapter 3"', isConversationalQuery('from my notes explain chapter 3'), false);

  print('\n=== General Knowledge Query Detection ===\n');

  // Should match
  check('"tell me some gd topics"', isGeneralKnowledgeQuery('tell me some gd topics'), true);
  check('"group discussion topics for interview"', isGeneralKnowledgeQuery('group discussion topics for interview'), true);
  check('"current affairs 2024"', isGeneralKnowledgeQuery('current affairs 2024'), true);
  check('"give me debate topics"', isGeneralKnowledgeQuery('give me debate topics'), true);
  check('"trending topics today"', isGeneralKnowledgeQuery('trending topics today'), true);
  check('"latest news in technology"', isGeneralKnowledgeQuery('latest news in technology'), true);
  check('"gk questions for exam"', isGeneralKnowledgeQuery('gk questions for exam'), true);

  // Should NOT match
  check('"explain thermodynamics"', isGeneralKnowledgeQuery('explain thermodynamics'), false);
  check('"what is binary search"', isGeneralKnowledgeQuery('what is binary search'), false);
  check('"summarize chapter 5"', isGeneralKnowledgeQuery('summarize chapter 5'), false);

  print('\n=== Results ===\n');
  print('  Passed: $passed');
  print('  Failed: $failed');
  print('  Total:  ${passed + failed}');
  if (failed > 0) {
    print('\n  ⚠️  SOME TESTS FAILED');
  } else {
    print('\n  🎉 ALL TESTS PASSED');
  }
}
