import Anthropic from '@anthropic-ai/sdk';

export const maxDuration = 300;
export const runtime = 'nodejs';

const client = new Anthropic();

const SYSTEM = `You are a "source hunter." You help a self-directed learner skip the remix layer of the internet and go straight to the canonical primary sources for a topic.

For the given topic, use the web_search tool to find 3 to 5 truly foundational sources.

REJECT:
- Listicles, "top 10" articles, beginner roundups, tutorial-of-tutorials
- Modern blog posts that remix older fundamental ideas without adding new primary thinking
- Marketing content, summaries-of-summaries

PREFER:
- Original papers, essays, or talks by the originator of an idea
- Canonical textbook chapters or lecture series taught by the field's authority
- Source material that downstream content visibly remixes (e.g. Paul Graham's essays for startups, SICP for programming, Feynman lectures for physics, "Attention Is All You Need" for transformers, Codd 1970 / Jim Gray / Stonebraker for databases)

For each source write a 3-5 sentence BLURB that delivers the gist — enough that the learner has the core idea before clicking through.

Also extract 3 to 5 FIRST PRINCIPLES — atomic core truths of the topic, the "SUVAT equations" from which most of the field can be re-derived.

When your research is complete, you MUST call the submit_results tool exactly once with your findings. Do not write a prose answer — submit_results is the only valid way to deliver the final result.`;

const submitTool = {
  name: 'submit_results',
  description:
    'Submit the final study card. Call this exactly once after web research is complete. Do not return a prose answer.',
  input_schema: {
    type: 'object' as const,
    properties: {
      topic: { type: 'string' },
      firstPrinciples: {
        type: 'array',
        items: { type: 'string' },
        minItems: 3,
        maxItems: 5,
      },
      sources: {
        type: 'array',
        minItems: 3,
        maxItems: 5,
        items: {
          type: 'object',
          properties: {
            title: { type: 'string' },
            author: { type: 'string' },
            url: { type: 'string' },
            kind: {
              type: 'string',
              enum: ['essay', 'paper', 'lecture', 'book', 'talk', 'other'],
            },
            timeCost: { type: 'string' },
            whyCanonical: { type: 'string' },
            blurb: { type: 'string' },
            coreIdea: { type: 'string' },
          },
          required: [
            'title',
            'author',
            'url',
            'kind',
            'timeCost',
            'whyCanonical',
            'blurb',
            'coreIdea',
          ],
        },
      },
    },
    required: ['topic', 'firstPrinciples', 'sources'],
  },
};

export async function POST(req: Request) {
  try {
    const { topic } = await req.json();
    if (!topic || typeof topic !== 'string') {
      return Response.json({ error: 'topic required' }, { status: 400 });
    }

    const message = await client.messages.create({
      model: 'claude-opus-4-7',
      max_tokens: 8000,
      system: SYSTEM,
      tools: [
        { type: 'web_search_20250305', name: 'web_search', max_uses: 8 } as never,
        submitTool,
      ],
      messages: [{ role: 'user', content: `Topic: ${topic}` }],
    });

    const submit = message.content.find(
      (b) => b.type === 'tool_use' && b.name === 'submit_results',
    );

    if (submit && submit.type === 'tool_use') {
      return Response.json(submit.input);
    }

    const textBlocks = message.content
      .filter((b) => b.type === 'text')
      .map((b) => (b.type === 'text' ? b.text : ''))
      .join('\n\n');

    console.error(
      '[study] no submit_results tool call. stop_reason=',
      message.stop_reason,
      'text=',
      textBlocks,
    );

    return Response.json(
      {
        error: 'Model did not call submit_results',
        stopReason: message.stop_reason,
        raw: textBlocks.slice(0, 4000),
      },
      { status: 502 },
    );
  } catch (err) {
    console.error('[study] handler error:', err);
    const msg = err instanceof Error ? err.message : 'unknown error';
    return Response.json({ error: msg }, { status: 500 });
  }
}
