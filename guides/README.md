# Funes Guides

## Quick start

```
bundle exec rake guides:setup   # one-time: install Jekyll deps
bundle exec rake guides:serve   # start dev server with live reload
```

Open http://localhost:4000/ — edits to `.md` files auto-refresh.

## Adding a new guide

1. Create a new `.md` file in `guides/`
2. Add frontmatter (`title`, `nav_order`)
3. Write content in Markdown
