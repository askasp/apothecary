# Apothecary Demo Recording Plan

Silent screen recording, ~4-5 minutes total. Record segment by segment, merge later.

## Setup

- A Phoenix demo app repo ready with `.apothecary/preview.yml` configured
- `gh` CLI authenticated
- Terminal open, ready to run `apothecary`
- Browser at 1440x900 or similar, no other tabs
- `demo/title-cards.html` open in a separate browser window, fullscreen (`f` key)
- Notifications off (Do Not Disturb)

**Important:** The inline preview is the star of the show. The "before" (Segment 4) vs individual worktree previews (Segment 7) vs merged "after" (Segment 8) is the narrative arc.

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

## Segment 3 — Choose a Project

**Title card:** "Choose a project"

1. Cmd+Tab to dashboard.
2. Click the project selector dropdown in the top-left corner.
3. Select the demo Phoenix app from the list (or use **Open Project** to point at it).
4. Project loads — dashboard updates to show the project name, tree panel populates.
5. Pause briefly to show the project is now active.

---

## Segment 4 — Preview the App (Before)

**Title card:** "Preview the app" / "The 'before' state"

**Note:** This establishes the baseline the viewer will compare against later.

1. Cmd+Tab to dashboard.
2. Click **main** in the tree panel to select it.
3. In the detail pane, click the preview link — the inline preview opens, filling the detail pane with an iframe of the running app.
4. Quick scan of the app — scroll around, show a couple of pages (2-3 seconds).
5. Establish the "before" state. This is what the agents will be changing.
6. Press Escape to close the inline preview and return to the detail view.

---

## Segment 5 — Create Three Concoctions

**Title card:** "Create three concoctions"

1. Cmd+Tab to dashboard workbench.
2. Click the "What shall we concoct?" textarea.
3. Type: "Add a dark mode toggle with a sun/moon icon that persists preference to localStorage"
4. Hit send. Concoction card appears.
5. Create a second: "Add a footer component with links to GitHub and docs"
6. Create a third: "Add a hero section with animated gradient background"
7. Three concoction cards now visible. Pause briefly so viewer sees them.

---

## Segment 6 — Watch the Swarm

**Title card:** "Watch the swarm" / "Three agents in parallel"

1. Cmd+Tab to dashboard.
2. Click the **Concoct** button (or press `s`). Cauldron animates.
3. Scale to 3 alchemists so all three concoctions run in parallel.
4. Watch all three cards move from STOCKROOM to CONCOCTING as agents claim them simultaneously.
5. Activity ticker lights up — dots go green.
6. Click a CONCOCTING card to open the detail drawer.
7. Show agent output streaming in real-time.
8. **Key moment:** ingredients appear as the agent self-decomposes the task. Checkboxes populate, progress bar moves.
9. Close drawer. Briefly peek at the other two to show all three agents working in parallel.
10. Let this run. Speed up waiting parts in post (2-4x).

---

## Segment 7 — Preview Each Worktree

**Title card:** "Preview each worktree" / "Inline, side by side"

**Note:** The viewer saw the "before" in Segment 4. Now they see what each of the three agents built — all via inline preview.

1. Cmd+Tab to dashboard.
2. Three worktrees should now be visible in the tree panel.
3. Click the first worktree to select it in the detail pane.
4. Click the preview link — inline preview opens showing the dark mode toggle change.
5. **Show the actual change.** Toggle dark mode on/off. This is the payoff.
6. Press Escape to close preview. Click the second worktree.
7. Open its preview — see the footer component the agent built.
8. Press Escape. Click the third worktree.
9. Open its preview — see the hero section with animated gradient.
10. Three agents, three features, all previewable inline. Return to dashboard.

---

## Segment 8 — Merge All & See the Result

**Title card:** "Merge all & see the result"

1. Cmd+Tab to dashboard.
2. Select the first completed concoction. Show the PR in the detail drawer.
3. Merge it. Card slides to BOTTLED.
4. Merge the second concoction.
5. Merge the third concoction.
6. **Key moment:** Click **main** in the tree panel. Open the inline preview.
7. The app now has all three changes — dark mode toggle, footer, and hero section.
8. Show the updated app briefly. The "after" state with everything combined.

---

## Segment 9 — Ask the Oracle

**Title card:** "Ask the Oracle" / "Codebase Q&A, powered by agents"

1. Cmd+Tab to dashboard workbench.
2. Type a question starting with `?`: "? How does the authentication system work?"
3. Hit send. A question concoction appears with a pulsing amber indicator.
4. Press `o` to switch to the Oracle tab — the question is listed.
5. Wait (or speed up in post) for the agent to analyze the codebase and produce an answer.
6. Answer appears in the Oracle tab. Click to expand and show the detailed response.
7. Pause so the viewer can read the first few lines.

---

## Segment 10 — Recurring Concoctions

**Title card:** "Recurring concoctions" / "Scheduled work on autopilot"

1. Cmd+Tab to dashboard.
2. Press `e` to switch to the Recipes tab.
3. Click **New Recipe**.
4. Fill in: title "Weekly dependency update", schedule `0 3 * * SUN`, priority P2.
5. Create it. Card appears with "active" badge and "next: 5d".
6. Show the pause/resume toggle briefly.
7. Mention this runs unattended — agents wake up, do the work, open a PR.

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

- Project selection
- Main preview opening inline (the "before")
- Concoction creation (typing + send)
- Cards moving between lanes
- Ingredients appearing in real-time
- All three inline previews loading — the parallel payoff
- Merging all three and seeing the combined result on main
- Oracle question being asked and answer appearing
- Recipe creation

### Export

1080p, 16:9. Works for GitHub README, Twitter/X, YouTube.
