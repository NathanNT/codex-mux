# DeepSeek bulk reverse-engineering integration

## Decision

Use `deepseek-flash` for bulk reverse-engineering work. As of 16 September
2026, the official endpoint serves that identifier with DeepSeek V4.1 Flash,
supports the Responses API and tool calls, and offers the provider's highest
documented concurrency. The `deepseek-v4-pro` identifier is temporarily routed
to the same Flash backend, so it provides no useful production distinction.

Use reasoning effort `high` for mapping, tracing, and review. Reserve `max` for
a second pass over a small number of highly ranked candidates. Do not spend
`max` effort on first-pass classification.

## Native Codex roles

Native roles remain useful for three bounded interactive jobs at a time:

- `deepseek_mapper`: subsystem and trust-boundary mapping;
- `deepseek_tracer`: one producer-to-consumer control/data-flow trace;
- `deepseek_reviewer`: contradiction and guard review.

The compatibility patch propagates an external provider only for the exact
profile tuple `read-only`, `on-request`, and `auto_review`. Production profiles
must retain that tuple.

Current native parent-to-worker task payloads can arrive as opaque encrypted
envelopes even though worker-to-parent finals are plaintext. Use this durable
dispatch protocol:

1. Choose a `<job-id>` containing only lowercase letters, digits, and
   underscores so it is also a valid native `task_name`.
2. Write the complete assignment to
   `analysis/worker-results/<job-id>/task.md`.
3. Spawn the appropriate DeepSeek role with `task_name = <job-id>`.
4. The role derives the leaf job id from its canonical task name and reads the
   task file as the sole authority.
5. Sol persists the plaintext final response as
   `analysis/worker-results/<job-id>/result.md` before using it.

This protocol survives parent compaction, makes retries idempotent, and keeps
external workers read-only. Follow-ups update `task.md` and start a new bounded
turn; they do not depend on decrypting an inter-agent message.

## Bulk architecture

Do not implement 100-way bulk as 100 native Codex subagents. Native agent slots,
IDA sessions, and collaboration transport are scarce. Use a small controller
that calls the DeepSeek Responses API directly and persists every request and
response.

```text
hash-gated exporters
        -> evidence units on disk
        -> SQLite job queue
        -> 16..100 stateless DeepSeek requests
        -> JSON validation and deduplication
        -> ranked candidate index
        -> bounded native tracer/reviewer jobs
        -> Sol verification against original artifacts
```

### Evidence units

Each unit should contain only the context needed for one question:

- artifact identity and SHA-256;
- component, class/function, address or bytecode offset;
- original instructions or `javap` bytecode;
- exact types and relevant constants;
- bounded callers, callees, xrefs, and version delta;
- known producer or sink classification;
- maintained closure identifiers that must not be repeated.

IDA and Java exporters are parent-owned. Bulk workers consume immutable exports
and do not share an IDA session.

### Required JSON result

```json
{
  "job_id": "string",
  "candidate": true,
  "facts": [],
  "attacker_control": "none|weak|partial|full",
  "producer": "string|null",
  "sink": "string|null",
  "guards": [],
  "contradictions": [],
  "unresolved_edges": [],
  "evidence_refs": [],
  "confidence": 0.0,
  "next_check": "string|null"
}
```

Reject malformed output, missing evidence references, and conclusions based
only on decompiler prose. Model output is triage evidence, never a finding.

## Scaling gates

1. Run the file-backed native smoke test.
2. Benchmark the pipeline against the historical 0x90 chain without revealing
   its exact functions, plus several maintained negative closures.
3. Start the API runner at 16 concurrent requests.
4. Measure top-k recall, duplicate rate, malformed-output rate, cost, latency,
   and Sol verification time.
5. Increase to 32, 64, then 100 only while useful-candidate recall rises faster
   than verification cost.

The success criterion is not alert volume. The historical positive must appear
in the ranked shortlist, protected neighboring paths must be downgraded for the
correct guards, and Sol must spend less time discovering candidates than in the
current sequential workflow.

## Security and provenance

- Keep `DEEPSEEK_API_KEY` in the process environment.
- Do not put credentials, private data, or live tokens in evidence units.
- Record model id, reasoning effort, prompt hash, input hashes, timestamps, and
  response hash for every job.
- Keep workers read-only and stateless.
- Sol owns canonical documentation, severity, and every decisive original-
  artifact claim.
