# Theme Configuration

Badi reads its theme from `~/.config/badi/theme.json` (`$XDG_CONFIG_HOME/badi/theme.json` if set).

On first run, a default theme file is created automatically. Unknown fields are ignored, so you only need to specify what you want to override.

## Example

```json
{
  "background_color": "#1e1e2e",
  "text_color": "#cdd6f4",
  "accent_color": "#89b4fa",
  "input_background": "#313244",
  "border_color": "#45475a",
  "hover_color": "#45475a",
  "placeholder_color": "#6c7086",
  "selected_text_color": "#1e1e2e",
  "font_family": "sans-serif",
  "font_size": 15,
  "font_weight": "normal",
  "window_width": 600,
  "window_height": 450,
  "window_padding": 14,
  "item_spacing": 6,
  "border_radius": 6,
  "border_width": 1,
  "input_padding": 10,
  "item_padding": 10
}
```

## Options

### Colors

| Key                   | Type   | Default   | Description                 |
| --------------------- | ------ | --------- | --------------------------- |
| `background_color`    | string | `#1e1e2e` | Window background           |
| `text_color`          | string | `#cdd6f4` | Default text color          |
| `accent_color`        | string | `#89b4fa` | Selected item background    |
| `input_background`    | string | `#313244` | Search bar background       |
| `border_color`        | string | `#45475a` | Search bar border           |
| `hover_color`         | string | `#45475a` | List item hover background  |
| `placeholder_color`   | string | `#6c7086` | Search placeholder text     |
| `selected_text_color` | string | `#1e1e2e` | Text color on selected item |

### Typography

| Key           | Type    | Default      | Description                                       |
| ------------- | ------- | ------------ | ------------------------------------------------- |
| `font_family` | string  | `sans-serif` | Font family name                                  |
| `font_size`   | integer | `15`         | Font size in px                                   |
| `font_weight` | string  | `normal`     | CSS font-weight (`normal`, `bold`, `light`, etc.) |

### Dimensions

| Key              | Type    | Default | Description                                |
| ---------------- | ------- | ------- | ------------------------------------------ |
| `window_width`   | integer | `600`   | Window width in px                         |
| `window_height`  | integer | `450`   | Window height in px                        |
| `window_padding` | integer | `14`    | Space around window edges in px            |
| `item_spacing`   | integer | `6`     | Vertical gap between list items in px      |
| `border_radius`  | integer | `6`     | Corner roundness for input and items in px |
| `border_width`   | integer | `1`     | Search bar border thickness in px          |
| `input_padding`  | integer | `10`    | Space inside search bar in px              |
| `item_padding`   | integer | `10`    | Space inside each list item in px          |

## Minimal Override

Only specify what you want to change:

```json
{
  "accent_color": "#f38ba8",
  "font_size": 18,
  "window_width": 800
}
```

All other values use their defaults.
