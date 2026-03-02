# Apothecary Demo Recording Plan

Silent screen recording, ~3-4 minutes total. Record segment by segment, merge later.

## Setup

- Apothecary running at `localhost:4000`, dark theme
- Demo app repo ready with `.apothecary/preview.yml` configured
- `gh` CLI authenticated
- Browser at 1440x900 or similar, no other tabs
- `demo/title-cards.html` open in a separate browser window, fullscreen (`f` key)
- Notifications off (Do Not Disturb)

## Recording Workflow

For each segment:
1. Arrow to the correct title card
2. Start recording (Cmd+Shift+5 or OBS hotkey)
3. Hold on title card for 2-3 seconds
4. Cmd+Tab to Apothecary
5. Perform the actions
6. Stop recording
7. Repeat for next segment

---

## Segment 1 — Intro

**Title card:** "Apothecary" / "A BEAM-orchestrated swarm of Claude Code agents"

- Hold 3 seconds. That's it — just the title.

---

## Segment 2 — Create Concoctions

**Title card:** "Create concoctions"

1. Cmd+Tab to dashboard. Show the empty/calm UI for a beat.
2. Click the "What shall we concoct?" textarea.
3. Type: "Add a dark mode toggle with a sun/moon icon that persists preference to localStorage"
4. Hit send. Card appears in STOCKROOM.
5. Create 2 more quickly:
   - "Add a footer component with links to GitHub and docs"
   - "Refactor the homepage hero section into its own LiveComponent"
6. Three cards now in STOCKROOM. Pause briefly so viewer sees them.

---

## Segment 3 — Start the Swarm

**Title card:** "Start the swarm"

1. Cmd+Tab to dashboard.
2. Click the **Concoct** button (or press `s`). Cauldron animates.
3. Press `+` a couple times to scale to 3 alchemists.
4. Watch cards move from STOCKROOM → CONCOCTING as agents claim them.
5. Activity ticker lights up at top — dots go green.
6. Click a CONCOCTING card (or press `Enter`) to open the detail drawer.
7. Show agent output streaming in real-time.
8. **Key moment:** ingredients appear as the agent self-decomposes the task. Checkboxes populate, progress bar moves.
9. Let this run for a bit. Speed up waiting parts in post (2-4x).
10. Close drawer (`Esc`).

---

## Segment 4 — Inspect the Diff

**Title card:** "Inspect the diff"

1. Cmd+Tab to dashboard.
2. Select a concoction that has meaningful changes (finished or nearly finished).
3. Press `d` — full-screen diff overlay opens.
4. Show the file list on the left (color-coded green/red/yellow).
5. Press `j`/`k` to navigate between files — right pane updates.
6. Pause on a meaningful change so viewers can read it.
7. Press `Esc` to close.

---

## Segment 5 — Preview Changes Live

**Title card:** "Preview changes live"

1. Cmd+Tab to dashboard.
2. Select a completed concoction, open the detail drawer.
3. Click **start preview** (or press `D`).
4. Card shows "PREVIEW ◐ starting..."
5. Flips to "PREVIEW ●" with a port link.
6. Click the port link — demo app opens in a new tab, running from the agent's worktree.
7. **Show the actual change** the agent made (dark mode toggle, footer, etc.). This is the payoff.
8. Switch back to Apothecary dashboard.

---

## Segment 6 — Merge

**Title card:** "Merge"

1. Cmd+Tab to dashboard.
2. A concoction should be in ASSAYING lane (PR open). Select it.
3. Show the PR URL in the detail drawer. Optionally click through to GitHub briefly.
4. Press `m` — merge confirmation bar appears.
5. Confirm merge.
6. Card slides to BOTTLED lane.
7. Show BOTTLED lane with the completed work.

---

## Segment 7 — Recipes

**Title card:** "Recipes" / "Recurring scheduled work"

1. Cmd+Tab to dashboard.
2. Press `e` to switch to Recipes tab.
3. Click **New Recipe**.
4. Fill in: title "Weekly dependency update", schedule `0 3 * * SUN`, priority P2.
5. Create it. Card appears with "active" badge and "next: 5d".
6. Show pause/resume toggle briefly.

---

## Segment 8 — Outro

**Title card:** "Apothecary" / "github.com/nomadkaraoke/apothecary"

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

If a segment has dead time while agents work, cut it or speed it up in iMovie/kdenlive. Show a subtle ⏩ in the corner during sped-up sections if you want.

### Key moments to keep at 1x speed

- Card creation (typing + send)
- Cards sliding between lanes
- Ingredients appearing in real-time
- Diff viewer navigation
- Preview app loading and showing the change
- Merge confirmation

### Export

1080p, 16:9. Works for GitHub README, Twitter/X, YouTube.
