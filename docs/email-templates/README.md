# Courriels d'authentification Grenier

Modèles HTML des trois courriels que Firebase Auth envoie : vérification d'adresse (`verify`), nouveau mot de passe (`reset`) et changement d'adresse de connexion (`change-email`).

- Mise en page compatible avec les clients mail : tableaux, styles en ligne, 600 px de large, aucune image ni police externe.
- Couleurs Grenier : accent `#B4521A`, fond `#FBF7F2`, texte `#1C1712`. Bouton plein orange arrondi, lien de secours sous le bouton, pied de page « le garde-manger du quartier ».
- Variables Firebase utilisées : `%LINK%`, `%EMAIL%` et `%NEW_EMAIL%`. `%DISPLAY_NAME%` n'est pas utilisé, car il est vide pour un compte courriel/mot de passe sans nom (« Bonjour , »).

Les fichiers sont générés : modifie les textes dans `build.mjs`, puis lance :

```bash
node docs/email-templates/build.mjs
```

## Quel fichier coller ?

Firebase n'accepte **qu'un seul corps personnalisé par modèle**, quelle que soit la langue. Sans personnalisation, il traduit son texte standard dans la langue de l'app. Une fois le corps personnalisé, tout le monde reçoit ce corps-là. Donc :

| Fichier | Usage |
|---|---|
| `*.bilingual.html` | **À coller dans Firebase.** Français d'abord, anglais en dessous. |
| `*.fr.html`, `*.en.html` | Versions d'une seule langue : référence, ou pour un futur envoi par un autre service qui choisit la langue. |

Les objets à utiliser sont dans `subjects.json`, en version bilingue.

## Ce que Firebase permet de modifier

Console Firebase › Authentication › Templates (onglet « Email templates ») :

| Modèle | Nom d'expéditeur | Objet | Corps HTML |
|---|---|---|---|
| Vérification d'adresse | oui | oui | oui |
| Réinitialisation du mot de passe | oui | oui | oui |
| Changement d'adresse | oui | oui | **non** dans la console (« pour éviter le spam ») ; l'API d'administration expose quand même le champ |

- **Expéditeur** : « Grenier » est déjà en place sur les trois modèles. L'adresse est `noreply@amc-2026-8ab03.firebaseapp.com` tant qu'aucun domaine personnalisé n'est configuré (« Customize domain »).
- **Langue** : le sélecteur « Template language » ne règle que la langue des modèles **non personnalisés**. D'où les fichiers bilingues.
- **URL d'action** : le lien `%LINK%` mène à la page standard `https://amc-2026-8ab03.firebaseapp.com/__/auth/action`. Une page à la marque Grenier demande d'héberger notre propre page de traitement (Firebase Hosting ou lien universel vers l'app), puis de régler « Customize action URL ». Ce n'est pas fait.

## Appliquer dans la console

Pour chacun des trois modèles :

1. Ouvre Authentication › Templates, puis le modèle, puis le crayon.
2. **Sender name** : `Grenier`.
3. **Subject** : la valeur `bilingual` du modèle dans `subjects.json`.
4. **Message** : colle tout le contenu du fichier `<modèle>.bilingual.html`. Pour le changement d'adresse, si le champ est verrouillé, laisse le message standard.
5. Clique sur **Save**.

Pour vérifier : crée un compte de test dans l'app, ou utilise « Mot de passe oublié », et regarde le courriel reçu, y compris dans les courriels indésirables.

## Appliquer par l'API (au lieu de la console)

`PATCH https://identitytoolkit.googleapis.com/admin/v2/projects/<projet>/config` avec `updateMask=notification.sendEmail.verifyEmailTemplate.body,…` et le jeton de `firebase login`. C'est une écriture sur le vrai projet : demande d'abord l'accord du propriétaire du projet.
