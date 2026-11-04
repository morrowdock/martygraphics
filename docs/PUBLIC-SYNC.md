# Public sync ownership and review

The existing publication maintainer owns triage and import into this repository.
The core maintainer supplies narrow eligible engine changes and their evidence.
There is no automatic mirror of an app repository or private monorepo.

## One candidate at a time

1. The core owner hands off an exact source commit, file list, intended public
   behavior, original authorship/license evidence, focused tests and known limits.
2. The publication owner decides whether the change belongs to generic MG core.
   Exclude private courses, app adapters, prompts/provider/routing policy,
   evaluation recipes, learner data, private assets, endpoints, keys and trust config.
3. Forward-port only reviewed files/diffs onto a scoped branch. Never import
   monorepo history. Record source hashes and every adaptation in `EXPORT.json`
   or the scoped PR provenance; preserve required license/attribution.
4. Run focused and integration checks at the exact candidate, refresh FILES.json,
   scan the added content/assets and complete reachable history, and verify all
   showcase claims against that public candidate.
5. Use one independent review for that candidate. A previous release's approval
   does not clear new code, assets or capability claims. Re-check fixes through
   the normal review process; avoid concurrent duplicate review assignments.
6. Merge through a normal PR after evidence is clean. Approved public main is
   not replaced by a new extraction. Publish no additional private repository
   as a side effect of a documentation or showcase update.

## Assets and examples

Coordinate with the existing website/UI owner before making duplicate captures.
Every accepted native capture needs an exact source revision, original synthetic
input, command, renderer/platform, dimensions/timing, hash and privacy/license
review. Distinguish native frame export, app screenshot, browser recreation and
concept art. A website asset is not automatically eligible for this repository.

Source and example licenses must permit public redistribution. No private
course/proprietary prompt can become public just by changing its title or numbers.

## Evidence-led roadmap

Prioritize reproducible gaps: starter usability, domain breadth supported by the
public primitives, text/layout quality, accessibility, frame cost and integration.
Use bounded proposals and measurements, not novelty, superiority or competitor
implementation guesses. A competitor's platforms or overlay demo does not
establish its internal engine architecture.

Announcements and outreach require owner review of the actual launch kit.
Check platform/community rules at posting time; this process authorizes no posts.
