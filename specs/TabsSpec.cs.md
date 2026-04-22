# Commander Tabs CodeSpeak

## Intent

Commander should support multiple top-level tabs in addition to multiple panels per tab. A tab represents a workspace; each workspace can contain one or more file panels and independent active-panel state.

## MUST

- Tabs MUST be modeled in Crystal, not as native AppKit tabs.
- Each tab MUST own its own panel collection, active panel index, and future optional command line state.
- The first implementation increment MAY keep renderer panel count fixed while switching Crystal-owned tab workspaces.
- Tab switching MUST preserve per-tab panel paths, cursors, marked files, and scroll/cursor state.
- Keyboard and mouse events MUST route to the active tab, then to its active/focused panel or widget.
- The renderer/backend MUST receive the active tab snapshot and tab bar draw state.
- The tab bar MUST allow more tabs than fit onscreen through future scrolling or overflow handling.

## MUST NOT

- The model MUST NOT assume one global pair of left/right panels.
- Tab switching MUST NOT rebuild or mutate inactive tab file state except explicit refresh commands.
- Native renderer code MUST NOT decide what a tab contains.
- Panel count MUST NOT be coupled to tab count.

## Initial command set

- `tab.new`: create a new workspace tab.
- `tab.close`: close the active workspace tab, preserving at least one tab.
- `tab.next`: activate next tab.
- `tab.previous`: activate previous tab.
- `tab.rename`: rename active tab.
- `tab.set_panel_count`: change panel count for the active tab.

## Invariants

- There is always at least one tab.
- Active tab index is clamped after tab close.
- Active panel index is scoped to the active tab.
- Existing `Tab` key panel cycling remains panel-focused; tab navigation should use separate shortcuts.

## Checks

- Creating a tab does not mutate the original tab's paths/cursors.
- Switching tabs restores the correct panel count and cursor state.
- Closing a tab never leaves the app without an active workspace.
- More than two panels still cycle by `Tab` inside the active tab.
- Headless command sequence can create two tabs with different panel URIs and switch between them without losing state.
