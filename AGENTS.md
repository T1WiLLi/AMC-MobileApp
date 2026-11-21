# AGENTS.md — AMC-MobileApp

> Fichier racine lu par **Codex** (et tout autre agent). Claude Code lit `CLAUDE.md`, qui pointe ici.

## Règle n°1 : les skills sont dans `.claude/skills/`

Avant **toute** action dans ce repo, lis et applique les skills du dossier `.claude/skills/`.
Chaque skill est un dossier contenant un `SKILL.md` (frontmatter `name` / `description` + instructions).
Ces fichiers sont la source de vérité pour tous les agents (Codex, Claude, autres) — tu dois les suivre comme si c'étaient tes propres instructions.

Ordre de lecture obligatoire au démarrage :

1. `.claude/skills/agent-coordination/SKILL.md` — **toujours en premier**. Communication entre agents via le doc partagé, claims, journal, questions, boucle sans fin.
2. `.claude/skills/git-workflow/SKILL.md` — repo GitHub, branches, pull régulier, commits, PR.
3. `.claude/skills/ios26-design/SKILL.md` — avant de toucher à une vue : design iOS 26 (Liquid Glass), données fake, qualité visuelle.
4. `.claude/skills/product-owner/SKILL.md` — qui possède le Backlog, comment demander un ajout/changement, comment choisir un item.

Quand une tâche correspond à la `description` d'un autre skill de `.claude/skills/`, lis-le aussi avant de commencer.
Relis la liste des skills de temps en temps : un autre agent a pu en ajouter un (annoncé dans le journal).

## Projet en bref

- App iOS **SwiftUI**, cible **iOS 26.0**, **Swift 6**, Xcode project `AMC-MobileApp.xcodeproj`.
- Architecture MVVM : `AMC-MobileApp/{App,Models,ViewModels,Views,Services}`.
- Tout tourne sur des **données fake** (services mock) — pas de backend réel.
- GitHub : https://github.com/T1WiLLi/AMC-MobileApp
- Doc de coordination des agents : https://claude.ai/artifact/9Ur9bKmmbmnjgZqgbskohg

## Les 6 règles non négociables

1. **Annonce avant d'agir** dans le doc de coordination, et vérifie qu'aucun autre agent ne fait déjà la même chose.
2. **Documente tout** ce que tu fais dans le journal du doc, pour que les autres agents soient au courant.
3. **Pull régulièrement**, comme un humain (au début de chaque tâche, avant chaque commit, et au minimum toutes les ~15 min).
4. **Ne t'arrête jamais** : une fois lancé, tu enchaînes les tâches en boucle (voir `agent-coordination`).
5. **Questions pour quelqu'un d'autre** → pose-la à l'agent de cette personne dans le doc ; c'est lui qui la fait remonter à son humain.
6. **Le Backlog appartient au Product Owner** : seul l'agent PO le modifie. Tu prends un item `prêt` ; pour tout ajout ou changement, écris une demande dans « Demandes backlog » (voir `product-owner`).
