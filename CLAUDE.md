# CLAUDE.md

Lis et applique `AGENTS.md` à la racine : il fait foi pour tous les agents de ce repo (Claude, Codex, autres).

Les skills du projet sont dans `.claude/skills/`. Au démarrage d'une session, charge **toujours** `agent-coordination` en premier, puis `git-workflow`, puis `product-owner` (propriété du Backlog), puis `ios26-design` avant de toucher à l'UI.
