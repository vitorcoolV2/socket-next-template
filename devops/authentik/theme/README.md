# Authentik Theme System

Custom theming for Home2500's Authentik identity provider.

## Directory Structure

```
theme/
├── _builder.sh         # Build script (orchestrator)
├── assets.map          # Path mapping registry
├── branding-*.json     # Theme configurations
├── assets/             # Static resources
│   ├── *.jpg           # Background images
│   ├── *.css           # Custom styles
│   └── *.svg           # Logo & icons
└── js/                 # Client-side scripts
    └── theme-toggle.js # Runtime theme switcher
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HOW THEY WORK TOGETHER                       │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────┐      ┌─────────────────┐      ┌──────────────────┐
│  branding-*.json │ ──── │   _builder.sh   │ ──── │  Authentik API   │
│  (Theme Config)  │      │  (Orchestrator) │      │  (brands/pk/)    │
└──────────────────┘      └────────┬────────┘      └──────────────────┘
                                   │
                          ┌────────┴─────────┐
                          │                  │
                          ▼                  ▼
              ┌──────────────────┐  ┌─────────────────┐
              │    assets.map    │  │   Docker Copy   │
              │  (Path Mapping)  │  │   (Container)   │
              └────────┬─────────┘  └─────────────────┘
                       │
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │ ./assets │ │ ./assets │ │   ./js   │
    │ (images) │ │   (css)  │ │  (toggle)│
    └──────────┘ └──────────┘ └──────────┘
```

## File Roles

### `branding-*.json` — Theme Configuration

Defines appearance per theme variant (dark, light, emotion).

```json
{
  "branding_title": "Home2500 | Identity",
  "branding_logo": "/static/dist/assets/icons/authentik-home2500.svg",
  "branding_favicon": "/static/dist/assets/icons/icon.png",
  "attributes": {
    "settings": {
      "theme": { "base": "dark" },
      "layout": "sidebar_left",
      "background": "/static/dist/assets/images/home2500-dark.jpg"
    }
  }
}
```

| Property           | Description                 |
| ------------------ | --------------------------- |
| `branding_title`   | Browser tab title           |
| `branding_logo`    | Header logo path            |
| `branding_favicon` | Favicon path                |
| `theme.base`       | `dark` or `light`           |
| `layout`           | `sidebar_left` or `stacked` |
| `background`       | Login page background image |

### `assets.map` — Path Mapping Registry

Maps local source files to Docker container destinations.

```bash
# Format: assets["local_relative_path"]="container_absolute_path"
assets["assets/home2500.jpg"]="/web/dist/assets/images/home2500.jpg"
assets["assets/home2500-dark.jpg"]="/web/dist/assets/images/home2500-dark.jpg"
assets["assets/home2500.css"]="/web/dist/custom.css"
assets["js/theme-toggle.js"]="/web/dist/theme-toggle.js"
```

| Local Path            | Container Path                         | Public URL                                |
| --------------------- | -------------------------------------- | ----------------------------------------- |
| `assets/home2500.jpg` | `/web/dist/assets/images/home2500.jpg` | `/static/dist/assets/images/home2500.jpg` |
| `assets/home2500.css` | `/web/dist/custom.css`                 | — (loaded by Authentik)                   |
| `js/theme-toggle.js`  | `/web/dist/theme-toggle.js`            | — (loaded by Authentik)                   |

### `./assets/` — Static Resources

| File                     | Type  | Purpose                       |
| ------------------------ | ----- | ----------------------------- |
| `home2500.jpg`           | Image | Light theme background        |
| `home2500-dark.jpg`      | Image | Dark/Emotion theme background |
| `authentik-home2500.svg` | Logo  | Header logo (all themes)      |
| `home2500-icon.svg`      | Icon  | Favicon source                |
| `home2500.css`           | CSS   | Custom styling overlay        |

### `./js/theme-toggle.js` — Client-Side Theme Switcher

Injects a ☀️/🌙 toggle button into the Authentik admin UI.

**Behavior:**

1. Polls DOM every 2s for Authentik web components
2. Injects button into admin header
3. On click: toggles `data-theme` attribute globally
4. Recursively updates all Shadow DOM components
5. Forces CSS reload via cache-busting query param

### `_builder.sh` — Orchestrator

Wires everything together:

```
┌─────────────────────────────────────────────────────────────────┐
│                     _build_brand_theme <theme>                   │
└─────────────────────────────────────────────────────────────────┘

Step 1: Load assets.map → declare associative array
        │
        ▼
Step 2: For each asset:
        ├─ docker cp local → container:/web/dist/...
        └─ curl check public URL is accessible (200 OK)
        │
        ▼
Step 3: Read branding-{theme}.json
        │
        ▼
Step 4: Validate background exists in assets.map
        │
        ▼
Step 5: PATCH /api/v3/core/brands/{pk}/
        │
        ▼
Step 6: PATCH /api/v3/flows/instances/default-authentication-flow/
```

## Available Themes

| Theme     | Base  | Layout       | Background        |
| --------- | ----- | ------------ | ----------------- |
| `dark`    | dark  | sidebar_left | home2500-dark.jpg |
| `light`   | light | stacked      | home2500.jpg      |
| `emotion` | dark  | stacked      | home2500-dark.jpg |

## Prerequisites

- Docker container `authentik-server` running
- Vault token authenticated (`vault_request_stew_token`)
- Authentik API token (auto-generated if missing)

## Usage

### Apply a specific theme

```bash
source devops/authentik/theme/_builder.sh
_build_brand_theme dark
```

### Interactive selection

```bash
source devops/authentik/theme/_builder.sh
choose_and_apply
```

### Using parent library shortcuts

```bash
source devops/authentik/_0-authentik_lib.sh
ak_theme_dark
# or
ak_theme_light
```

## Adding a New Theme

1. Create `branding-{name}.json` in this directory:

```json
{
  "branding_title": "Home2500 | Identity",
  "branding_logo": "/static/dist/assets/icons/authentik-home2500.svg",
  "branding_favicon": "/static/dist/assets/icons/icon.png",
  "attributes": {
    "settings": {
      "theme": { "base": "dark" },
      "layout": "stacked",
      "background": "/static/dist/assets/images/home2500-dark.jpg"
    }
  }
}
```

1. Apply the theme:

```bash
source _builder.sh
_build_brand_theme {name}
```

## Troubleshooting

**Assets not found (404):**

```bash
# Verify public URLs are accessible
_authentik_asset_exist_published
```

**API token invalid:**

```bash
ak_api_token_restore
# or
ak_api_token_generate
```

**Container not running:**

```bash
docker ps | grep authentik-server
```
