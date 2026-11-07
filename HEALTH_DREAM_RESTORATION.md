# Health and dream safety reconstruction

This is a reconstruction from the available September repository baseline and the
recovery audit, not a byte-identical recovery of the lost final working tree.

- Historical `skills/nihaixia` files remain unchanged. Online TCM prompts load only
  two explicitly reviewed, non-prescription concept excerpts. No persona, urgent
  remedy FAQ, diagnosis formula, medication dose, or brewing instructions are
  injected. The assistant is a learning aid, not a clinician impersonation.
- TCM emergency detection includes traditional Chinese stroke, hemiplegia and
  overdose signals and normalizes whitespace/zero-width characters. Both response
  paths refer immediately without provider configuration or budget access.
- Dream crisis detection covers follow-up answers and traditional Chinese. The
  question-generation stage also avoids the provider on crisis signals.
- Source cards require an adjacent exact quotation from the bounded injected
  corpus and its actual study-note title. The local notes are not authenticated
  editions or translations of original authors' books. Generated source metadata
  alone is never accepted as evidence. No bibliography is fabricated.
- Malformed/truncated structured dream responses raise a provider error; ordinary
  prose containing braces or the word `sources` is preserved.
- TCM oversized stream segments retain their bounded prefix instead of silently
  dropping a whole answer. Nonstream retry attempts share a 56-second deadline.

Verification: real-corpus assertions and mocked-provider tests in
`tests/verified/test_health_dream_restoration.py`, plus existing TCM/dream suites.
No live model call is needed. Generic upstream SSE framing/completion handling is
owned by `reading_agent.py` and reviewed separately during integration.

Limits: emergency keyword recognition is conservative, not a medical diagnostic
system. Prompt constraints cannot guarantee every possible provider output.
Source-card verification does not independently authenticate the historical
corpus or guarantee the entire generated essay is factually correct.
