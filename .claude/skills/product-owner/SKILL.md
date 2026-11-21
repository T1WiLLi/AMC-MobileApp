---
name: product-owner
description: Rôle de Product Owner (PO) sur AMC-MobileApp — un seul agent possède et modifie le Backlog du board ; les autres agents demandent des ajouts/changements via « Demandes backlog », le PO les revoit, priorise, rédige les critères d'acceptation et garde le backlog à jour. À lire par tout agent avant de toucher au Backlog, de proposer une tâche, ou de claimer un item.
---

# Product Owner et propriété du Backlog

## Qui est PO

- Le PO actuel est indiqué dans la section **Décisions** du board (dernière décision « PO = … » qui fait foi).
- PO au 2026-11-21 : **`claude-zachary`** (agent Claude Code de zachary).
- Changer de PO = une décision validée par les humains, écrite dans « Décisions ». Un agent ne s'auto-proclame jamais PO.

## Règle d'or : seul le PO écrit dans « Backlog »

- **Seul le PO** ajoute, modifie, réordonne, découpe, fusionne ou retire un item de la section **Backlog** du board.
- Tous les autres agents **lisent** le Backlog et **choisissent** un item `prêt` à claimer — c'est tout.
- Un agent qui veut un nouvel item, un changement de priorité, un découpage, une correction de critères ou la suppression d'un item écrit une **demande** dans la section **Demandes backlog** (format ci-dessous). Il ne touche pas au Backlog lui-même.
- Si un non-PO modifie le Backlog quand même, le PO déplace la modification en demande, rétablit le Backlog et le note dans le journal (sans effacer le texte de l'autre : il est recopié dans la demande).

## Format du Backlog (tenu par le PO)

Table triée par priorité (le haut = le plus important) :

```
| ID | Item | Priorité | Critères d'acceptation | Dépend de | Statut |
```

- ID : `B-001`, `B-002`, … (incrémental, jamais réutilisé).
- Priorité : `P0` (bloquant / prochain), `P1` (important), `P2` (plus tard).
- Critères d'acceptation : courts et vérifiables (« l'onglet X affiche Y avec données fake, état vide soigné, preview clair/sombre »).
- Statut : `à affiner` (pas encore claimable) → `prêt` → `claimé (T-xxx)` → `fait (PR #n)` / `abandonné`.
- Un item doit être assez petit pour une PR. Sinon le PO le découpe.

## Format des demandes (écrites par n'importe quel agent)

```
| ID | De (agent) | Type | Demande | Pourquoi | Décision PO | Statut |
```

- ID : `R-001`, `R-002`, … (incrémental).
- Type : `ajout`, `modif`, `priorité`, `découpage`, `retrait`.
- Statut : `ouverte` → `acceptée (B-xxx)` / `refusée` / `à préciser`.
- Le demandeur n'attend pas la réponse : il prend un autre item `prêt` en attendant.

## Côté agents (non-PO)

- Claimer = prendre un item `prêt` du Backlog ; l'ID du claim (`T-xxx`) cite l'item (`B-xxx`) dans la colonne Tâche.
- Pas d'item `prêt` disponible ? Écris une demande (`R-xxx`) avec ton idée, puis fais de la revue de PR / des tests sur du code existant en attendant la décision du PO. Ne code pas une idée hors backlog.
- Un bug trouvé en cours de tâche : s'il est dans ta zone et minuscule, corrige-le dans ta PR ; sinon, demande `R-xxx`.
- Quand ta PR est mergée, passe ton claim à `fini` ; le PO passe l'item à `fait`.

## Côté PO

À chaque passage sur le board (boucle `agent-coordination`) :

1. Traiter **toutes** les demandes `ouverte` : accepter (créer/modifier l'item, noter `acceptée (B-xxx)`), refuser (une phrase de pourquoi) ou demander une précision. Viser une réponse en moins de 30 min.
2. Synchroniser les statuts : items claimés (lire « Tâches en cours »), items faits (PR mergées sur GitHub : `gh pr list --state merged`).
3. Garder **au moins 3 items `prêt`** en tête pour que personne ne tourne à vide ; affiner les `à affiner` (critères d'acceptation, découpage, dépendances).
4. Éviter que deux items `prêt` touchent les mêmes fichiers en même temps quand c'est évitable (moins de conflits).
5. Les arbitrages produit qui engagent tout le monde vont dans « Décisions » ; les questions produit pour un humain passent par son agent (« Questions entre agents ») ou directement à l'humain du PO.
6. Journaliser chaque changement du Backlog en une ligne (`B-xxx ajouté / repriorisé / découpé / retiré — pourquoi`).

Le PO peut aussi coder, mais le backlog passe avant : il ne laisse jamais de demande `ouverte` sans réponse pendant qu'il code.
