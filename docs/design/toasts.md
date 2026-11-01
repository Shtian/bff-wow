# Toasts

Adds toasts, with a sound, for live Feed entries. Builds on the Feed in #14 (`docs/design/feed.md`) and the settings page in #16 (`docs/design/settings-and-release.md`), and replaces that page's "Feed sounds stay out" for v1. Domain vocabulary from `CONTEXT.md`.

## The idea in one line

A **Toast** is a third way to show a live Feed entry, next to the chat line: a small notice on screen, with a sound, that you can place yourself.

## What makes a toast

- The same entries as the chat line: other Members' new Feed entries after While you were away has settled (ding, death, new Character, max level, joined, left). Your own events don't toast.
- Entries that arrive while settling go into the summary, as before, and don't toast.
- No events outside the Feed. "Member came online" stays the v2 notification it was.
- No per-kind settings in v1.

## Toast vs chat line

Two independent settings, both on by default. Core fires `feedEntry` when **either** is on, and marks the entry seen as it fires. With both off, entries stay unseen for the next login's popup and the Feed tab. App prints the chat line if chat lines are on, and shows the toast if toasts are on.

## How it looks and behaves

- The Skin's flat window look, without a border: the kind's Feed picture (shared with the Feed tab through `Skin.feedPicture`; a Reaction's icon for a Reaction), then the entry's text. A thin line along the bottom shrinks with the time the toast has left; max level, joined, left and goals get it in gold, with gold text.
- Each toast shows for **6 s** and fades out over the last 0.6 s. Hovering stops its clock, and leaving starts it again where it stopped.
- **At most 3** at once. The newest sits where toasts are placed and pushes older ones away. They grow downward when placed in the top half of the screen and upward in the bottom half.
- A burst that doesn't fit (a lockdown flush, the end of combat) fills the free slots and ends in one **"+N more in the Feed"** toast, with the Feed's sidebar icon. Later entries add to it, and give it its full time again, while it shows. With the screen full and no such toast, entries wait for a slot.
- **Left-click** opens the panel on the Feed tab. **Right-click** dismisses.
- **Combat:** nothing new shows in combat. Entries wait and show once it ends. Toasts already on screen fade as usual, and clicking one still opens the Feed, since the panel isn't protected.
- **Turning toasts off** clears those on screen and those waiting.
- **Sound:** plays when toasts show, at most once every 2 s, on the Master channel so it's heard with game sounds muted. Only toasts play it; the chat line and the While you were away popup stay silent.

## Placement

**Move toasts** in Settings closes the Settings panel and shows a sample toast to drag, with **Done** and **Reset** on the side toasts stack towards, so they always have room (Escape closes it too). The position is saved when you drop it: the centre of the first toast, as x and y from the bottom left of the screen. Until it's moved, toasts sit 160 px below the top centre.

## Settings

A **Toasts** section on the settings page, under Notifications and display:

| Setting | Default |
|---|---|
| Show toasts for live events | on |
| Sound: a dropdown of game sounds (the game's own select box), plus a **Play** button | Friend online (`UI_BNET_TOAST`) |
| **Move toasts** button | |

The sound and Move toasts are greyed out while toasts are off. Choosing a sound plays it. There's no duration setting.

The sounds are game sounds named by their `SOUNDKIT` key, plus None: Friend online, Whisper, Invite, Quest complete, Ready check, Raid warning, Map ping and Alarm. Any the client doesn't have are left out of the menu. No LibSharedMedia and no sound files shipped.

All three are account-wide in `BFF_DB`, like the rest of the settings.

## Code

- **Core** owns the settings: `setToasts(on)` / `isToastsOn()`, `setToastSound(key)` / `toastSound()` (`"none"` for silence, nil resets to `Core.DEFAULT_TOAST_SOUND`), and `setToastPosition(x, y)` / `toastPosition()` (nil for the default). Each fires `changed`.
- **ToastQueue** (`UI/ToastQueue.lua`) is pure Lua: the cap, the overflow toast, the combat hold, hover and the sound throttle. `tests/toasts_spec.lua` tests it directly, alongside Core's settings and gating.
- **Toasts** (`UI/Toasts.lua`) draws the queue, plays sounds and owns the move mode.
- `/bffdev toast [n]` (dev checkout only) shows n sample toasts, one of each kind in turn, bypassing Core, to check placement and bursts in game.
