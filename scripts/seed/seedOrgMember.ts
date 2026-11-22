// Rattache un compte existant à l'organisme de démo (T-194) : écrit `users/{uid}.organizationId` (que les règles
// interdisent au client) et ajoute l'uid à `organizations/{orgId}.memberUserIds`. Au prochain lancement de l'app,
// ce compte voit le portail Organisme. DRY-RUN PAR DÉFAUT : rien n'est écrit sans --yes.
//
//   Émulateur (défaut) : npm --prefix scripts/seed run seed:org-member -- --email x@y.z [--yes]
//   Projet réel        : npm --prefix scripts/seed run seed:org-member -- --email x@y.z --target cloud          (dry-run)
//                        npm --prefix scripts/seed run seed:org-member -- --email x@y.z --target cloud --yes    (écrit)
//
// Prérequis : l'organisme existe (`seed:org`) et le compte s'est déjà connecté une fois (son profil users/{uid}
// existe). Idempotent. Pour détacher un compte, supprimez le champ à la main dans la console Firebase.
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'
import { connect } from './firestoreRest.ts'
import { organizationId, planMemberWrites } from './organizations.ts'

async function main() {
  const { values } = parseArgs({
    options: {
      email: { type: 'string' },
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string', default: 'amc-2026-8ab03' },
      yes: { type: 'boolean', default: false }
    }
  })
  const email = values.email?.trim().toLowerCase()
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('--email <courriel> est requis')
  const client = connect(values.target, values.project)
  console.log(`Cible : ${client.label}`)

  const uid = await client.uidForEmail(email)
  if (!uid) throw new Error(`Aucun compte Auth pour ${email}.`)
  const user = await client.getFields(`users/${uid}`)
  if (!user) throw new Error(`Le compte ${email} (${uid}) n'a pas encore de profil users/${uid} : qu'il ouvre l'app une fois.`)
  if (!(await client.getFields(`organizations/${organizationId}`))) {
    throw new Error(`organizations/${organizationId} est introuvable : lancez d'abord seed:org.`)
  }
  const current = (user.organizationId as { stringValue?: string } | undefined)?.stringValue
  console.log(`Compte ${email} (${uid}) -> organisme ${organizationId}` +
    (current ? ` (organizationId actuel : ${current})` : ''))

  if (!values.yes) {
    console.log('[dry-run] Aucune écriture : relancez avec --yes pour appliquer.')
    return
  }
  await client.commit(planMemberWrites(uid, client.docName))
  console.log('Compte rattaché : relancez l\'app (ou reconnectez-vous) pour voir le portail Organisme.')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error)
    process.exitCode = 1
  })
}
