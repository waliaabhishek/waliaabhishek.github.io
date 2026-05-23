---
title: "The Design Doc Is the Prompt"
date: 2026-05-23
draft: false
tags: ["ai-development", "design-docs", "software-engineering", "workflow"]
categories: ["engineering"]
description: "How writing specs instead of chat messages let one engineer ship 400+ features across three codebases in two months."
---

AI-assisted development is a multi-pronged thought process. It is a prompting optimization game as well as a model personality/tendency and a big rework problem.

The model based on its tendency could decide if it wants to take the prompt too literally or maybe just an outline of what you want and still ignore some pieces that it doesn't want to care about. GPT 5.5 and Opus 4.7 are prime examples for the divergence in behaviour. Opus is more exploratory in nature while GPT 5.5 takes its instructions pretty seriously (as of today). Once you understand how different models behave, you may unlock the power to work with them as a partner by using the subtle persuasion techniques. I have been dealing with these subtleties of different models for the past 8-10 months of my journey evolving my workflow with them (not the exact same versions, but you catch the drift).

Once you solve the prompting dilemma, then you spend the following days and nights thinking how the code is absolutely correct in how it was implemented yet it still doesn't fit the architecture and the design of how and where you would have imagined it to be. It is correct, yet it needs extra cycles to rewrite or guide the agent to do it properly. I burned a lot of hours on this loop before I figured out what was actually going on.

The AI wasn't failing at coding but it was failing at inferring my intent from that one/many chat message(s). No single prompt carries enough context once a project has real module boundaries, real constraints, real dependencies between components. I was asking it to guess a spec from a conversation. This is where I realized that agents are extremely good at implementing a spec but it's just pretty mediocre at inferring one.

The realization came from a mistake to be really honest. I stumbled upon it while prompting my agent (rather non-eloquently at that - majority of it is speech to text with software using whisper from OpenAI). Nonetheless, this forced me to rethink how I was prompting and I started building a workflow around design docs. Over about two months, across three production codebases - a data pipeline orchestrator in Go (now abandoned unfortunately - another one of the half done projects as a developer :D ), a cost allocation engine in Python (Chitragupta - live and available) & a Kafka client library in Rust (Ongoing - available soonish), that shift produced over 300 design documents and 400+ shipped features with me as the solo engineer. The code started (almost) behaving the way I needed it to. The specs were the result of long conversations with Opus and GPT which we kept refining over time. The spec made the difference in what was delivered and how.

## TL;DR

If you're here for the takeaways and don't want the full walkthrough, here's the short version. Take what fits. Leave the rest.

1. **Write a spec before you prompt.** Even half a page with goals, non-goals, interfaces, and edge cases changes the output quality. Doesn't need to be formal. Needs to be specific. Don't hesitate to ask the thinking models to even write the first draft for you if you are shy of typing like me. But READ IT and modify it yourself if you ask the agent to create the first draft for you. 

2. **Force a DRY check.** One section in the doc: "what already exists that does something similar?" Grep/RipGrep/AST search/Graph search - use whatever works best for you before creating. This alone prevents the most common source of AI-generated bloat - the same structure everywhere. This also promotes reusability. 

3. **Split review into roles.** Multiple siloed perspectives (correctness vs. operability vs quality vs performance etc) catch more than a single agent can in one generic pass. The structure matters more than the count. Also, be deliberate about not spinning up too many sub agents. This will add to your token cost and increase it manifold if you decide to go on a spending spree. You have been warned.

4. **Track deferred work explicitly.** A markdown file or a task somewhere in your preferred backlog tracker. DO NOT skip on this. Tech debt and pot holes will probably be everywhere as the agents cannot think deeply like a developer can for corner cases every time. You can be explicit in instructions for the system to not fix potholes immediately. They can be deferred items in tech debt for you to resolve when the agent finishes the existing tasks. This will prevent context bloat and derailment. Four columns: what, where, why deferred, trigger to revisit. Review it each session. The format doesn't matter but the rigor will keep the code from being a mess long term. 

5. **Treat the design doc as the handoff.** Between sessions, between agents, between today-you and next-month-you. It's the artifact that survives context loss. Be religious about it. 

The rest of the post is the how and why behind each of these.

## A spec, not a conversation

To be clear: I did not hand-write 300+ design docs. That's not physically possible in two months. What I do is provide the intent. The scope, the constraints, the goals, the things I know about the existing codebase that the AI doesn't. Then an agent team fleshes that out into a full design doc, grepping the codebase for existing patterns, proposing interfaces, mapping edge cases. I review the output, push back where it's wrong, and approve when it's right. The final design doc is AI-generated too. Just not from a chat prompt. From a structured creation workflow (a skill) with specific roles for sub agents and me rambling on for minutes before we even write a single word in that markdown file.

Each section in a design doc exists because it answers a question the AI will need answered during implementation. I didn't start with this template but it evolved over the first couple of weeks as I kept hitting the same problem.

**Goals and non-goals.** Non-goals might be more important than goals, actually. If you don't explicitly say "multi-tenancy is a non-goal," you may end up getting a multi-tenant implementation. AI tends to over-build, so the fence around the field that you create matters more than the field itself.

**Existing infrastructure analysis.** This one I added after about two weeks of finding DRY violations everywhere. AI loves inventing new types, new abstractions, new utility functions -- which may ironically be the same it invented for some other work 5 sessions ago. It doesn't know what already exists in your codebase unless it knows about it. So every design doc now has a section that forces a find before creating. Each existing pattern potentially gets reused over time. Skip this section and you end up with three slightly different validation helpers in the same project.

**Interface signatures and config schema.** The actual contract. Exact method names, parameters, return types. Exact YAML field names, types, defaults. Not "a function that processes records." The actual signature: `func (e *Engine) Process(ctx context.Context, batch []Record) ([]Result, error)`. The AI implements it verbatim. No guessing, no "I interpreted your intent as..."

**Behavior tables.** What happens when the input is empty. When a dependency times out. When two operations conflict. AI handles happy paths fine. Edge cases are where vague inputs produce vague code.

What does NOT go in: implementation code. No pseudocode, no step-by-step how-to. The doc specifies the what and the why. Agents will figure out the how during the implementation phase. The moment you/agent start writing pseudocode in the design doc, it basically adds bloat to the context, and usually constrains it to that model rather than letting it find a better/novel path.

Size discipline: 10-20 KB. Over 40 KB means implementation is leaking in. Under 5 KB means you haven't thought it through. This has been my personal yardstick. Your mileage may vary.

The contrast with chat-prompting is pretty stark. A prompt says "add graceful shutdown to the pipeline." A design doc says: three-phase shutdown (drain in-flight batches, flush checkpoints, stop plugins), force shutdown on second SIGINT, atomic counter for batch tracking, checkpoint flush must use a fresh context not the cancelled parent. See how our thought out feature design gave us a much more detailed and optimized implementation ?

## Who reviews the reviewer?

So agents created the design doc and agents implemented it. The same AI that proposed the interfaces is the one coding against them. Who catches the blind spots?

If you're a solo engineer, the answer is usually: you catch the problems during testing, when they're expensive to fix. That's where I was for the first few weeks. Agents reviewing their own output doesn't help much. One generic "review this" pass catches formatting issues and obvious bugs. It doesn't catch architectural problems because the same assumptions that produced the design are the ones doing the reviewing.

What actually worked: adversarial review with domain-specific roles. Not one reviewer doing one pass. Multiple reviewers, each looking for different things all with their own fresh context and the sole goal to review the code from a specific perspective.

One reviewer cares about contracts. Interfaces, data models, API shape. "Does this type already exist somewhere? Does the return type match what the caller expects?" Another cares about architecture. Failure modes, concurrency, lifecycle. "What happens when this crashes mid-write? Is this goroutine cleaned up on shutdown?" A third cares about operations. Observability, testing, deployment. "How do you know this is working in production?"

Each one issues numbered findings with severity. An architect role addresses them by updating the design doc. Loop until resolved. A final gate reviewer does a deep cross-cutting check before signing off.

On the Rust project, one of these review cycles caught a lifetime conflict in a connection pool that crossed an async boundary. The contracts reviewer flagged the type issue. The architecture reviewer flagged the shutdown ordering problem it would cause. Neither concern alone would have surfaced the full picture. That's the thing, right? It's not about having more reviewers but about structured disagreement. One perspective optimizing for correctness pushes against one optimizing for simplicity. Those adversarial reviews are what a real team provides. I'm simulating the argument, not the headcount.

This is obviously overkill for a 200-line CLI tool. For the Kafka client, which has about 10 crates with layered dependencies, it was worth every cycle. Pick your battles on this one.

## The output

Across all three projects:

| | Go | Python | Rust |
|---|---|---|---|
| Design documents | ~120 | ~200 | 25 deep specs |
| Features shipped | 107 | 153 | ~200 chunks |
| Quality tracking | DRY gates | 13 tech debt items with triggers | 188 audit findings with resolution proof |

All three projects followed the same approach, with subtle differences as I evolved the process. Each stage stays small: 
* A design doc is 10-20 KB. 
* A review cycle runs in maybe 15 minutes. 
* An implementation session has a clear spec to work against instead of a vague feature description. 

No single step requires holding the whole project in your head. That's what made the volume possible.


Session continuity turned out to be a bigger deal than I expected. This has evolved since I originally drafted this blog as well. 

Old: Every project had a status file that tracks current phase, what's done, what's blocked, what's next. Each session starts by reading it, ends by updating it. AI picks up exactly where the last session left off. Without this, every session starts from scratch and you burn half your time just re-orienting. For multi-month projects, this is the difference between viable and not.

New: The old method had a really big flaw which surfaced overtime. Token bloat. The Markdown files were amazing to carry the status for small stints, but for bigger projects like a Kafka Client it became too big. So much so that my initial session start would bloat the context to 70k tokens without even doing a single thing. I have since migrated to Backlog.md. It is a task management system that maintains everything in pure markdown. So now, every new session works on a tightly scoped task from markdown which has a design doc attached to it. This helped me reduce the context bloat from 70k tokens at the beginning to about 25k tokens to start off the session. Still feels bloated, but it gives my agent all the context that it needs to that one specific task and nothing more. 

The audit tracking was another surprise. On the Rust project, I ran an external audit after I'd considered nine phases of implementation "done." It surfaced 94 additional findings. Stubs that weren't wired up. Security features that were defined but not connected. Config that was parsed but never propagated. Tests that passed but didn't actually validate what they claimed to. **"Done" was not done.** Having a registry where every finding gets logged with a trigger condition for resolution meant nothing could quietly slip through. Items get resolved with proof (date, commit, test count) or closed as invalid if the audit was wrong. Both are fine. The point is nothing goes unexamined.

## What didn't work

Some design docs were over-specified and the implementation diverged anyway. The doc became stale immediately. I don't have a clean solution for keeping docs updated post-implementation. The code is the source of truth. The doc is a point-in-time artifact. Not ideal, but acceptable.

The review agents catch structural issues well. They do not catch "this is the wrong feature to build." Product judgment is still on you. No amount of process automation replaces knowing what to build next.

And the upfront cost is real. First few weeks felt slow. I was directing design docs for features I could have just built directly. The creation workflow, the review cycles, the template iterations. It felt like overhead on top of overhead. In the next few weeks, the docs were producing cleaner implementations with fewer correction cycles. Now, the velocity is something I couldn't have reached any other way. If you bail after week one because it feels like process theater, you'll never see it.

This workflow is model-agnostic, language-agnostic, tool-agnostic. The design doc is a markdown file. The review roles are a prompting pattern. The status tracking is a text file. I built custom infrastructure around all of it because the volume demanded it, but the core idea works with a text editor and whatever AI tool you're already using.

Your mileage will vary depending on project size and how much architecture you're dealing with. For greenfield work with clear module boundaries, this is a huge win. For legacy codebases with undocumented assumptions, the design doc phase gets harder because the existing infrastructure analysis requires understanding code that nobody fully understands.
