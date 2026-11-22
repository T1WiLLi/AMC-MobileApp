# Réinitialiser les données de démo de Grenier

> Pour remplir le **vrai projet** `amc-2026-8ab03` (ou un émulateur) sans rien supprimer, utilisez `seedFirestore.ts` : il écrit les mêmes documents et crée ou met à jour les mêmes comptes de démo (voir `docs/firebase.md`, section 6).

Le script B-025 vide Firestore `(default)` et les comptes Auth du projet d’émulateur sélectionné. Il recharge ensuite toutes les [fixtures](fixtures/README.md) avec le SDK Firebase Admin : le catalogue (vendeurs, produits, lots), les groupes, les points de cueillette, les utilisateurs, les ménages et les commandes groupées. Il crée enfin les comptes Auth de démo (B-029).

## Préparer la démo locale

Depuis la racine du dépôt, avec Node.js 22 (22.18 ou plus récent) ou 24 LTS, et Java 21 ou plus récent, installez les dépendances et démarrez les émulateurs.

```sh
npm --prefix scripts/seed ci
npx --yes firebase-tools@15.37.0 emulators:start --project demo-grenier --only auth,firestore
```

Dans un autre terminal, depuis la racine du dépôt, lancez le seed.

```sh
GRENIER_DEMO_PASSWORD='…' npm --prefix scripts/seed run seedDemo
```

## Comptes de démo

Chaque utilisateur de `users.json` reçoit un compte Auth dont l’uid est l’id du document `users`. Les trois personas sont :

| Persona | uid | Courriel |
| --- | --- | --- |
| Amina (famille, Parc-Extension) | `user-amina` | `amina@demo.grenier.local` |
| Ferme Lafleur (vendeur) | `user-ferme-lafleur` | `ferme-lafleur@demo.grenier.local` |
| Jean (hôte, Parc-Extension) | `user-jean` | `jean@demo.grenier.local` |

Les hôtes des autres points de cueillette suivent le même modèle (`user-hote-rosemont` → `hote-rosemont@demo.grenier.local`). Tous les comptes partagent un mot de passe qui n’est jamais versionné : le script lit `GRENIER_DEMO_PASSWORD` (6 caractères ou plus). Sans cette variable, il en génère un et l’affiche une fois à la fin de l’exécution. Partagez le mot de passe de l’équipe hors du dépôt (gestionnaire de mots de passe).

L’app, les émulateurs et le script doivent utiliser le même identifiant de projet. Pour changer de projet local, choisissez un identifiant `demo-*`, passez-le à la CLI Firebase et ajoutez `-- --project demo-mon-projet` à la commande `seedDemo`. Les ports par défaut sont 8080 (Firestore) et 9099 (Auth). Les variables `FIRESTORE_EMULATOR_HOST` et `FIREBASE_AUTH_EMULATOR_HOST` permettent de sélectionner d’autres ports sur la boucle locale.

Avant de vider les émulateurs, le script charge et valide toutes les fixtures (références entre fichiers comprises), puis vérifie que les deux services répondent. Les identifiants des documents sont stables. Les échéances des lots partent du début du jour UTC et les créneaux de cueillette sont placés à l’heure de Montréal à partir de la même date, pour que deux exécutions le même jour produisent le même contenu Firestore. Les ménages sont aussi écrits dans `groups/{groupId}/members/{householdId}` et `households/{id}/private/profile`, et les parts dans `groupOrders/{id}/shares/{householdId}`. Pendant la réinitialisation, suspendez les écritures de l’app sur ce projet. En cas d’interruption, relancez le script. Si le verrou temporaire subsiste, vérifiez que le PID qu’il contient a quitté, puis retirez le fichier indiqué dans le message d’erreur.

La réinitialisation cloud est en attente de la confirmation du projet de démo (Q-011). La commande actuelle accepte exclusivement des identifiants `demo-*` et des hôtes locaux.

## Vérifier le script

```sh
npm --prefix scripts/seed run check
npm --prefix scripts/seed test
npx --yes firebase-tools@15.37.0 emulators:exec --project demo-grenier-seed-test --only auth,firestore 'npm --prefix scripts/seed run test:emulators'
```

Le test `seedDemo.integration.ts` lance la commande deux fois sur un projet jetable, avec puis sans `GRENIER_DEMO_PASSWORD`. Il vérifie la suppression d’un compte et d’un document en sous-collection, le contenu de Firestore (sous-collections comprises) et la connexion des trois personas à chaque passage. Arrêtez les autres émulateurs qui occupent les ports par défaut avant de lancer ce test.

`seedFirestore.integration.ts` lance `seedFirestore.ts` deux fois sur le même projet : il vérifie qu’un document et un compte étrangers au seed survivent, que les comptes sont créés puis mis à jour, et que les personas se connectent avec le mot de passe courant.

## Portail Organismes (T-194)

`seedOrganization.ts` crée l'organisme de démo (banque alimentaire de Côte-des-Neiges : 5 dons simulés, 2 parrainages, le fonds de solidarité de 3 groupes). Il ne supprime rien et n'écrase ni les membres de l'organisme ni le solde d'un fonds déjà présent. `seedOrgMember.ts` rattache un compte existant (`users/{uid}.organizationId`, champ que les règles interdisent au client) : le compte doit s'être connecté une fois et l'organisme doit exister. Les deux sont en **dry-run par défaut** : rien n'est écrit sans `--yes`. Il faut d'abord que les groupes de démo existent (`seed:firestore`).

```sh
# Émulateur (défaut)
npm --prefix scripts/seed run seed:org -- --yes
npm --prefix scripts/seed run seed:org-member -- --email amina@demo.grenier.local --yes

# Projet réel : à lancer par un humain (dry-run d'abord)
npm --prefix scripts/seed run seed:org -- --target cloud
npm --prefix scripts/seed run seed:org -- --target cloud --yes
npm --prefix scripts/seed run seed:org-member -- --email <courriel> --target cloud
npm --prefix scripts/seed run seed:org-member -- --email <courriel> --target cloud --yes
```
