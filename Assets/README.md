# Maw Chat application icon

`MawChatIcon.png` is original generated artwork made for this app on 2026-09-13:
two overlapping chat bubbles on a violet tile, with transparent outer corners.
The source is kept at its generated resolution and alpha is preserved.

`scripts/build-icon.sh` packages 16–1024 pixel representations into a native ICNS.
`scripts/build-app.sh` includes it as `Contents/Resources/MawChatIcon.icns` and sets
`CFBundleIconFile`. No external image URL or generated-image cache path is required.
