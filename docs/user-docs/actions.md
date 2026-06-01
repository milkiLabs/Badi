# Actions Configuration

Badi reads its actions from `~/.config/badi/config.json` (`$XDG_CONFIG_HOME/badi/config.json` if set).

Actions define prefix-triggered modes. Type a trigger (e.g. `g `) to switch Badi into that mode, type your query, and press Enter to execute.

On first run, a default config file is created automatically.

## Example

```json
{
  "actions": [
    {
      "trigger": "g ",
      "name": "Google",
      "icon": "🔍",
      "action": "xdg-open https://google.com/search?q=%s"
    },
    {
      "trigger": "> ",
      "name": "Run",
      "icon": ">",
      "action": "sh -c %s"
    }
  ]
}
```

These are the defaults that get written on first run (when the file is
missing). Edit the file to add, remove, or change triggers.

## Fields

| Key       | Type   | Description                                                    |
| --------- | ------ | -------------------------------------------------------------- |
| `trigger` | string | Text that activates this mode (e.g. `"g "`)                    |
| `name`    | string | Display name shown in the badge                                |
| `icon`    | string | Emoji or symbol shown next to the name                         |
| `action`  | string | Shell command template. `%s` is replaced with the user's query as one shell-quoted argument |

## How It Works

1. Type the trigger in the search box (e.g. `g `)
2. A badge appears showing the action name
3. The input clears - type your query
4. Press Enter to execute the action with your query
5. Press Escape to exit back to app search

## Adding Your Own

Edit `~/.config/badi/config.json`. Delete actions you don't want, add new ones. The file is only written on first run - subsequent launches read as-is.

```json
{
  "actions": [
    {
      "trigger": "d ",
      "name": "Dictionary",
      "icon": "📖",
      "action": "xdg-open https://en.wiktionary.org/wiki/%s"
    },
    {
      "trigger": "w ",
      "name": "Wikipedia",
      "icon": "🌐",
      "action": "xdg-open https://en.wikipedia.org/wiki/%s"
    },
    { "trigger": "> ", "name": "Run", "icon": ">", "action": "sh -c %s" }
  ]
}
```
