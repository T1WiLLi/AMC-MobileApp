# Réinitialiser les données de démo de Grenier

Le script B-025 vide Firestore `(default)` et les comptes Auth du projet d’émulateur sélectionné. Il recharge ensuite le catalogue B-026 (vendeurs, produits et lots) avec le SDK Firebase Admin. Les comptes des personas arriveront avec B-029.

## Préparer la démo locale

Depuis la racine du dépôt, avec Node.js 22 (22.18 ou plus récent) ou 24 LTS, et Java 21 ou plus récent, installez les dépendances et démarrez les émulateurs.

```sh
npm --prefix scripts/seed ci
npx --yes firebase-tools@15.37.0 emulators:start --project demo-grenier --only auth,firestore
```

Dans un autre terminal, depuis la racine du dépôt, lancez le seed.

```sh
npm --prefix scripts/seed run seedDemo
```

L’app, les émulateurs et le script doivent utiliser le même identifiant de projet. Pour changer de projet local, choisissez un identifiant `demo-*`, passez-le à la CLI Firebase et ajoutez `-- --project demo-mon-projet` à la commande `seedDemo`. Les ports par défaut sont 8080 (Firestore) et 9099 (Auth). Les variables `FIRESTORE_EMULATOR_HOST` et `FIREBASE_AUTH_EMULATOR_HOST` permettent de sélectionner d’autres ports sur la boucle locale.

Avant de vider les émulateurs, le script charge les trois fichiers du [catalogue](fixtures/README.md) et vérifie que les deux services répondent. Les identifiants des documents sont stables. Les échéances des lots partent du début du jour UTC pour que deux exécutions le même jour produisent le même catalogue. Pendant la réinitialisation, suspendez les écritures de l’app sur ce projet. En cas d’interruption, relancez le script. Si le verrou temporaire subsiste, vérifiez que le PID qu’il contient a quitté, puis retirez le fichier indiqué dans le message d’erreur.

La réinitialisation cloud est en attente de la confirmation du projet de démo (Q-011). La commande actuelle accepte exclusivement des identifiants `demo-*` et des hôtes locaux.

## Vérifier le script

```sh
npm --prefix scripts/seed run check
npm --prefix scripts/seed test
npx --yes firebase-tools@15.37.0 emulators:exec --project demo-grenier-seed-test --only auth,firestore 'npm --prefix scripts/seed run test:emulators'
```

Le test d’intégration lance la commande deux fois sur un projet jetable. Il vérifie la suppression d’un compte et d’un document en sous-collection ainsi que le contenu de Firestore à chaque passage. Arrêtez les autres émulateurs qui occupent les ports par défaut avant de lancer ce test.
