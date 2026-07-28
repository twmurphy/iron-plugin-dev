---
marketplaces:
  - name: iron-plugins
    url: https://github.com/twmurphy/iron-plugins.git
---

# Where this repo publishes

Read by the iron-plugin-dev plugin's deploy-plugin skill. Each entry is a
marketplace that lists a plugin from this repo; releasing moves the ref in every
one of them, alongside this repo's own `.claude-plugin/marketplace.json`.

Committed on purpose — the destination list belongs to the project, not to a
machine. Remote marketplaces are read from a clone the plugin keeps under
`~/.iron-plugin-dev/marketplaces/`, so a URL is the only configuration needed.
