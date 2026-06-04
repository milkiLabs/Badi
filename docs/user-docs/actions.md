# Actions Configuration

Badi reads its actions from `~/.config/badi/config.json`
(`$XDG_CONFIG_HOME/badi/config.json` if set).

Actions define prefix-triggered modes. Type a trigger (e.g. `g `)
to switch Badi into that mode, type your query, and press Enter to
execute.

On first run, a default config file is created automatically.

## Kinds

An action can be one of four `kind` values, which determine how the
query is executed. `kind` defaults to `"shell"` (the original
behavior) if omitted, so existing config files keep working.

| Kind     | When to use                                                       | Required fields                     |
| -------- | ----------------------------------------------------------------- | ----------------------------------- |
| `shell`  | Default. Run a shell command template. `%s` is replaced with the shell-quoted query. | `action` (string)                   |
| `argv`   | Run a program directly with arg list. No shell. `%s` substituted in each arg. | `program` (string), `args` (array)  |
| `http`   | Fetch a URL via `curl`. `%s` is replaced with a URL-encoded query in the URL. Response body goes to stdout. | `url` (string), `method` (optional, default `"GET"`) |
| `script` | Run a script with the query as `$1`. No shell.                    | `script` (string, absolute path)    |

## Examples

### `shell` (default) — Google search and shell-out

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

### `argv` — invoke a known program directly (no shell)

```json
{
  "trigger": "git ",
  "name": "git",
  "icon": "🌱",
  "kind": "argv",
  "program": "git",
  "args": ["%s"]
}
```

`git ` + `status` runs `git status` directly, with no shell
involved. Empty args after `%s` substitution are passed as `""` so
positional meaning is preserved (a "missing" arg is still an
arg).

### `http` — quick API calls

```json
{
  "trigger": "ip ",
  "name": "IP lookup",
  "icon": "🌐",
  "kind": "http",
  "url": "https://ipinfo.io/%s/json",
  "method": "GET"
}
```

`ip ` + `8.8.8.8` fetches the JSON; the response body appears on
stdout, Badi exits 0. Requires `curl` on `$PATH`.

### `script` — call a local script

```json
{
  "trigger": "fb ",
  "name": "Find file",
  "icon": "🔎",
  "kind": "script",
  "script": "/home/me/bin/find-file"
}
```

`fb ` + `README` runs `find-file README` directly, with no shell.
POSIX `$1` convention.

## Fields

| Key       | Type   | Description                                                    |
| --------- | ------ | -------------------------------------------------------------- |
| `trigger` | string | Text that activates this mode (e.g. `"g "`)                    |
| `name`    | string | Display name shown in the badge                                |
| `icon`    | string | Emoji or symbol shown next to the name                         |
| `kind`    | string | One of `shell` (default), `argv`, `http`, `script`             |
| `action`  | string | (`.shell`) Shell command template; `%s` is replaced with the shell-quoted query |
| `program` | string | (`.argv`) Program path to run directly (no shell)              |
| `args`    | array  | (`.argv`) Arg list; `%s` substituted in each                   |
| `url`     | string | (`.http`) URL template; `%s` replaced with the URL-encoded query |
| `method`  | string | (`.http`) HTTP method; defaults to `"GET"`                     |
| `script`  | string | (`.script`) Absolute path to a script; the query is `$1`       |

## How It Works

1. Type the trigger in the search box (e.g. `g `)
2. A badge appears showing the action name
3. The input clears - type your query
4. Press Enter to execute the action with your query
5. Press Escape to exit back to app search

## Adding Your Own

Edit `~/.config/badi/config.json`. Delete actions you don't want,
add new ones. The file is only written on first run — subsequent
launches read as-is.

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
