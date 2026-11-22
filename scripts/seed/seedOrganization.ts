// Seed du portail Organismes (T-194, T-208) : l'organisme de démo (banque alimentaire de Côte-des-Neiges) et quatre
// autres organismes montréalais, leurs dons, leurs parrainages, leur fiche publique (carte des organismes), leur
// photo de profil et leur bannière, et le fonds de solidarité des groupes financés. Ne supprime rien. Idempotent.
// DRY-RUN PAR DÉFAUT : rien n'est écrit sans --yes.
//
//   Émulateur (défaut) : npm --prefix scripts/seed run seed:org -- --project demo-grenier [--yes]
//   Projet réel        : npm --prefix scripts/seed run seed:org -- --target cloud          (dry-run)
//                        npm --prefix scripts/seed run seed:org -- --target cloud --yes    (écrit)
//
// Les groupes de démo (fixtures/groups.json) doivent exister : lancez d'abord `seed:firestore` (ou seedDemo). Pour rattacher un compte à l'organisme : `seed:org-member` (seedOrgMember.ts).
import { readFile } from 'node:fs/promises'
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'
import { connect } from './firestoreRest.ts'
import {
  buildOrganizationSeed, describeSeed, planOrganizationMediaWrites, planOrganizationWrites, type GroupInfo
} from './organizations.ts'

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
  const existing = { organizations: new Set<string>(), funds: new Set<string>() }
  for (const organization of seed.organizations) {
    if (await client.getFields(`organizations/${organization.id}`)) existing.organizations.add(organization.id)
  }
  for (const fund of seed.funds) {
    if (await client.getFields(fund.path)) existing.funds.add(fund.groupId)
  }
  console.log(`Organismes déjà présents (profil mis à jour, membres conservés) : ${[...existing.organizations].join(', ') || 'aucun'} ; ` +
    `fonds déjà présents (lignes manquantes ajoutées) : ${[...existing.funds].join(', ') || 'aucun'}`)
  // Images lues avant toute écriture : une image manquante ou trop lourde arrête le seed (dry-run compris).
  const mediaDir = new URL('./media/', import.meta.url)
  const files = new Map<string, Buffer>()
  for (const media of seed.organizations.flatMap(({ media }) => media)) {
    files.set(media.file, await readFile(new URL(media.file, mediaDir)))
  }
  const mediaWrites = planOrganizationMediaWrites(seed, (file) => files.get(file)!, client.docName)
  console.log(`Images : ${mediaWrites.length} (photo de profil + bannière par organisme)`)

  if (!values.yes) {
    console.log('[dry-run] Aucune écriture : relancez avec --yes pour appliquer.')
    return
  }
  await client.commit(planOrganizationWrites(seed, existing, client.docName))
  // Un commit REST est limité à 10 Mio : petits lots d'images (300 Kio au plus chacune, ~400 Kio en base64).
  for (let start = 0; start < mediaWrites.length; start += 8) await client.commit(mediaWrites.slice(start, start + 8))
  console.log('Seed des organismes terminé. Rattachez un compte avec : npm --prefix scripts/seed run seed:org-member -- --email <courriel>')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error)
    process.exitCode = 1
  })
}
