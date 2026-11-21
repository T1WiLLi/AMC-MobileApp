# Fixtures du catalogue de démo (B-026)

Données lues par le script de seed (B-025) pour remplir l'émulateur ou le projet de démo.
Chaque fichier est un tableau JSON de documents, avec les mêmes champs que les modèles Swift de `AMC-MobileApp/Core/Models/`.
Le champ `id` sert d'id de document Firestore.

| Fichier | Collection | Contenu |
| --- | --- | --- |
| `vendors.json` | `vendors` | 6 vendeurs : 3 fermes (dont Ferme Lafleur, persona de démo), 1 coopérative, 2 grossistes |
| `products.json` | `products` | 40 produits, les 9 catégories de RQ-039 |
| `offers.json` | `offers` | 25 lots, 3 paliers chacun ; 23 actifs, 2 en brouillon |

Particularités à gérer dans le script :

- `offers[].deadlineInDays` : nombre de jours à partir du moment du seed. Le script le convertit en `deadline` (Timestamp), pour que la démo reste rejouable. Ne pas écrire `deadlineInDays` dans Firestore.
- `zones` et `servedZones` : identifiants des quartiers des 8 groupes de B-027 (`parc-extension`, `rosemont`, `hochelaga`, `saint-michel`, `verdun`, `cote-des-neiges`, `montreal-nord`, `villeray`).
- `products[].referencePriceSource` : d'où vient le prix d'épicerie de référence (RQ-113). Ce sont des estimations à vérifier, pas des relevés.
- Les montants sont en cents (CAD). Le prix d'un palier est le prix d'une part ; une part = une unité du produit (`shareUnit` = `unit`).

Modification : changez les fichiers à la main ou régénérez-les, puis lancez les tests (`AMC-MobileAppTests/Seed/SeedFixtureTests.swift`). Ils vérifient que tout se décode avec les modèles Swift et que les liens entre fichiers sont cohérents.
