# CLAUDE.md

Lis et applique `AGENTS.md` à la racine : il fait foi pour tous les agents de ce repo (Claude, Codex, autres).

Les skills du projet sont dans `.claude/skills/`. Au démarrage d'une session, charge **toujours** `agent-coordination` en premier, puis `git-workflow`, puis `product-owner` (propriété du Backlog), puis `ios26-design` avant de toucher à l'UI. Avant chaque push, lance le skill `qa` (QA du code, et QA visuelle si l'UI change). Aucune nouvelle feature sans l'approbation d'un humain (voir `AGENTS.md`, règle 7).
