import { query, tool, createSdkMcpServer } from '@anthropic-ai/claude-agent-sdk';
import { z } from 'zod';

export const maxDuration = 300;
export const runtime = 'nodejs';

// Powered by the Claude Agent SDK, authenticated with a Pro/Max subscription
// (CLAUDE_CODE_OAUTH_TOKEN) instead of a billed API key. Usage draws from the
// subscription's limits. This requires the Claude Code CLI on the host, so the
// app is meant to run locally / self-hosted — it will NOT work on serverless.
const MODEL = 'claude-opus-4-8';

const SYSTEM = `You are a "source hunter." You help a self-directed learner skip the remix layer of the internet and go straight to the canonical primary sources for a topic.

For the given topic, use the WebSearch tool to find 3 to 5 truly foundational sources.

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

const sourceSchema = {
  title: z.string(),
  author: z.string(),
  url: z.string(),
  kind: z.enum(['essay', 'paper', 'lecture', 'book', 'talk', 'other']),
  timeCost: z.string(),
  whyCanonical: z.string(),
  blurb: z.string(),
  coreIdea: z.string(),
};

export async function POST(req: Request) {
  try {
    const { topic } = await req.json();
    if (!topic || typeof topic !== 'string') {
      return Response.json({ error: 'topic required' }, { status: 400 });
    }

    // The model delivers its answer by calling submit_results. We capture the
    // validated input here rather than parsing prose out of the transcript.
    let card: {
      topic: string;
      firstPrinciples: string[];
      sources: Array<Record<string, string>>;
    } | null = null;

    const studyServer = createSdkMcpServer({
      name: 'study',
      version: '1.0.0',
      tools: [
        tool(
          'submit_results',
          'Submit the final study card. Call this exactly once after web research is complete. Do not return a prose answer.',
          {
            topic: z.string(),
            firstPrinciples: z.array(z.string()).min(3).max(5),
            sources: z.array(z.object(sourceSchema)).min(3).max(5),
          },
          async (args) => {
            card = args;
            return { content: [{ type: 'text', text: 'Study card recorded.' }] };
          },
        ),
      ],
    });

    let resultMeta: { is_error?: boolean; subtype?: string } | null = null;

    for await (const message of query({
      prompt: `Topic: ${topic}`,
      options: {
        model: MODEL,
        systemPrompt: SYSTEM,
        mcpServers: { study: studyServer },
        // Whitelist exactly two tools: web research + the structured submit.
        // Everything else (file system, bash, etc.) stays disallowed.
        allowedTools: ['WebSearch', 'mcp__study__submit_results'],
        maxTurns: 20,
        // Non-interactive: never block on a permission prompt.
        permissionMode: 'bypassPermissions',
      },
    })) {
      if (message.type === 'result') {
        resultMeta = { is_error: message.is_error, subtype: message.subtype };
      }
    }

    if (card) {
      return Response.json(card);
    }

    console.error('[study] no submit_results tool call. result=', resultMeta);
    return Response.json(
      {
        error: 'Model did not call submit_results',
        stopReason: resultMeta?.subtype ?? 'unknown',
      },
      { status: 502 },
    );
  } catch (err) {
    console.error('[study] handler error:', err);
    const msg = err instanceof Error ? err.message : 'unknown error';
    return Response.json({ error: msg }, { status: 500 });
  }
}
