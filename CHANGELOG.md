# Changelog

## 0.4.5 - 2026-08-25

- Install a second legacy icon pair beside the calling MacroScript.
- Preserve a successful auto unwrap when xatlas encounters zero-area triangles.
- Collapse only UV vertices belonging exclusively to degenerate geometry.

## 0.4.4 - 2026-08-25

- Store legacy alpha masks as RGB bitmaps like the icons shipped with Max 2016.
- Fix helper executable discovery across Max 2016 language profiles.
- Avoid an `undefined`-to-string rollout exception when the helper is missing.

## 0.4.3 - 2026-08-25

- Archive the legacy `DIN Tools-DIN_UV_xatlasPack.mcr` duplicate during install.
- Prevent an older duplicate MacroScript definition from replacing the custom icon.

## 0.4.2 - 2026-08-25

- Add a dedicated legacy 3ds Max toolbar icon with 16x15 and 24x24 alpha pairs.
- Add an administrator-free per-user installer with language-profile detection.
- Back up existing files and verify every installed file with SHA-256.
- Resolve the helper executable across Max 2016 language profiles.
- Add a reproducible release ZIP builder.

## 0.4.1

- Preserve separate stacked UV islands as independent, non-overlapping charts.
- Add xatlas automatic unwrap and pack mode with exact triangle topology support.
