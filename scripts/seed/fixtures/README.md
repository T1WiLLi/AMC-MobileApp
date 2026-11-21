# Fixtures de démo (B-026, B-027, B-029)

Données lues par le script de seed (B-025) pour remplir l'émulateur ou le projet de démo.
Chaque fichier est un tableau JSON de documents, avec les mêmes champs que les modèles Swift de `AMC-MobileApp/Core/Models/`.
Le champ `id` sert d'id de document Firestore.

| Fichier | Collection | Contenu |
| --- | --- | --- |
| `vendors.json` | `vendors` | 6 vendeurs : 3 fermes (dont Ferme Lafleur, persona de démo), 1 coopérative, 2 grossistes |
| `products.json` | `products` | 40 produits, les 9 catégories de RQ-039 |
| `offers.json` | `offers` | 25 lots, 3 paliers chacun ; 23 actifs, 2 en brouillon |
| `groups.json` | `groups` | 8 groupes publics de quartier (B-027) |
| `pickupPoints.json` | `pickupPoints` | 9 points de cueillette, au moins un par groupe (B-027) |
| `users.json` | `users` | 3 personas de démo (B-029) + 8 hôtes de points de cueillette |
| `households.json` | `households` | fourni par B-028 |
| `groupOrders.json` | `groupOrders` | fourni par B-028 |

Particularités à gérer dans le script :

- `offers[].deadlineInDays` : nombre de jours à partir du moment du seed. Le script le convertit en `deadline` (Timestamp), pour que la démo reste rejouable. Ne pas écrire `deadlineInDays` dans Firestore.
- `zones` et `servedZones` : identifiants des quartiers des 8 groupes de B-027 (`parc-extension`, `rosemont`, `hochelaga`, `saint-michel`, `verdun`, `cote-des-neiges`, `montreal-nord`, `villeray`).
- `products[].referencePriceSource` : d'où vient le prix d'épicerie de référence (RQ-113). Ce sont des estimations à vérifier, pas des relevés.
- Les montants sont en cents (CAD). Le prix d'un palier est le prix d'une part ; une part = une unité du produit (`shareUnit` = `unit`).

## groups.json (B-027)

IDs fixes, utilisés par d'autres fichiers : `group-parc-extension`, `group-rosemont`, `group-hochelaga`, `group-saint-michel`, `group-verdun`, `group-cote-des-neiges`, `group-montreal-nord`, `group-villeray`.

- `neighborhood` : le slug du quartier (mêmes valeurs que `zones`).
- `centerGeohash` : geohash de précision 6 du centre du quartier.
- `householdCount` : 10 pour Parc-Extension, 8 pour Rosemont, 7 pour les six autres (60 au total). Doit correspondre aux membres écrits à partir de `households.json`.
- `coordinatorIds` : ids d'utilisateurs. `user-jean` coordonne Parc-Extension ; les autres groupes n'ont pas encore de coordinateur.
- Champs en plus du modèle Swift (ignorés au décodage, le script peut les écrire tels quels) : `description`, `latitude`, `longitude`, `pickupPointIds` (ids de `pickupPoints.json`).

## pickupPoints.json (B-027)

IDs `pickup-<slug>-<n>`. Parc-Extension en a deux, les autres groupes un seul. `pickup-parc-extension-1` est tenu par Jean (`user-jean`).

- Lieux et adresses vraisemblables mais inventés (sous-sols d'église, centres communautaires, cafés, bibliothèques).
- `slotTemplates` : à convertir par le script en `slots` (`PickupSlot`, Timestamps), comme `deadlineInDays`. Chaque gabarit `{ "inDays", "start", "end" }` donne un créneau le jour du seed + `inDays`, de `start` à `end` (heure locale de Montréal, `HH:mm`). Ne pas écrire `slotTemplates` dans Firestore.
- Champs en plus du modèle (le script peut les écrire tels quels) : `groupId`, `neighborhood`, `latitude`, `longitude`, `geohash`.
- `photoURL` est absent (optionnel).

## users.json (B-029)

- `user-amina` : famille, Parc-Extension, ménage `household-amina`, préférences `halal` et `local`.
- `user-ferme-lafleur` : vendeur, `vendorId` = `vendor-ferme-lafleur`.
- `user-jean` : hôte, Parc-Extension, ménage `household-jean`.
- `user-hote-<slug>` : un hôte par quartier pour les autres points de cueillette (dont `user-hote-parc-extension` pour `pickup-parc-extension-2`). Sans ménage.

Aucun courriel ni téléphone (le modèle `AppUser` n'en a pas). Le script doit créer les comptes Auth de démo avec ces mêmes uid s'il en a besoin.

## households.json et groupOrders.json (fournis par B-028)

- Ménages : `household-amina`, `household-jean`, puis `household-001` à `household-058` (60 au total).
- Appartenances : 10 ménages dans `group-parc-extension` (dont Amina et Jean), 8 dans `group-rosemont`, 7 dans chacun des six autres groupes.

## Modification

Changez les fichiers à la main ou régénérez-les, puis lancez les tests (`AMC-MobileAppTests/Seed/SeedFixtureTests.swift` et `SeedGroupsFixtureTests.swift`). Ils vérifient que tout se décode avec les modèles Swift et que les liens entre fichiers sont cohérents.
