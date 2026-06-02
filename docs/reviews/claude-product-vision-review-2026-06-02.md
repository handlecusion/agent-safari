Review done. Changes = 3 new process docs + README pointer (4 lines). No code. CLAUDE.md and reviewer-agent showed empty diff = unchanged this turn. All cross-refs resolve. One real risk: ROADMAP.md and DEVELOPMENT_PHASES.md now both track phases with different numbering.

---

## Product-Vision Review — uncommitted docs/process changes

**Verdict:** PASS_WITH_NOTES

**Phase alignment**
- Changes are pure documentation/process — no phase code touched. Maps to the *Operating Model* step "write/update the phase section before coding" in the new `DEVELOPMENT_PHASES.md` itself.
- Phase status claims match reality per wiki bundle: Phase 0 & 1 `Done through v0.0.6`, Phase 2 `Active` (native click/actionability remaining). Consistent.
- Priority→Phase mapping is coherent though never stated explicitly: Vision Priority 1 (native click) = Phase 2 remaining; Priority 2 (capture metadata) = Phase 3; Priority 3 (session model) = Phase 5 `Gated`. Correct, just implicit.

**Vision alignment**
- Strong. All three docs are faithful restatements of the eyes/hands/evidence/failure-explanation frame. No capability invented beyond vision.
- Scope boundaries preserved verbatim across all three: no CDP parity, no default HAR/proxy, no WebAuthn, no true multi-tab/profile isolation before single-WebView stable, thin MCP delegating to CLI.
- `PRODUCT_SPEC.md` §5 Quality Bar and §6/§7/§8 contracts (refs, native input, evidence) directly operationalize the vision's "refs must be trustworthy" + "evidence over claims" principles. Good — turns prose into acceptance criteria.
- README change is a 4-line pointer block only. Harmless, accurate.

**Scope risks**
- 🟡 **Dual roadmap source-of-truth.** `docs/ROADMAP.md` (P0/P1/P2) and new `docs/DEVELOPMENT_PHASES.md` (Phase 0–6) both track the same forward work under different numbering (ROADMAP P0 native input ↔ Phase 2; P1 capture ↔ Phase 3+4; P2 session ↔ Phase 5). These will drift. `DEVELOPMENT_PHASES.md` *Operating Model* step 5 even says "update … roadmap …", implying both persist. Pick one canonical, demote the other to a pointer.
- 🟢 No capability overreach. Docs add zero new claims to exercise.

**Missing evidence**
- Phase/capability claims (`v0.0.6` capability list in SPEC §4, Phase 0/1 `Done`) are restated, not re-verified in this diff. Acceptable for a docs commit, but nothing in the change re-runs gates. If you want the commit self-evidencing, paste one real gate run (`bash scripts/smoke_cli.sh` exit 0) into the commit body.
- No GUI gate needed — no runtime behavior changed.

**Required doc updates**
- Reconcile `ROADMAP.md` vs `DEVELOPMENT_PHASES.md`: make one canonical, cross-link with `[[ ]]`, delete duplicated phase status from the other.
- Optional: add an explicit Vision-Priority → Phase-number crosswalk line in `DEVELOPMENT_PHASES.md` so the mapping isn't reader-inferred.
- Confirm intent: `CLAUDE.md` and `.claude/agents/product-vision-reviewer.md` did not appear in `git ls-files` and aren't in `git status` — they read as untracked/ignored local files while the 3 docs get committed. Verify that's deliberate (reviewer persona + project instructions arguably belong in-repo).

**Recommended next action**
Before committing: collapse the ROADMAP/DEVELOPMENT_PHASES overlap (one canonical, one pointer), then commit all three docs + README pointer together as a single docs-only commit. No code gates required for this change; one `smoke_cli.sh` exit-0 line in the commit message is sufficient evidence.
