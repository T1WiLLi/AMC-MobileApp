// Seed du portail Organismes (T-194) : l'organisme de démo (banque alimentaire de Côte-des-Neiges), ses dons,
// ses parrainages et le fonds de solidarité de trois groupes. Ne supprime rien. DRY-RUN PAR DÉFAUT : rien n'est
// écrit sans --yes.
//
//   Émulateur (défaut) : npm --prefix scripts/seed run seed:org [-- --yes]
//   Projet réel        : npm --prefix scripts/seed run seed:org -- --target cloud          (dry-run)
//                        npm --prefix scripts/seed run seed:org -- --target cloud --yes    (écrit)
//
// Les groupes de démo (group-cote-des-neiges, group-parc-extension, group-rosemont) doivent exister : lancez
// d'abord `seed:firestore`. Pour rattacher un compte à l'organisme : `seed:org-member` (seedOrgMember.ts).
import { readFile } from 'node:fs/promises'
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'
import { connect } from './firestoreRest.ts'
import { buildOrganizationSeed, describeSeed, organizationId, planOrganizationWrites, type GroupInfo } from './organizations.ts'

async function main() {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string', default: 'amc-2026-8ab03' },
      yes: { type: 'boolean', default: false }
    }
  })
  const client = connect(values.target, values.project)
  const groups = JSON.parse(await readFile(new URL('./fixtures/groups.json', import.meta.url), 'utf8')) as GroupInfo[]
  const seed = buildOrganizationSeed(groups)
  console.log(`Cible : ${client.label}`)
  for (const line of describeSeed(seed)) console.log(line)

  // Les groupes doivent déjà exister dans la cible : un fonds ne vit pas sans son groupe.
  for (const fund of seed.funds) {
    if (!(await client.getFields(`groups/${fund.groupId}`))) {
      throw new Error(`groups/${fund.groupId} est introuvable dans la cible : lancez d'abord seed:firestore.`)
    }
  }
  const existing = {
    organization: (await client.getFields(`organizations/${organizationId}`)) !== null,
    funds: new Set<string>()
  }
  for (const fund of seed.funds) {
    if (await client.getFields(fund.path)) existing.funds.add(fund.groupId)
  }
  console.log(`Organisme ${existing.organization ? 'déjà présent : profil mis à jour, membres conservés' : 'à créer'} ; ` +
    `fonds déjà présents : ${[...existing.funds].join(', ') || 'aucun'}`)

  if (!values.yes) {
    console.log('[dry-run] Aucune écriture : relancez avec --yes pour appliquer.')
    return
  }
  await client.commit(planOrganizationWrites(seed, existing, client.docName))
  console.log('Seed de l\'organisme terminé. Rattachez un compte avec : npm --prefix scripts/seed run seed:org-member -- --email <courriel>')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error)
    process.exitCode = 1
  })
}
