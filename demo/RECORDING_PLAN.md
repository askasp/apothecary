# Apothecary Demo Recording Plan

Silent screen recording, ~4-5 minutes total. Record segment by segment, merge later.

## Setup

- A Phoenix demo app repo ready with `.apothecary/preview.yml` configured
- `gh` CLI authenticated
- Terminal open, ready to run `apothecary`
- Browser at 1440x900 or similar, no other tabs
- `demo/title-cards.html` open in a separate browser window, fullscreen (`f` key)
- Notifications off (Do Not Disturb)

**Important:** The demo app appears three times — Segment 4 (the "before" via main preview), Segment 7 (preview of individual changes), and Segment 8 (the merged "after"). The contrast between before/after is the payoff.

## Recording Workflow

For each segment:
1. Arrow to the correct title card
2. Start recording (Cmd+Shift+5 or OBS hotkey)
3. Hold on title card for 2-3 seconds
4. Cmd+Tab to the target window (terminal or Apothecary)
5. Perform the actions
6. Stop recording
7. Repeat for next segment

---

## Segment 1 — Intro

**Title card:** "Apothecary" / "A BEAM-orchestrated swarm of Claude Code agents"

- Hold 3 seconds. That's it — just the title.

---

## Segment 2 — Start Apothecary

**Title card:** "Start Apothecary"

1. Cmd+Tab to a terminal.
2. Run `apothecary` (or `apothecary start`).
3. Show it booting — Elixir/Phoenix output scrolls briefly.
4. Browser opens (or Cmd+Tab to it) showing the Apothecary dashboard.
5. Pause on the dashboard for a beat — clean slate, no project selected yet.

---

## Segment 3 — Create a Project

**Title card:** "Create a project"

1. Cmd+Tab to dashboard.
2. Click the project selector dropdown in the top-left corner.
3. Click **New Project** (or **Open Project** if pointing at an existing Phoenix repo).
4. For "New Project": give it a name, show the bootstrapper creating the repo.
   For "Open Project": paste or browse to the demo Phoenix app's path.
5. Project loads — dashboard updates to show the project name in the selector.
6. The workbench is now scoped to this project. Pause briefly.

---

## Segment 4 — Preview the App (Before)

**Title card:** "Preview the app" / "The 'before' state"

**Note:** This establishes the baseline the viewer will compare against later.

1. Cmd+Tab to dashboard.
2. The main preview section should be visible in the workbench area.
3. Click **Start Preview** on the main project (this runs the dev server on the main branch).
4. Preview starts — status shows "Starting..." then flips to "Running" with a port link.
5. Click the port link or show the embedded preview iframe.
6. Quick scan of the app — scroll around, show a couple of pages (2-3 seconds).
7. Establish the "before" state. This is what the agents will be changing.

---

## Segment 5 — Create Concoctions

**Title card:** "Create concoctions"

1. Cmd+Tab to dashboard workbench.
2. Click the "What shall we concoct?" textarea.
3. Type: "Add a dark mode toggle with a sun/moon icon that persists preference to localStorage"
4. Hit send. Concoction card appears.
5. Create a second one:
   - "Add a footer component with links to GitHub and docs"
6. Two concoction cards now visible. Pause briefly so viewer sees them.

---

## Segment 6 — Watch the Swarm

**Title card:** "Watch the swarm" / "Parallel agents, live ingredients"

1. Cmd+Tab to dashboard.
2. Click the **Concoct** button (or press `s`). Cauldron animates.
3. Press `+` to scale to 2 alchemists (one per concoction).
4. Watch both cards move from STOCKROOM to CONCOCTING as agents claim them simultaneously.
5. Activity ticker lights up — dots go green.
6. Click a CONCOCTING card (or press `Enter`) to open the detail drawer.
7. Show agent output streaming in real-time.
8. **Key moment:** ingredients appear as the agent self-decomposes the task. Checkboxes populate, progress bar moves.
9. Close drawer (`Esc`). Click the other CONCOCTING card briefly to show both agents working in parallel.
10. Let this run. Speed up waiting parts in post (2-4x).

---

## Segment 7 — Preview Each Change

**Title card:** "Preview each change" / "Side-by-side, in parallel"

**Note:** The demo app returns here — the viewer saw the "before" in Segment 4, now they see what each agent built. The contrast is the payoff.

1. Cmd+Tab to dashboard.
2. Select the first completed concoction, open the detail drawer.
3. Click **Start Preview** (or press `D`).
4. Status shows "Starting..." then flips to "Running" with a port link.
5. Click the port link — demo app opens running from the agent's worktree (different port, e.g. `localhost:4001`).
6. **Show the actual change** the agent made (dark mode toggle). This is the payoff.
7. Switch back to dashboard. Select the second concoction.
8. Start its preview too — now two worktree previews running simultaneously.
9. Click through to see the second change (footer). Two agents, two features, both previewable.
10. Switch back to Apothecary dashboard.

---

## Segment 8 — Merge & See the Result

**Title card:** "Merge & see the result"

1. Cmd+Tab to dashboard.
2. A concoction should be in SAMPLING lane (PR open). Select it.
3. Show the PR URL in the detail drawer. Optionally click through to GitHub briefly.
4. Press `m` — merge confirmation bar appears.
5. Confirm merge. Card slides to BOTTLED lane.
6. Merge the second concoction too.
7. **Key moment:** main preview auto-refreshes (or manually restart it) — now the app has both changes. Dark mode + footer, merged into main.
8. Show the updated app briefly. The "after" state with all changes combined.

---

## Segment 9 — Recurring Concoctions

**Title card:** "Recurring concoctions" / "Scheduled work on autopilot"

1. Cmd+Tab to dashboard.
2. Press `e` to switch to the Recipes tab.
3. Click **New Recipe**.
4. Fill in: title "Weekly dependency update", schedule `0 3 * * SUN`, priority P2.
5. Create it. Card appears with "active" badge and "next: 5d".
6. Show the pause/resume toggle briefly.
7. Mention this runs unattended — agents wake up, do the work, open a PR.

---

## Segment 10 — Ask the Oracle

**Title card:** "Ask the Oracle" / "Codebase Q&A, powered by agents"

1. Cmd+Tab to dashboard workbench.
2. Type a question starting with `?`: "? How does the authentication system work?"
3. Hit send. A question concoction appears with a pulsing amber indicator.
4. Press `o` to switch to the Oracle tab — the question is listed.
5. Wait (or speed up in post) for the agent to analyze the codebase and produce an answer.
6. Answer appears in the Oracle tab. Click to expand and show the detailed response.
7. Pause so the viewer can read the first few lines.

---

## Segment 11 — Outro

**Title card:** "Apothecary" / "github.com/askasp/apothecary"

- Hold 3 seconds. End.

---

## Post-Production

### Concatenate segments

```bash
# create list.txt with one line per file:
# file 'segment1.mov'
# file 'segment2.mov'
# ...
ffmpeg -f concat -i list.txt -c copy demo.mov
```

### Speed up waiting parts

If a segment has dead time while agents work, cut it or speed it up in iMovie/kdenlive. Show a subtle fast-forward indicator in the corner during sped-up sections if you want.

### Key moments to keep at 1x speed

- Project creation / selection
- Main preview starting (the "before")
- Concoction creation (typing + send)
- Cards moving between lanes
- Ingredients appearing in real-time
- Both previews loading — the parallel payoff
- Merge confirmation and seeing the combined result
- Oracle question being asked and answer appearing
- Recipe creation

### Export

1080p, 16:9. Works for GitHub README, Twitter/X, YouTube.
