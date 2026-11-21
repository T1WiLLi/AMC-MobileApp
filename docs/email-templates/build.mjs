// Génère les modèles de courriels Firebase Auth de Grenier (docs/email-templates/*.html).
//   node docs/email-templates/build.mjs
// Une seule mise en page (tableaux, styles en ligne, 600 px, aucune image) pour tous les modèles.
// Variables Firebase utilisées : %LINK%, %EMAIL%, %NEW_EMAIL%. Pas de %DISPLAY_NAME% : il est vide pour un
// compte courriel/mot de passe sans nom, ce qui donnerait « Bonjour , ».
import { writeFileSync } from 'node:fs'

const color = { accent: '#B4521A', background: '#FBF7F2', text: '#1C1712', muted: '#6B5E52', line: '#EADFD3', card: '#FFFFFF' }
const font = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"

const copy = {
  verify: {
    fr: {
      subject: 'Vérifie ton adresse courriel Grenier',
      preheader: 'Un clic pour confirmer ton adresse et rejoindre ton quartier.',
      title: 'Bienvenue chez Grenier',
      greeting: 'Bonjour,',
      body: 'Confirme que <strong>%EMAIL%</strong> est bien ton adresse pour finir de créer ton compte.',
      button: 'Vérifier mon adresse',
      ignore: 'Tu n’as pas créé de compte Grenier ? Tu peux ignorer ce courriel.'
    },
    en: {
      subject: 'Verify your Grenier email address',
      preheader: 'One tap to confirm your address and join your neighbourhood.',
      title: 'Welcome to Grenier',
      greeting: 'Hi,',
      body: 'Confirm that <strong>%EMAIL%</strong> is your address to finish setting up your account.',
      button: 'Verify my address',
      ignore: 'Didn’t create a Grenier account? You can ignore this email.'
    }
  },
  reset: {
    fr: {
      subject: 'Choisis un nouveau mot de passe Grenier',
      preheader: 'Le lien est valide pendant une heure.',
      title: 'Nouveau mot de passe',
      greeting: 'Bonjour,',
      body: 'Quelqu’un (sans doute toi) a demandé à changer le mot de passe du compte <strong>%EMAIL%</strong>. Le lien est valide pendant une heure.',
      button: 'Choisir un nouveau mot de passe',
      ignore: 'Tu n’as rien demandé ? Ignore ce courriel : ton mot de passe actuel reste le même.'
    },
    en: {
      subject: 'Choose a new Grenier password',
      preheader: 'The link is valid for one hour.',
      title: 'New password',
      greeting: 'Hi,',
      body: 'Someone (probably you) asked to change the password for <strong>%EMAIL%</strong>. The link is valid for one hour.',
      button: 'Choose a new password',
      ignore: 'Didn’t ask for this? Ignore this email: your current password stays the same.'
    }
  },
  'change-email': {
    fr: {
      subject: 'Ton adresse de connexion Grenier a changé',
      preheader: 'Si ce n’est pas toi, tu peux annuler ce changement.',
      title: 'Adresse de connexion modifiée',
      greeting: 'Bonjour,',
      body: 'L’adresse de connexion de ton compte Grenier est maintenant <strong>%NEW_EMAIL%</strong>.',
      button: 'Annuler ce changement',
      ignore: 'C’est bien toi ? Tu n’as rien à faire. Sinon, annule le changement puis choisis un nouveau mot de passe.'
    },
    en: {
      subject: 'Your Grenier sign-in email changed',
      preheader: 'If this wasn’t you, you can undo the change.',
      title: 'Sign-in email changed',
      greeting: 'Hi,',
      body: 'The sign-in email for your Grenier account is now <strong>%NEW_EMAIL%</strong>.',
      button: 'Undo this change',
      ignore: 'Was it you? Nothing to do. If not, undo the change and then choose a new password.'
    }
  }
}

const fallbackLabel = { fr: 'Le bouton ne marche pas ? Copie ce lien dans ton navigateur :', en: 'Button not working? Paste this link into your browser:' }
const tagline = { fr: 'le garde-manger du quartier', en: 'the neighbourhood pantry' }
const reason = { fr: 'Courriel automatique envoyé par Grenier. Merci de ne pas y répondre.', en: 'Automated email from Grenier. Please do not reply.' }

function block(text, lang) {
  return `
          <tr><td style="padding:0 40px 8px 40px;font-family:${font};font-size:24px;line-height:30px;font-weight:700;color:${color.text};">${text.title}</td></tr>
          <tr><td style="padding:8px 40px 0 40px;font-family:${font};font-size:16px;line-height:24px;color:${color.text};">${text.greeting}</td></tr>
          <tr><td style="padding:8px 40px 24px 40px;font-family:${font};font-size:16px;line-height:24px;color:${color.text};">${text.body}</td></tr>
          <tr><td align="left" style="padding:0 40px 24px 40px;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
              <td align="center" bgcolor="${color.accent}" style="border-radius:12px;background-color:${color.accent};">
                <a href="%LINK%" target="_blank" style="display:inline-block;padding:14px 28px;font-family:${font};font-size:16px;line-height:20px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:12px;">${text.button}</a>
              </td>
            </tr></table>
          </td></tr>
          <tr><td style="padding:0 40px 8px 40px;font-family:${font};font-size:13px;line-height:20px;color:${color.muted};">${fallbackLabel[lang]}</td></tr>
          <tr><td style="padding:0 40px 24px 40px;font-family:${font};font-size:13px;line-height:20px;word-break:break-all;"><a href="%LINK%" target="_blank" style="color:${color.accent};text-decoration:underline;">%LINK%</a></td></tr>
          <tr><td style="padding:0 40px 32px 40px;font-family:${font};font-size:14px;line-height:22px;color:${color.muted};">${text.ignore}</td></tr>`
}

function page(lang, sections, preheader) {
  const separator = `
          <tr><td style="padding:0 40px 32px 40px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="border-top:1px solid ${color.line};font-size:0;line-height:0;">&nbsp;</td></tr></table></td></tr>`
  const footerLang = lang === 'en' ? 'en' : 'fr'
  const footerTagline = lang === 'bilingual' ? `${tagline.fr} · ${tagline.en}` : tagline[footerLang]
  const footerReason = lang === 'bilingual' ? `${reason.fr}<br>${reason.en}` : reason[footerLang]
  return `<!DOCTYPE html>
<html lang="${lang === 'en' ? 'en' : 'fr'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>Grenier</title>
</head>
<body style="margin:0;padding:0;background-color:${color.background};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${color.background};">${preheader}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${color.background}" style="background-color:${color.background};">
  <tr><td align="center" style="padding:32px 16px;">
    <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;">
      <tr><td style="padding:0 8px 20px 8px;font-family:${font};font-size:22px;line-height:28px;font-weight:800;letter-spacing:-0.3px;color:${color.accent};">Grenier</td></tr>
      <tr><td bgcolor="${color.card}" style="background-color:${color.card};border:1px solid ${color.line};border-radius:20px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
          <tr><td style="height:36px;font-size:0;line-height:0;">&nbsp;</td></tr>${sections.join(separator)}
        </table>
      </td></tr>
      <tr><td align="center" style="padding:24px 16px 0 16px;font-family:${font};font-size:13px;line-height:20px;color:${color.muted};"><strong style="color:${color.accent};">Grenier</strong> — ${footerTagline}</td></tr>
      <tr><td align="center" style="padding:4px 16px 0 16px;font-family:${font};font-size:12px;line-height:18px;color:${color.muted};">${footerReason}</td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>
`
}

const directory = new URL('./', import.meta.url)
const subjects = []
for (const [name, { fr, en }] of Object.entries(copy)) {
  writeFileSync(new URL(`${name}.fr.html`, directory), page('fr', [block(fr, 'fr')], fr.preheader))
  writeFileSync(new URL(`${name}.en.html`, directory), page('en', [block(en, 'en')], en.preheader))
  writeFileSync(new URL(`${name}.bilingual.html`, directory), page('bilingual', [block(fr, 'fr'), block(en, 'en')], `${fr.preheader} · ${en.preheader}`))
  subjects.push({ name, fr: fr.subject, en: en.subject, bilingual: `${fr.subject} · ${en.subject}` })
}
writeFileSync(new URL('subjects.json', directory), `${JSON.stringify(subjects, null, 2)}\n`)
console.log(`${subjects.length * 3} modèles générés.`)
