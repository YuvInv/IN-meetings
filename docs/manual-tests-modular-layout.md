# Manual tests — modular / resizable meeting layout

Run `make run-mac`, then:

1. **Video meeting** — open one. Video is in the left column; transcript fills the right at full height;
   no audio footer (the video player has its own inline transport controls).
2. **Resize** — drag the column divider (⇆, between media and transcript) and the video/summary divider
   (⇅, inside the left column). Both panes resize; the cursor changes to a resize arrow over each handle.
3. **Audio-only meeting** — open one. Layout is **Summary | Transcript**; the audio playback bar is a
   full-width footer at the bottom.
4. **Collapse summary** — click "Summary" in the header. Audio meeting → **full-width transcript** (no dead
   left column); video meeting → **video | transcript**. Click again to restore. The button is tinted when
   the summary is shown, and only appears when the meeting actually has a summary.
5. **Persistence** — quit (⌘Q) and relaunch, reopen a meeting: the divider sizes **and** the summary
   visibility are remembered (global, the same for every meeting).
6. **RTL** — the Hebrew transcript still reads right-to-left inside its pane (chrome stays left-to-right).
7. **Known nit to eyeball (deferred fix):** toggling the summary on an **audio-only** meeting may reset the
   transcript scroll position (the layout swaps between a split and a full-width transcript). Confirm whether
   this is actually noticeable on a long transcript — if it's annoying we'll anchor the scroll identity;
   if not, leave it.
