---
name: git-workflow
description: Workflow Git/GitHub de AMC-MobileApp pour plusieurs agents en parallèle — URL du repo, une branche par tâche, pull fréquent, rebase, commits courts, push et pull requests, résolution de conflits. À utiliser avant tout commit, push, PR, ou au début d'une tâche.
---

# Workflow Git

- Repo : https://github.com/T1WiLLi/AMC-MobileApp (remote `origin`)
- Branche principale : `main` (toujours buildable).
- `gh` CLI est connecté : utilise-le pour issues et PR.

## Une tâche = une branche

```bash
git switch main && git pull --rebase origin main
git switch -c <type>/<sujet-court>      # feat/item-detail, fix/tabbar-glass, chore/fake-data
```

Types : `feat`, `fix`, `refactor`, `chore`, `test`, `docs`. Indique la branche dans ton claim (`agent-coordination`).

## Pull souvent

- Avant de commencer, avant chaque commit, avant chaque PR, et au minimum toutes les ~15 min :
  ```bash
  git fetch origin && git rebase origin/main
  ```
- Conflit : résous-le en gardant le travail des deux côtés ; si le conflit touche la zone d'un autre agent, demande-lui dans le board avant de trancher.
- Après un rebase, rebuild avant de pousser.

## Commits

- Petits et fréquents, message à l'impératif, en français ou anglais mais cohérent : `feat(items): écran détail en Liquid Glass`.
- Jamais de secrets, de `xcuserdata/`, `DerivedData/`, `.DS_Store` (déjà dans `.gitignore`).
- Le projet doit compiler à chaque commit poussé :
  ```bash
  xcodebuild -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
  (adapte le nom du simulateur à ceux disponibles : `xcrun simctl list devices available`).

## Push et PR

```bash
git push -u origin HEAD
gh pr create --base main --fill
```

- Une PR par tâche, petite. Dans la description : ce qui change, captures d'écran si UI, l'ID du claim (`T-012`).
- Lien de la PR dans le journal du board, claim passé à `en review`.
- Relis les PR des autres agents quand tu n'as rien d'urgent ; commente dans la PR **et** note-le dans le board.
- Merge : squash, une fois buildable et sans conflit. Après merge : supprime la branche, passe le claim à `fini`, journalise.

## Interdits

- `git push --force` sur `main` (sur ta propre branche : `--force-with-lease` seulement).
- Committer directement sur `main`, sauf micro-fix de config annoncé dans le board.
- Réécrire l'historique d'une branche d'un autre agent.
- Modifier `AMC-MobileApp.xcodeproj/project.pbxproj` sans l'annoncer : c'est le fichier qui conflicte le plus. Le projet utilise des dossiers synchronisés (Xcode 16+) : un nouveau `.swift` dans `AMC-MobileApp/` est inclus automatiquement, **pas besoin** de toucher au pbxproj pour ajouter des fichiers. Ne le modifie que pour un vrai réglage (target, capability, package), annoncé dans le board.
