# Stdin Detection

Badi checks `stat().kind == .named_pipe` to distinguish real pipes from
`/dev/null`. This matters because Sway's `exec` connects stdin to `/dev/null`
(a character device), which should launch in apps mode, not piped mode.

| Launch method      | `stat().kind`       | Mode  |
| ------------------ | ------------------- | ----- |
| Terminal           | `.character_device` | Apps  |
| `echo foo \| badi` | `.named_pipe`       | Piped |
| Sway keybinding    | `.character_device` | Apps  |
| File redirect      | `.file`             | Apps  |

`isTty()` alone can't distinguish pipes from `/dev/null` — both return false.
The `stat().kind` check adds the needed granularity.

The check is fail-safe: if `stat` fails, `is_piped` defaults to `false` (apps
mode). Worst case of a wrong detection is showing "No input" in piped mode —
not a crash.
