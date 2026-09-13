# Find a project and prepare a draft in Maw Chat

For first-time users: open either native interface, find a discovered project and
prepare a local draft without sending a message.

## Before you begin

- Build the app using the [README commands](../../README.md#build-and-run).
- Start your compatible [chat backend](../../README.md#dependencies-and-related-repositories).
  Complete any backend login or credential setup yourself; do not include it in captures.
- Choose a project already discovered by your backend. These examples use `maw-rs`;
  use your own project name when following the steps.

## V1 steps

1. **Open Maw Chat** — Open `build/Maw Chat.app`.
   - **Expected result:** the light workspace and the Oracle/project sidebar appear.
2. **Search for a project** — Type its name in **Search Oracles, chats, #tags…**.
   - **Expected result:** the sidebar narrows to matching projects and conversations.
3. **Start a local draft** — Select **+ New thread** below the intended project.
   - **Expected result:** the heading becomes **New chat in <project>** and the composer appears.
4. **Type an example** — Enter `Explain the project structure and suggest a small first task.`
   without pressing Send or ⌘Return.
   - **Expected result:** the text remains in the composer; no assistant response or new server chat is created.

![Full V1 window at the unsent-draft stopping point](../screenshots/v1-full-window.jpg)

## V2 steps

1. **Open Maw Chat V2** — Open `build/Maw Chat V2.app`.
   - **Expected result:** the dark sidebar, conversation pane and inspector appear at a wide window size.
2. **Choose a project** — Select the top-left **+** button, labelled **New conversation · Choose Oracle**.
   - **Expected result:** the **New conversation** chooser opens.
3. **Filter the chooser** — Choose **All projects** for projects without an `-oracle` suffix,
   and type a name in **Search Oracles**.
   - **Expected result:** matching project rows remain. **Oracles** limits the list to Oracle project names.
4. **Select the intended project** — Select its main row.
   - **Expected result:** the chooser closes, the project becomes the draft target, and
     **Start a conversation** appears. Choosing this way also favorites the project.
5. **Narrow the sidebar** — Type the project name in **Search Oracles or sessions**.
   - **Expected result:** the visible sidebar matches the project used in the screenshot.
6. **Type the same example draft** — Do not press Send or ⌘Return.
   - **Expected result:** the unsent text appears at the bottom with the correct project destination.

![Full V2 window at the unsent-draft stopping point](../screenshots/v2-full-window.jpg)

## Verify

The intended project is visible, the example text remains in the composer and no
message has been submitted. Clear the example when finished. Sending is deliberately
outside this walkthrough: it changes the shared backend and can start a paid model turn.

## Troubleshooting

- **Project missing from V2's chooser** — Select **All projects**, then search again.
- **Repository discovery is limited** — The server may cap inventory discovery; this
  warning was visible during capture. Check backend discovery configuration for missing projects.
- **Could not connect to the server** — Check that your configured chat backend is running.
  The apps do not start it for you; a disconnected server was observed before capture.
- **No live source selected** — This is the intentional V2 capture state, not a failed
  chat connection. Terminal output was excluded from the public images.

## Notes

- Interface observed on 13 September 2026; labels and layout may change.
- Native app interaction/capture was used, not browser automation.
- These are full app windows at their native capture sizes, not full-desktop captures.
- No cropping, compositing, generated replacement UI or pixel redaction was applied.
- Example drafts were cleared afterward; temporary search/filter/favorite changes were restored.
- No credentials, account IDs, session UUIDs, private transcript bodies or terminal output
  appear in the published captures. The visible project/thread labels are retained.
