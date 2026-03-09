# Apothecary Demo Recording Plan

Silent screen recording, ~5-6 minutes total. Record segment by segment, merge later.

## Setup

- A Phoenix demo app repo ready with `.apothecary/preview.yml` configured
- `gh` CLI authenticated
- Terminal open, ready to run `apothecary`
- Browser at 1440x900 or similar, no other tabs
- `demo/title-cards.html` open in a separate browser window, fullscreen (`f` key)
- Notifications off (Do Not Disturb)

**Narrative arc:** Start by previewing main to establish a baseline. Then create a single worktree with some fixes, preview the branch, and merge it back — showing the full lifecycle. Then scale up by creating multiple worktrees in parallel.

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

**Title card:** "Apothecary" / "Neovim for agents"

- Hold 3 seconds. That's it — just the title.

---

## Segment 2 — Boot & Open a Project

**Title card:** "Boot & open a project"

**What to show:** Apothecary boots fast, keyboard-driven project selection.

1. Cmd+Tab to a terminal.
2. Run `apothecary` (or `apothecary start`).
3. Show it booting — Elixir/Phoenix output scrolls briefly.
4. Browser opens (or Cmd+Tab to it) showing the Apothecary dashboard.
5. Select the demo Phoenix app from the project selector (type the path or pick from list).
6. Dashboard loads with the project name. Pause briefly — clean workspace, ready to go.

---

## Segment 3 — Preview Main

**Title card:** "Preview main" / "The starting point"

**What to show:** Inline preview of main branch, establishing the "before" state.

1. Cmd+Tab to dashboard.
2. Click **main** in the tree panel to select it.
3. Click the preview link — the inline preview opens in the right panel.
4. Quick scan of the app — scroll around, show a couple of pages (2-3 seconds).
5. Establish the "before" state. This is what the agents will be changing.

---

## Segment 4 — Create a Worktree

**Title card:** "Create a worktree" / "Describe the work, dispatch an agent"

**What to show:** Natural language input creates a worktree, agent starts working.

1. Cmd+Tab to dashboard.
2. Press `b` to enter branch-creation mode.
3. Type: "Fix the landing page hero section — update the headline text, improve spacing, and add a call-to-action button"
4. Hit Enter. Worktree appears in the queued group.
5. Press `s` to start the swarm. Agent picks it up, worktree moves to brewing.

---

## Segment 5 — Watch It Work

**Title card:** "Watch it work" / "Tasks, progress, live output"

**What to show:** Agent output streaming, self-decomposition into tasks, progress bar filling.

1. Cmd+Tab to dashboard.
2. Click the brewing worktree to see the detail panel.
3. Show agent output streaming in real-time.
4. **Key moment:** Tasks appear as the agent self-decomposes the work. Checkboxes populate, progress bar moves.
5. Let it run to completion. Speed up waiting parts in post (2-4x).

---

## Segment 6 — Preview the Branch

**Title card:** "Preview the branch" / "Inline, side by side with main"

**What to show:** Inline dev server preview of the agent's branch, comparing to main.

1. Cmd+Tab to dashboard.
2. The worktree should now be done or have a PR open.
3. Click the worktree to select it in the detail pane.
4. Click the preview link — inline preview opens showing the changes.
5. **Show the actual change.** Compare to what main looked like. This is the first payoff.

---

## Segment 7 — Merge into Main

**Title card:** "Merge into main"

**What to show:** One-key merge, result visible on main's preview immediately.

1. Cmd+Tab to dashboard.
2. Select the completed worktree. Show the PR in the detail panel.
3. Merge it (press `m`). Worktree moves to bottled.
4. Click **main** in the tree panel. The preview updates.
5. Show the updated app briefly. The "after" moment.

---

## Segment 8 — Scale It Up

**Title card:** "Scale it up" / "Three agents in parallel"

**What to show:** Rapid worktree creation, scaling agents, parallel execution.

1. Cmd+Tab to dashboard.
2. Create several worktrees in quick succession (press `b` each time):
   - "Add a dark mode toggle with a sun/moon icon that persists preference to localStorage"
   - "Add a footer component with links to GitHub and docs"
   - "Add a testimonials carousel with auto-rotation"
3. Scale to 3 agents (press `+` twice).
4. Watch all three worktrees move to brewing simultaneously.
5. Briefly peek at each detail panel — three agents working at the same time.
6. Let them run. Speed up waiting parts in post (2-4x).

---

## Segment 9 — Preview Each Branch

**Title card:** "Preview each branch"

**What to show:** Click through each worktree, each has its own live preview.

1. Cmd+Tab to dashboard.
2. Three worktrees should now be done or have PRs open.
3. Click the first worktree. Preview shows the dark mode toggle.
4. Click the second worktree. Preview shows the footer.
5. Click the third worktree. Preview shows the testimonials carousel.
6. Three agents, three features, all previewable inline.

---

## Segment 10 — Merge All

**Title card:** "Merge all" / "Everything combined on main"

**What to show:** Merge all branches, preview main with all features combined.

1. Cmd+Tab to dashboard.
2. Merge all three worktrees one by one (select each, press `m`). They move to bottled.
3. **Key moment:** Click **main** in the tree panel. Preview updates.
4. The app now has everything — dark mode, footer, testimonials, plus the earlier fixes.
5. Show the fully updated app. This is the big payoff.

---

## Segment 11 — Recurring Worktrees

**Title card:** "Recurring worktrees" / "Cron-scheduled, fully unattended"

**What to show:** Recipe creation for scheduled agent work.

1. Cmd+Tab to dashboard.
2. Press `e` to switch to the Recipes tab.
3. Click **New Recipe**.
4. Fill in: title "Weekly dependency update", schedule `0 3 * * SUN`, priority P2.
5. Create it. Card appears with "active" badge and "next: 5d".
6. Show the pause/resume toggle briefly.

---

## Segment 12 — Outro

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

- Boot and project selection (fast, keyboard-driven)
- Main preview opening inline (the baseline)
- Worktree creation with natural language
- Agent self-decomposition into tasks
- First branch preview — comparing to main
- First merge and seeing the result on main
- Creating multiple worktrees in rapid succession
- All worktrees moving to brewing simultaneously
- Each branch preview loading
- Merging all and seeing the combined result on main
- Recipe creation

### Export

1080p, 16:9. Works for GitHub README, Twitter/X, YouTube.
