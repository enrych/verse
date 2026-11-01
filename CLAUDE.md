# Verse — instructions for Claude

## Git
- Never add `Co-Authored-By`, `Claude-Session`, "Generated with Claude Code" or any
  other AI attribution to commit messages, PR descriptions, tags or releases.
- Commit as the repository owner; keep messages to a subject line and a short body.

## Project
- macOS menu bar app (SwiftUI, macOS 14+). The Xcode project is generated from
  `project.yml` with XcodeGen; never edit `Verse.xcodeproj`.
- Verse is "song lyrics on your lock screen / any display". Display styles are
  interchangeable options (v0.1 ships Constellation); don't brand the product
  around a single style.
- Website lives in `site/` (static, deployed to Cloudflare Pages `verse`).
