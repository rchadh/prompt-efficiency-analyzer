# ⌬ Prompt Efficiency Analyzer (PES)

A developer tool that scores any AI prompt across 5 dimensions, identifies inefficiencies, estimates token waste, generates an optimized version, and highlights how the same prompt would perform differently across LLMs.

**Live:** [https://rchadh.github.io/prompt-efficiency-analyzer/](https://rchadh.github.io/prompt-efficiency-analyzer/)

---

## Why This Exists

Vague, unstructured prompts cost real money. In enterprise environments with 25+ engineers each using AI coding assistants, LLM-powered agents, and chat interfaces daily, the token waste from poorly written prompts compounds fast.

A prompt that gets the right answer on the first try can be 5–10x more token-efficient than an ad-hoc conversation where the developer spends 3–4 follow-ups teaching the model context it should have had from the start.

PES provides an objective, measurable quality gate — a score between 0 and 100 — that turns prompt quality from a subjective opinion into a data point.

---

## How It Works

### Architecture

```
Browser (GitHub Pages)
    │
    │ POST — prompt text only, no API key
    ▼
Cloudflare Worker (reverse proxy)
    │
    │ Injects API key server-side
    ▼
Anthropic Claude API
    │
    │ Returns structured JSON score
    ▼
Browser renders results
```

The app is a React single-page application hosted on GitHub Pages as static HTML/JS/CSS. All AI processing happens via the Anthropic API, proxied through a Cloudflare Worker that holds the API key securely — no secrets exist in the frontend code.

### Scoring Flow

1. **User pastes a prompt** into the input area
2. **The prompt is sent** to Claude Sonnet 4 with a specialized scoring system prompt
3. **Claude analyzes** the prompt across 5 weighted dimensions and returns a structured JSON response
4. **The UI renders** the score breakdown, feedback, improved prompt, token estimates, and LLM variance analysis

---

## The 5 Scoring Dimensions

Each dimension is scored 0–20 points, totalling 0–100.

### CLR — Instruction Clarity (0–20)

Measures how precisely the task is stated. The scorer evaluates verb strength, scope definition, and ambiguity.

**What scores high:** Specific action verbs ("Analyze", "Generate", "Return"), clear scope boundaries ("focus only on database performance"), explicit what/who/when.

**What gets penalized:** Vague verbs ("help me with", "tell me about"), unbounded scope, missing subject or object.

**Example gap:**
- Weak (4/20): `"Help me with my code"`
- Strong (18/20): `"Analyze the following REST controller method for N+1 query problems"`

### CTX — Context Completeness (0–20)

Measures whether the prompt provides the domain context, role, and background information the model needs to avoid hallucination and produce accurate results.

**What scores high:** Role definition ("You are a senior Java architect"), domain specifics ("Spring Boot 3.x, WebFlux, AWS EKS"), audience context ("for a retail investor onboarding flow").

**What gets penalized:** No role or persona, missing domain ("review my code" — what language? what framework?), no audience context for content generation tasks.

**Example gap:**
- Weak (3/20): `"Write a risk disclosure"`
- Strong (19/20): `"As a SEBI-registered investment advisor, generate a risk disclosure statement for retail investors being onboarded for equity mutual fund SIP investments. Reference SEBI circular SEBI/HO/IMD/2021."`

### SPE — Output Specificity (0–20)

Measures how well the prompt constrains the expected output — format, structure, length, and what to include or exclude.

**What scores high:** Explicit format ("Return a JSON array"), structural constraints ("3 numbered paragraphs, max 75 words each"), inclusion/exclusion lists ("Do not include fund recommendations").

**What gets penalized:** Open-ended requests ("explain it"), no format guidance, no length constraints, missing exclusion criteria.

**Example gap:**
- Weak (2/20): `"Explain machine learning"`
- Strong (17/20): `"Return your findings as a JSON array. Each item must have: severity (HIGH/MEDIUM/LOW), description (max 2 sentences), and fix (max 3 sentences). Focus only on performance issues. Ignore code style."`

### TKN — Token Efficiency (0–20)

Measures the signal-to-noise ratio of the prompt itself. Every unnecessary word in the prompt costs tokens on input, and vague prompts cause longer, more exploratory responses — costing tokens on output too.

**What scores high:** Dense, information-rich prompts with no filler. Every sentence adds either context, a constraint, or a requirement.

**What gets penalized:** Pleasantries ("Could you please kindly help me..."), redundant rephrasing ("I want you to... What I'm looking for is..."), unnecessary preamble ("I've been working on this project and...").

**Example gap:**
- Weak (5/20): `"Hi there! I've been working on a project and I was wondering if you could possibly help me out with reviewing some code? I'd really appreciate it if you could take a look."`
- Strong (18/20): `"Review this Spring Boot controller for N+1 queries and missing indexes. Return JSON: [{severity, description, fix}]."`

### ALN — Model Alignment (0–20)

Measures how well the prompt leverages known LLM strengths — structured reasoning cues, examples, step-by-step instructions, and format anchoring.

**What scores high:** Step-by-step reasoning cues ("First analyze X, then evaluate Y"), few-shot examples, structured delimiters (XML tags, markdown headers), explicit reasoning chains.

**What gets penalized:** Prompts that work against model tendencies, no structure to guide reasoning, missing examples where they would help, format requests the model is known to struggle with.

---

## Grading Scale

| Grade | Score | Label | Meaning |
|-------|-------|-------|---------|
| **S** | 90–100 | Elite | Production-ready. Suitable for prompt library with no changes. |
| **A** | 80–89 | Strong | Minor tuning needed. Review feedback and adjust 1–2 dimensions. |
| **B** | 65–79 | Adequate | Functional but leaves value on the table. Review before library entry. |
| **C** | 50–64 | Weak | Will produce inconsistent results. Significant rework recommended. |
| **D** | 35–49 | Poor | Likely to cause substantial token waste and require multiple follow-ups. |
| **F** | 0–34 | Broken | Will produce poor, hallucinated, or off-target results. Rewrite entirely. |

---

## Token Efficiency Estimation

The analyzer provides three token-related metrics for each scored prompt:

### Current Prompt Tokens
Estimated input token count for the prompt as written. This directly impacts API cost — every token in the prompt is billed on input.

### Estimated Response Tokens
Projected output token count based on how the prompt is likely to be interpreted. Vague prompts tend to generate longer, more exploratory responses because the model hedges across multiple interpretations. Specific prompts generate shorter, targeted responses.

### Inefficiency Waste (%)
The percentage of total tokens (input + output) that could be eliminated with a better-written prompt. This factors in:

- **Prompt-side waste:** Redundant phrasing, pleasantries, unnecessary context that doesn't influence the output
- **Response-side waste:** Additional tokens the model generates because the prompt didn't constrain the output format, length, or scope
- **Retry waste:** The implicit cost of follow-up messages that wouldn't be needed if the original prompt was clearer

**How to interpret the waste percentage:**

| Waste % | Interpretation |
|---------|----------------|
| 0–10% | Efficient — minimal room for improvement |
| 11–25% | Moderate — tightening format and constraints would help |
| 26–50% | Significant — prompt is generating unnecessary verbosity |
| 51%+ | Severe — prompt is likely causing multi-turn back-and-forth |

**Real cost impact example:**
A team of 25 engineers, each sending ~50 prompts/day with an average waste of 30%, at Claude Sonnet pricing ($3/M input, $15/M output), could be wasting $500–2,000/month in unnecessary token consumption. PES helps identify and eliminate this waste at the source.

---

## Cross-LLM Variance Analysis

The same prompt does not score equally across all models. The **LLM Variance** tab shows how the scored prompt would perform differently on major model families.

### Why Scores Vary

| Factor | Claude | GPT-4o | Gemini | LLaMA |
|--------|--------|--------|--------|-------|
| **Context window** | 200K — verbose context is cheap | 128K — be more selective | 1M — very permissive | 8K–128K — must be concise |
| **Instruction style** | Excels with XML tags and structured delimiters | Excels with markdown headers and numbered lists | Prefers natural language flow | Simpler instructions = more reliable |
| **Role prompting** | Moderate — resists strong persona adoption | High — roles meaningfully boost output quality | Moderate effect | High for fine-tuned variants |
| **Chain of thought** | Excellent — extended thinking mode available | Strong with o1/o3 reasoning models | Good | Variable by model version |
| **Output format** | Excellent JSON/XML adherence | Excellent structured output support | Good | Unreliable without fine-tuning |

### Practical Impact

A prompt scoring **85/100 on Claude** might score **62/100 on LLaMA-3** because:
- The prompt uses XML tags for structure (Claude strength, LLaMA weakness)
- It includes 2,000 tokens of context (fine for Claude's 200K window, potentially wasteful for an 8K LLaMA deployment)
- It requests JSON output with nested objects (Claude adheres reliably, LLaMA may break format)

### Enterprise Implication

When maintaining a prompt library or repository, each prompt should be tagged with its target model family. When the organization upgrades models (e.g., Claude Sonnet 3.5 → Sonnet 4), all Tier 1 governed prompts should be re-scored to detect performance drift before it reaches production.

---

## Improved Prompt Generation

For every analyzed prompt, PES generates a rewritten version targeting a score of 85+. The **Improved Prompt** tab shows:

- **The optimized prompt** — ready to copy and use, with all five dimensions strengthened
- **Improvement rationale** — explains what specific changes were made and why each change improves the score

The rewriter focuses on:
1. Adding missing role/context if the original lacked it
2. Tightening output format constraints
3. Removing filler and redundancy
4. Adding structure cues that improve model alignment
5. Adding explicit exclusion criteria to prevent scope creep

---

## Sample Prompts for Testing

### Grade F — Broken (~15/100)
```
Tell me about APIs.
```

### Grade C — Weak (~52/100)
```
I need help reviewing my Spring Boot REST API code for problems.
Can you look at it and tell me what's wrong? I'm a Java developer
and want to improve the code quality.
```

### Grade A — Strong (~85/100)
```
You are a senior Java architect with 10 years of Spring Boot
and microservices experience. Review the following REST controller
method and identify issues across these 3 areas only:
1. Performance (N+1 queries, missing indexes, inefficient loops)
2. Security (missing auth checks, input validation gaps)
3. Error handling (missing exception handling, wrong HTTP status codes)

Return your findings as a JSON array. Each item must have:
- category: "PERFORMANCE" | "SECURITY" | "ERROR_HANDLING"
- severity: "HIGH" | "MEDIUM" | "LOW"
- description: what the issue is (max 2 sentences)
- fix: concrete recommendation (max 3 sentences)

Ignore code style, naming conventions, and formatting issues.
```

### Grade S — Elite (~94/100)
```
You are a SEBI-registered investment advisor and compliance officer
at a Fortune 500 financial services firm in India.

Task: Generate a client-facing risk disclosure statement for retail
investors being onboarded onto an equity mutual fund SIP product.

Regulatory requirements (mandatory):
1. Market risk — reference SEBI circular SEBI/HO/IMD/DF3/CIR/P/2021/573
2. Liquidity risk — specifically for open-ended vs closed-ended funds
3. Expense ratio impact — illustrate with numeric example assuming
   1% vs 2.5% expense ratio over 10-year horizon

Output format:
- 3 numbered paragraphs, one per risk type
- Each paragraph: maximum 75 words
- Tone: formal legal language, no marketing, no superlatives
- End with: "Past performance does not guarantee future returns."

Do not include: fund recommendations, specific fund names, return projections.
```

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Frontend | React (Vite build) |
| Hosting | GitHub Pages (static) |
| AI Engine | Anthropic Claude Sonnet 4 |
| API Proxy | Cloudflare Worker (secures API key) |
| Scoring | 5-dimension JSON analysis via structured system prompt |

---

## Local Development

```bash
git clone https://github.com/rchadh/prompt-efficiency-analyzer.git
cd prompt-efficiency-analyzer
npm install
npm run dev
```

Opens at `http://localhost:5173`

---

## License

MIT

---

*Built by Rahul Chadha as part of a broader exploration into enterprise AI governance*
