---
name: git-workflow
description: Workflow Git/GitHub de AMC-MobileApp pour plusieurs agents en parallèle — un worktree par agent, une branche par tâche, pull fréquent, CI obligatoire et auto-merge, vérifier et merger ses PR et relire celles des autres, un seul simulateur (iPhone 17) partagé sous verrou. À utiliser avant tout commit, push, PR, build ou test, et au début d'une tâche.
---

# Workflow Git

- Repo : https://github.com/T1WiLLi/AMC-MobileApp (remote `origin`)
- Branche principale : `main`, **protégée** : le check CI « Build et tests (iOS 26) » est obligatoire pour merger, pas de push direct, pas de force-push. Toujours buildable.
- `gh` CLI est connecté : utilise-le pour les PR, les checks et le merge.

## Un agent = un worktree (OBLIGATOIRE)

Plusieurs sessions ont partagé le même dossier : un `git switch` de l'une a changé la branche de l'autre, et un `git push origin HEAD` est parti sur `main`. Plus jamais :

```bash
git worktree add ../AMC-MobileApp-<agent> origin/main     # une fois par agent
cd ../AMC-MobileApp-<agent>
```

- Ne fais **jamais** `git switch` ou `git checkout` dans un dossier qu'un autre agent utilise.
- Vérifie ta branche avant chaque commit et push : `git branch --show-current`.
- Un sous-agent travaille dans son propre worktree (outil Agent avec `isolation: "worktree"`).

## Une tâche = une branche = une PR

```bash
git fetch origin && git switch -c <type>/<sujet-court> origin/main
```

Types : `feat`, `fix`, `refactor`, `chore`, `test`, `docs`. Indique la branche dans ton claim (`agent-coordination`).

PR empilée (ta tâche dépend d'une PR pas encore mergée) : pars de sa branche, écris en tête de la description « Empilée sur #N : à merger après », et n'active l'auto-merge qu'une fois #N mergée.

## Pull souvent

- Avant de commencer, avant chaque commit, avant chaque PR, et au minimum toutes les ~15 min :
  ```bash
  git fetch origin && git rebase origin/main
  ```
- Conflit : résous-le en gardant le travail des deux côtés ; si le conflit touche la zone d'un autre agent, demande-lui dans le board avant de trancher.
- Après un rebase, rebuild avant de pousser.

## Build et tests : un seul simulateur, l'iPhone 17

- Un seul simulateur pour toute l'équipe : **iPhone 17**. Ne crée pas d'autres simulateurs.
- Toujours `-parallel-testing-enabled NO` : sinon Xcode crée des « Clone of iPhone 17 ».
- Plusieurs agents partagent ce simulateur : prends le verrou avant chaque `xcodebuild test` ou `simctl install/launch`, libère-le juste après, même en cas d'échec :
  ```bash
  until mkdir /tmp/amc-sim.lock 2>/dev/null; do sleep 10; done
  xcodebuild test -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp \
    -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
  rmdir /tmp/amc-sim.lock
  ```
- Un simple build n'a pas besoin du simulateur : `-destination 'generic/platform=iOS Simulator'`.
- Mets un `-derivedDataPath` à toi (par exemple dans ton scratchpad) pour ne pas écraser le build d'un autre agent.

## Commits

- Petits et fréquents, message à l'impératif, en français : `feat(items): écran détail en Liquid Glass`.
- Jamais de secrets (`GoogleService-Info.plist` reste hors git), ni `xcuserdata/`, `DerivedData/`, `.DS_Store`.
- Le projet doit compiler à chaque commit poussé.

## Push, PR, CI et merge

```bash
git push -u origin HEAD
gh pr create --base main --title "<type>(<zone>): …" --body "…"
gh pr merge --auto --squash --delete-branch    # se merge tout seul quand la CI est verte
```

- Une PR par tâche, petite. Dans la description : ce qui change, captures si UI, l'ID du claim (`T-012`), et le résultat des tests locaux.
- La CI (`.github/workflows/ci.yml`) build et teste chaque PR sur un runner macOS (environ 6 min). **On merge dès que c'est vert**, sans attendre de relecture : l'auto-merge le fait pour toi.
- Lien de la PR dans le journal du board, claim passé à `en review`, puis `fini` après le merge.

## Surveiller ses PR et relire celles des autres (à chaque tour de boucle)

```bash
gh pr list --author @me                    # mes PR : CI rouge ? conflit ? auto-merge actif ?
gh pr checks <n>                           # pourquoi c'est rouge
gh pr list                                 # PR des autres agents
```

- CI rouge sur ta PR : corrige tout de suite (c'est prioritaire sur une nouvelle tâche).
- Conflit sur ta PR : `git fetch origin && git rebase origin/main`, rebuild, `git push --force-with-lease`.
- PR empilée dont la base vient d'être mergée : rebase sur `main` et active l'auto-merge.
- PR d'un autre agent ouverte depuis longtemps, sans check, ou qui touche ta zone : relis-la (`gh pr diff <n>`), teste-la si tu es sur Mac et lui non, commente dans la PR **et** note-le dans le board. Ne pousse jamais sur sa branche sans son accord.

## Interdits

- Push direct ou force-push sur `main` (de toute façon refusé par la protection).
- Réécrire l'historique d'une branche d'un autre agent, ou pousser dessus sans son accord.
- Partager un dossier de travail entre deux agents qui codent.
- Modifier `AMC-MobileApp.xcodeproj/project.pbxproj` sans l'annoncer dans le board : c'est le fichier qui conflicte le plus. Les dossiers sont synchronisés (Xcode 16+) : un nouveau `.swift` dans `AMC-MobileApp/` est inclus automatiquement, sans toucher au pbxproj. Ne le modifie que pour un vrai réglage (cible, capability, paquet).
- Ajouter un `.gitkeep` dans `AMC-MobileApp/` : Xcode le copie dans l'app et le build casse.
