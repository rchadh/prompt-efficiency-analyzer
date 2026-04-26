import { useState } from "react";

const DIMENSIONS = [
  { id: "clarity", label: "Instruction Clarity", abbr: "CLR", max: 20, color: "#f59e0b" },
  { id: "context", label: "Context Completeness", abbr: "CTX", max: 20, color: "#34d399" },
  { id: "specificity", label: "Output Specificity", abbr: "SPE", max: 20, color: "#60a5fa" },
  { id: "efficiency", label: "Token Efficiency", abbr: "TKN", max: 20, color: "#c084fc" },
  { id: "alignment", label: "Model Alignment", abbr: "ALN", max: 20, color: "#fb7185" },
];

const LLM_FACTORS = [
  { dim: "Context Window", claude: "200K — verbose OK", gpt4o: "128K — be selective", gemini: "1M — very permissive", llama: "8K–128K — concise", impact: "Long prompts penalized on smaller windows" },
  { dim: "Instruction Style", claude: "XML tags work best", gpt4o: "Markdown headers work best", gemini: "Natural language preferred", llama: "Simpler = more reliable", impact: "Format of instructions shifts score across models" },
  { dim: "Role Prompting", claude: "Moderate — resists strong personas", gpt4o: "High — roles boost performance", gemini: "Moderate effect", llama: "High for fine-tuned variants", impact: "'You are an expert' has variable ROI" },
  { dim: "Chain of Thought", claude: "Excellent (extended thinking)", gpt4o: "Strong with o1/o3", gemini: "Good", llama: "Variable by version", impact: "'Think step by step' has different ROI per model" },
  { dim: "Output Format", claude: "Excellent JSON/XML adherence", gpt4o: "Excellent structured outputs", gemini: "Good", llama: "Unreliable without fine-tuning", impact: "Format constraints score higher on reliable models" },
];

const GRADES = [
  { g: "S", r: "90–100", note: "Elite — production-ready, library-approved", c: "#f59e0b" },
  { g: "A", r: "80–89", note: "Strong — minor tuning needed", c: "#34d399" },
  { g: "B", r: "65–79", note: "Adequate — review before library entry", c: "#60a5fa" },
  { g: "C", r: "50–64", note: "Weak — significant improvement needed", c: "#c084fc" },
  { g: "D", r: "35–49", note: "Poor — likely to cause token waste", c: "#fb923c" },
  { g: "F", r: "0–34", note: "Broken — will produce poor/hallucinated results", c: "#fb7185" },
];

const SCORER_SYSTEM = `You are a Prompt Engineering Quality Analyzer for enterprise AI systems. Score the given prompt across 5 dimensions and return ONLY valid JSON — no markdown fences, no text outside the JSON object.

Dimensions (each 0–20, total 0–100):
1. clarity: How precisely the task is stated. Penalize vague verbs, ambiguous scope, missing who/what/when.
2. context: Domain context and role the model needs. Penalize missing domain, audience, or constraints.
3. specificity: Output format, length, structure constraints. Penalize open-ended requests with no format guidance.
4. efficiency: Signal-to-noise ratio. Penalize padding, redundant phrases, unnecessary pleasantries.
5. alignment: How well it leverages LLM strengths — examples, structured reasoning, step-by-step cues.

Return exactly this JSON structure:
{
  "scores": { "clarity": <0-20>, "context": <0-20>, "specificity": <0-20>, "efficiency": <0-20>, "alignment": <0-20> },
  "total": <0-100>,
  "grade": "<S|A|B|C|D|F>",
  "gradeLabel": "<Elite|Strong|Adequate|Weak|Poor|Broken>",
  "tokenEstimate": { "currentPromptTokens": <int>, "estimatedResponseTokens": <int>, "inefficiencyWaste": <0-100> },
  "dimensionFeedback": { "clarity": "<1-2 sentences>", "context": "<1-2 sentences>", "specificity": "<1-2 sentences>", "efficiency": "<1-2 sentences>", "alignment": "<1-2 sentences>" },
  "topIssues": ["<issue1>", "<issue2>", "<issue3>"],
  "improvedPrompt": "<rewritten version that would score 85+>",
  "improvementRationale": "<2-3 sentences on key changes made>",
  "llmVarianceNote": "<2 sentences on how this specific prompt would score differently on GPT-4o vs Claude vs Gemini>"
}`;

const EXAMPLES = [
  { label: "vague", text: "Explain machine learning" },
  { label: "weak", text: "Write a Python function to sort a list" },
  { label: "good-java", text: "You are a senior Java developer specializing in Spring Boot performance. Analyze the following REST controller method for N+1 query problems and missing database indexes. Return a JSON array where each item has: severity (HIGH/MEDIUM/LOW), description, and recommended_fix. Focus only on database performance issues.\n\n[PASTE CONTROLLER CODE HERE]" },
  { label: "good-fin", text: "As a SEBI-registered investment advisor, generate a risk disclosure statement for retail investors being onboarded for equity mutual fund SIP investments. Reference SEBI circular SEBI/HO/IMD/2021. Include: (1) market risk, (2) liquidity risk, (3) expense ratio impact. Format as 3 numbered paragraphs. Maximum 200 words. Formal legal tone." },
];

function gradeColor(g) {
  const m = { S: "#f59e0b", A: "#34d399", B: "#60a5fa", C: "#c084fc", D: "#fb923c", F: "#fb7185" };
  return m[g] || "#9ca3af";
}

function ScoreRing({ total, grade, color }) {
  const r = 46, cx = 62, cy = 62, circ = 2 * Math.PI * r;
  const dash = (total / 100) * circ;
  return (
    <svg width="124" height="124" viewBox="0 0 124 124">
      <circle cx={cx} cy={cy} r={r} fill="none" stroke="#1e2030" strokeWidth="7" />
      <circle cx={cx} cy={cy} r={r} fill="none" stroke={color} strokeWidth="7"
        strokeLinecap="round" strokeDasharray={`${dash} ${circ}`} strokeDashoffset={circ * 0.25}
        style={{ filter: `drop-shadow(0 0 7px ${color}60)`, transition: "stroke-dasharray 1s ease" }} />
      <text x={cx} y={cy - 7} textAnchor="middle" fill={color} style={{ fontSize: 24, fontFamily: "monospace", fontWeight: 700 }}>{total}</text>
      <text x={cx} y={cy + 10} textAnchor="middle" fill="#6b7280" style={{ fontSize: 10, fontFamily: "monospace" }}>/100</text>
      <text x={cx} y={cy + 26} textAnchor="middle" fill={color} style={{ fontSize: 13, fontFamily: "monospace", fontWeight: 700 }}>{grade}</text>
    </svg>
  );
}

export default function PromptScorer() {
  const [prompt, setPrompt] = useState("");
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [tab, setTab] = useState("analysis");
  const [history, setHistory] = useState([]);
  const [copied, setCopied] = useState(false);

  const wc = prompt.trim().split(/\s+/).filter(Boolean).length;
  const col = result ? gradeColor(result.grade) : "#f59e0b";

  async function analyze() {
    if (!prompt.trim() || loading) return;
    setLoading(true); setError(null); setResult(null); setTab("analysis");
    try {
      const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "claude-sonnet-4-20250514", max_tokens: 1000,
          system: SCORER_SYSTEM,
          messages: [{ role: "user", content: `Score this prompt:\n\n${prompt}` }],
        }),
      });
      const data = await res.json();
      const raw = data.content?.[0]?.text || "";
      const parsed = JSON.parse(raw.replace(/```json|```/g, "").trim());
      setResult(parsed);
      setHistory(h => [{
        id: Date.now(), preview: prompt.slice(0, 65) + (prompt.length > 65 ? "…" : ""),
        fullPrompt: prompt, result: parsed,
        time: new Date().toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" }),
      }, ...h].slice(0, 15));
    } catch (e) { setError("Scoring failed — check console for details."); }
    setLoading(false);
  }

  function copyImproved() {
    if (result?.improvedPrompt) {
      navigator.clipboard?.writeText(result.improvedPrompt);
      setCopied(true); setTimeout(() => setCopied(false), 2000);
    }
  }

  const S = {
    wrap: { minHeight: "100vh", background: "#0d0f18", color: "#e2e8f0", fontFamily: "'Segoe UI', system-ui, sans-serif" },
    hdr: { display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 22px", height: 50, borderBottom: "1px solid #1a1d2e", background: "#080a12", position: "sticky", top: 0, zIndex: 50 },
    grid: { display: "grid", gridTemplateColumns: "1fr 306px", minHeight: "calc(100vh - 50px)" },
    left: { padding: "20px 22px", borderRight: "1px solid #1a1d2e", display: "flex", flexDirection: "column", gap: 16 },
    right: { background: "#080a12", display: "flex", flexDirection: "column" },
    card: { background: "#080a12", border: "1px solid #1a1d2e", borderRadius: 10 },
    mono: (sz=10, col="#4b5563") => ({ fontFamily: "monospace", fontSize: sz, color: col, letterSpacing: "0.07em" }),
    label: { fontFamily: "monospace", fontSize: 10, color: "#4b5563", letterSpacing: "0.1em", marginBottom: 8 },
  };

  return (
    <div style={S.wrap}>
      <style>{`
        @keyframes spin{to{transform:rotate(360deg)}}
        @keyframes fadein{from{opacity:0;transform:translateY(7px)}to{opacity:1;transform:translateY(0)}}
        *{box-sizing:border-box}
        ::-webkit-scrollbar{width:4px}::-webkit-scrollbar-thumb{background:#1e2030;border-radius:2px}
        textarea:focus,button:focus{outline:none}
        .hr:hover{background:rgba(255,255,255,0.025)!important}
        .eb:hover{border-color:#f59e0b50!important;color:#9ca3af!important}
        .tb:hover{color:#f59e0b!important}
      `}</style>

      {/* Header */}
      <div style={S.hdr}>
        <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
          <div style={{ width: 26, height: 26, borderRadius: 6, background: "linear-gradient(135deg,#f59e0b,#ef4444)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 13, fontWeight: 800, color: "#080a12" }}>⌬</div>
          <span style={S.mono(13, "#e2e8f0")}>PROMPT EFFICIENCY ANALYZER</span>
          <span style={{ padding: "1px 7px", border: "1px solid #1e2030", borderRadius: 4, ...S.mono(9) }}>PES · v1.0</span>
        </div>
        <div style={{ display: "flex", gap: 14, ...S.mono(9) }}>
          {["5 DIMENSIONS", "100 PT SCALE", "CROSS-LLM ANALYSIS"].map(t => <span key={t}>{t}</span>)}
        </div>
      </div>

      <div style={S.grid}>
        {/* LEFT */}
        <div style={S.left}>
          {/* Input */}
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
              <span style={S.mono(10, "#4b5563")}>INPUT PROMPT</span>
              <span style={S.mono(10, "#374151")}>{wc}w · {prompt.length}c</span>
            </div>
            <div style={{ border: `1px solid ${loading ? "#f59e0b40" : "#1a1d2e"}`, borderRadius: 10, overflow: "hidden", background: "#080a12", transition: "border-color 0.2s" }}>
              <textarea value={prompt} onChange={e => setPrompt(e.target.value)}
                onKeyDown={e => e.key === "Enter" && e.ctrlKey && analyze()}
                placeholder={"Paste your prompt here for scoring…\n\nTip: Include role, context, output format, and constraints for a high score."}
                style={{ width: "100%", minHeight: 148, background: "transparent", border: "none", padding: "13px 15px", color: "#e2e8f0", fontSize: 13, lineHeight: 1.65, resize: "vertical" }} />
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "8px 12px", borderTop: "1px solid #1a1d2e", background: "#060810" }}>
                <div style={{ display: "flex", gap: 6 }}>
                  {EXAMPLES.map(ex => (
                    <button key={ex.label} className="eb" onClick={() => setPrompt(ex.text)}
                      style={{ padding: "3px 9px", borderRadius: 4, border: "1px solid #1e2030", background: "transparent", color: "#4b5563", ...S.mono(10), cursor: "pointer", transition: "all 0.15s" }}>
                      {ex.label}
                    </button>
                  ))}
                </div>
                <button onClick={analyze} disabled={loading || !prompt.trim()}
                  style={{ padding: "7px 18px", borderRadius: 7, background: loading || !prompt.trim() ? "#1e2030" : "linear-gradient(135deg,#f59e0b,#ef4444)", border: "none", color: loading || !prompt.trim() ? "#374151" : "#080a12", ...S.mono(11, "inherit"), fontWeight: 700, cursor: loading || !prompt.trim() ? "not-allowed" : "pointer", letterSpacing: "0.08em", display: "flex", alignItems: "center", gap: 6 }}>
                  {loading ? <><span style={{ display: "inline-block", animation: "spin 1s linear infinite" }}>⌬</span>SCORING…</> : "ANALYZE ⌬"}
                </button>
              </div>
            </div>
            <div style={{ marginTop: 5, ...S.mono(10, "#374151") }}>Ctrl+Enter to analyze</div>
          </div>

          {error && <div style={{ padding: "11px 14px", background: "rgba(251,113,133,0.08)", border: "1px solid rgba(251,113,133,0.25)", borderRadius: 8, fontSize: 12.5, color: "#fb7185" }}>{error}</div>}

          {/* Tabs */}
          {result && (
            <div style={{ animation: "fadein 0.4s ease" }}>
              <div style={{ display: "flex", gap: 0, borderBottom: "1px solid #1a1d2e", marginBottom: 16 }}>
                {["analysis", "improved", "variance"].map(t => (
                  <button key={t} className="tb" onClick={() => setTab(t)}
                    style={{ padding: "7px 16px", background: "transparent", border: "none", borderBottom: tab === t ? `2px solid ${col}` : "2px solid transparent", color: tab === t ? col : "#4b5563", ...S.mono(11), cursor: "pointer", textTransform: "uppercase", marginBottom: -1, letterSpacing: "0.05em", transition: "all 0.15s" }}>
                    {t === "analysis" ? "Analysis" : t === "improved" ? "Improved Prompt" : "LLM Variance"}
                  </button>
                ))}
              </div>

              {/* Analysis */}
              {tab === "analysis" && (
                <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
                  {/* Dimension rows */}
                  <div style={{ ...S.card, overflow: "hidden" }}>
                    <div style={{ padding: "9px 14px", borderBottom: "1px solid #1a1d2e", ...S.mono(10), letterSpacing: "0.1em" }}>DIMENSION BREAKDOWN</div>
                    {DIMENSIONS.map((d, i) => {
                      const val = result.scores[d.id];
                      return (
                        <div key={d.id} className="hr" style={{ padding: "11px 14px", borderBottom: i < 4 ? "1px solid #0d0f18" : "none", transition: "background 0.15s" }}>
                          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 5 }}>
                            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                              <span style={{ ...S.mono(10, d.color), fontWeight: 700, minWidth: 28 }}>{d.abbr}</span>
                              <span style={{ fontSize: 12.5, color: "#9ca3af" }}>{d.label}</span>
                            </div>
                            <span style={{ ...S.mono(13, d.color), fontWeight: 700 }}>{val}<span style={{ color: "#374151", fontSize: 10 }}>/{d.max}</span></span>
                          </div>
                          <div style={{ background: "#1a1d2e", borderRadius: 3, height: 4, marginBottom: 5 }}>
                            <div style={{ width: `${(val/d.max)*100}%`, height: "100%", borderRadius: 3, background: `linear-gradient(90deg,${d.color}70,${d.color})`, boxShadow: `0 0 5px ${d.color}40`, transition: "width 0.8s ease" }} />
                          </div>
                          <div style={{ fontSize: 11.5, color: "#6b7280", lineHeight: 1.5 }}>{result.dimensionFeedback[d.id]}</div>
                        </div>
                      );
                    })}
                  </div>

                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                    <div style={{ ...S.card, padding: "13px 14px" }}>
                      <div style={{ ...S.label }}>TOP ISSUES</div>
                      {result.topIssues.map((issue, i) => (
                        <div key={i} style={{ display: "flex", gap: 7, marginBottom: 7, alignItems: "flex-start" }}>
                          <span style={{ color: "#ef4444", fontSize: 9, marginTop: 3, flexShrink: 0 }}>◈</span>
                          <span style={{ fontSize: 12, color: "#9ca3af", lineHeight: 1.5 }}>{issue}</span>
                        </div>
                      ))}
                    </div>
                    <div style={{ ...S.card, padding: "13px 14px" }}>
                      <div style={{ ...S.label }}>TOKEN ESTIMATE</div>
                      {[
                        { l: "Prompt tokens", v: result.tokenEstimate.currentPromptTokens, c: "#60a5fa" },
                        { l: "Response tokens", v: result.tokenEstimate.estimatedResponseTokens, c: "#34d399" },
                        { l: "Waste %", v: result.tokenEstimate.inefficiencyWaste + "%", c: "#fb7185" },
                      ].map(r => (
                        <div key={r.l} style={{ display: "flex", justifyContent: "space-between", marginBottom: 9 }}>
                          <span style={{ fontSize: 12, color: "#6b7280" }}>{r.l}</span>
                          <span style={{ ...S.mono(12, r.c), fontWeight: 700 }}>{r.v}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {/* Improved */}
              {tab === "improved" && (
                <div style={{ display: "flex", flexDirection: "column", gap: 12, animation: "fadein 0.3s ease" }}>
                  <div style={{ ...S.card, padding: 15 }}>
                    <div style={{ ...S.label }}>OPTIMIZED PROMPT</div>
                    <div style={{ background: "#060810", border: "1px solid #1a1d2e", borderRadius: 7, padding: 13, fontSize: 13, lineHeight: 1.7, color: "#d1d5db", whiteSpace: "pre-wrap", wordBreak: "break-word", maxHeight: 280, overflowY: "auto" }}>
                      {result.improvedPrompt}
                    </div>
                    <button onClick={copyImproved} style={{ marginTop: 9, padding: "5px 12px", border: "1px solid #1e2030", borderRadius: 5, background: "transparent", color: copied ? "#34d399" : "#6b7280", ...S.mono(10), cursor: "pointer", transition: "all 0.15s" }}>
                      {copied ? "✓ COPIED" : "COPY PROMPT"}
                    </button>
                  </div>
                  <div style={{ ...S.card, padding: 15 }}>
                    <div style={{ ...S.label }}>WHY THESE CHANGES</div>
                    <div style={{ fontSize: 13, color: "#9ca3af", lineHeight: 1.65 }}>{result.improvementRationale}</div>
                  </div>
                </div>
              )}

              {/* LLM Variance */}
              {tab === "variance" && (
                <div style={{ display: "flex", flexDirection: "column", gap: 12, animation: "fadein 0.3s ease" }}>
                  <div style={{ ...S.card, padding: 15 }}>
                    <div style={{ ...S.label }}>VARIANCE FOR THIS PROMPT</div>
                    <div style={{ fontSize: 13, color: "#9ca3af", lineHeight: 1.65 }}>{result.llmVarianceNote}</div>
                  </div>
                  <div style={{ ...S.card, overflow: "hidden" }}>
                    <div style={{ padding: "9px 14px", borderBottom: "1px solid #1a1d2e", ...S.mono(10), letterSpacing: "0.1em" }}>CROSS-MODEL SCORING FACTORS</div>
                    <div style={{ overflowX: "auto" }}>
                      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 11.5 }}>
                        <thead>
                          <tr style={{ borderBottom: "1px solid #1a1d2e", background: "#060810" }}>
                            {["Dimension", "Claude", "GPT-4o", "Gemini", "LLaMA", "Score Impact"].map(h => (
                              <th key={h} style={{ padding: "7px 11px", textAlign: "left", ...S.mono(9), fontWeight: 600 }}>{h}</th>
                            ))}
                          </tr>
                        </thead>
                        <tbody>
                          {LLM_FACTORS.map((row, i) => (
                            <tr key={i} className="hr" style={{ borderBottom: "1px solid #0d0f18", transition: "background 0.15s" }}>
                              <td style={{ padding: "8px 11px", color: "#f59e0b", ...S.mono(11), fontWeight: 700 }}>{row.dim}</td>
                              <td style={{ padding: "8px 11px", color: "#34d399", fontSize: 11 }}>{row.claude}</td>
                              <td style={{ padding: "8px 11px", color: "#60a5fa", fontSize: 11 }}>{row.gpt4o}</td>
                              <td style={{ padding: "8px 11px", color: "#c084fc", fontSize: 11 }}>{row.gemini}</td>
                              <td style={{ padding: "8px 11px", color: "#fb923c", fontSize: 11 }}>{row.llama}</td>
                              <td style={{ padding: "8px 11px", color: "#6b7280", fontSize: 11 }}>{row.impact}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                  <div style={{ background: "rgba(245,158,11,0.05)", border: "1px solid rgba(245,158,11,0.2)", borderRadius: 10, padding: "13px 15px" }}>
                    <div style={{ ...S.mono(10, "#f59e0b"), marginBottom: 7, letterSpacing: "0.08em" }}>ENTERPRISE IMPLICATION</div>
                    <div style={{ fontSize: 12.5, color: "#9ca3af", lineHeight: 1.65 }}>
                      A prompt scoring 85/100 on Claude may score 62/100 on LLaMA-3 due to context window and instruction-following differences.
                      Tag each library prompt with its target model family and re-evaluate scores on every model upgrade.
                      Consider maintaining model-specific variants of critical system prompts rather than a single universal version.
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}

          {!result && !loading && (
            <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 10, padding: 32, textAlign: "center" }}>
              <div style={{ fontSize: 38, opacity: 0.1 }}>⌬</div>
              <div style={{ ...S.mono(11, "#2d3044"), letterSpacing: "0.1em" }}>PASTE A PROMPT AND CLICK ANALYZE</div>
              <div style={{ fontSize: 12, color: "#2d3044", maxWidth: 340, lineHeight: 1.6 }}>Scores across 5 dimensions: Clarity · Context · Specificity · Token Efficiency · Model Alignment</div>
            </div>
          )}
        </div>

        {/* RIGHT */}
        <div style={S.right}>
          {/* Score section */}
          <div style={{ padding: "18px 18px 14px", borderBottom: "1px solid #1a1d2e" }}>
            <div style={{ ...S.label }}>EFFICIENCY SCORE</div>
            {result ? (
              <div style={{ animation: "fadein 0.5s ease" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 14, marginBottom: 14 }}>
                  <ScoreRing total={result.total} grade={result.grade} color={col} />
                  <div>
                    <div style={{ ...S.mono(20, col), fontWeight: 800, lineHeight: 1 }}>{result.grade}</div>
                    <div style={{ ...S.mono(12, "#6b7280"), marginTop: 4 }}>{result.gradeLabel}</div>
                    <div style={{ ...S.mono(11, "#374151"), marginTop: 8 }}>
                      {result.total >= 85 ? "✓ Library-ready" : result.total >= 65 ? "⚠ Needs review" : "✗ Revise before use"}
                    </div>
                  </div>
                </div>
                {/* Mini bars */}
                <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
                  {DIMENSIONS.map(d => (
                    <div key={d.id} style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <span style={{ ...S.mono(9, d.color), fontWeight: 700, minWidth: 26 }}>{d.abbr}</span>
                      <div style={{ flex: 1, background: "#1a1d2e", borderRadius: 2, height: 5 }}>
                        <div style={{ width: `${(result.scores[d.id]/d.max)*100}%`, height: "100%", borderRadius: 2, background: d.color, opacity: 0.8, transition: "width 0.8s ease" }} />
                      </div>
                      <span style={{ ...S.mono(10, d.color), fontWeight: 600, minWidth: 18, textAlign: "right" }}>{result.scores[d.id]}</span>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div style={{ display: "flex", justifyContent: "center", alignItems: "center", height: 100 }}>
                <span style={{ ...S.mono(10, "#1e2030"), letterSpacing: "0.1em" }}>{loading ? "SCANNING…" : "— AWAITING INPUT —"}</span>
              </div>
            )}
          </div>

          {/* Grade reference */}
          <div style={{ padding: "14px 18px", borderBottom: "1px solid #1a1d2e" }}>
            <div style={{ ...S.label }}>GRADE REFERENCE</div>
            {GRADES.map(row => (
              <div key={row.g} style={{ display: "flex", alignItems: "flex-start", gap: 8, marginBottom: 5, padding: "4px 7px", borderRadius: 5, background: result?.grade === row.g ? `${row.c}10` : "transparent", border: result?.grade === row.g ? `1px solid ${row.c}25` : "1px solid transparent", transition: "all 0.2s" }}>
                <span style={{ ...S.mono(11, row.c), fontWeight: 800, minWidth: 14 }}>{row.g}</span>
                <span style={{ ...S.mono(10, "#374151"), minWidth: 46, marginTop: 1 }}>{row.r}</span>
                <span style={{ fontSize: 11, color: "#4b5563", flex: 1, lineHeight: 1.4 }}>{row.note}</span>
              </div>
            ))}
          </div>

          {/* History */}
          <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <div style={{ padding: "10px 18px 7px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ ...S.mono(10), letterSpacing: "0.1em" }}>HISTORY</span>
              {history.length > 0 && <span onClick={() => setHistory([])} style={{ ...S.mono(9, "#374151"), cursor: "pointer" }}>CLEAR</span>}
            </div>
            <div style={{ flex: 1, overflowY: "auto", padding: "0 10px 12px" }}>
              {history.length === 0 ? (
                <div style={{ ...S.mono(10, "#1e2030"), textAlign: "center", paddingTop: 16, letterSpacing: "0.1em" }}>— NO HISTORY —</div>
              ) : (
                history.map(item => {
                  const ic = gradeColor(item.result.grade);
                  const isActive = result && item.result === result;
                  return (
                    <div key={item.id} onClick={() => { setPrompt(item.fullPrompt); setResult(item.result); setTab("analysis"); }}
                      style={{ padding: "9px 12px", marginBottom: 5, borderRadius: 7, cursor: "pointer", background: isActive ? `${ic}10` : "rgba(255,255,255,0.015)", border: `1px solid ${isActive ? ic + "35" : "#1a1d2e"}`, transition: "all 0.15s" }}>
                      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 3 }}>
                        <span style={{ ...S.mono(11, ic), fontWeight: 700 }}>{item.result.grade} — {item.result.total}/100</span>
                        <span style={{ ...S.mono(10, "#374151") }}>{item.time}</span>
                      </div>
                      <div style={{ fontSize: 11, color: "#4b5563", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{item.preview}</div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
