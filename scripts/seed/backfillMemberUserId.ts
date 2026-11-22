// Rattrapage T-193 : écrit `userId` (uid du propriétaire du ménage) sur chaque adhésion `groups/{g}/members/{h}`
// qui n'en a pas. La passation du créateur lit l'héritier dans `members/{h}.userId` (les ménages ne sont lisibles
// que par leurs membres).
//
// Propriétaire du ménage = `households/{h}.ownerId`, sinon le premier de `userIds` (HouseholdMembership.ownerId).
// Idempotent : une adhésion qui a déjà un `userId` n'est jamais touchée. Dry-run par défaut : rien n'est écrit sans --yes.
//
//   Émulateur (défaut) : npm --prefix scripts/seed run backfill:members [-- --yes]
//   Projet réel        : npm --prefix scripts/seed run backfill:members -- --target cloud          (dry-run)
//                        npm --prefix scripts/seed run backfill:members -- --target cloud --yes    (écrit)
//
// Cloud : session de `firebase login` (jeton OAuth de la CLI Firebase), jamais de clé de service. Ce script passe
// par l'API REST de Firestore (émulateur compris), comme seedFirestore.ts en cloud.
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'

export type Member = { path: string, groupId: string, householdId: string, userId: string | null }
export type Household = { ownerId: string | null, userIds: string[] }
export type Plan = {
  updates: { path: string, userId: string }[]
  skipped: { path: string, reason: 'deja-renseigne' | 'menage-introuvable' | 'menage-sans-compte' }[]
}

/** Propriétaire d'un ménage : `ownerId`, sinon le premier compte de `userIds`. */
export function ownerOf(household: Household): string | null {
  if (household.ownerId) return household.ownerId
  return household.userIds.find((id) => id.length > 0) ?? null
}

/** Ce qu'il faut écrire (pur, testé) : seules les adhésions sans `userId` dont le ménage a un propriétaire. */
export function planBackfill(members: Member[], households: Map<string, Household>): Plan {
  const plan: Plan = { updates: [], skipped: [] }
  for (const member of members) {
    if (member.userId) { plan.skipped.push({ path: member.path, reason: 'deja-renseigne' }); continue }
    const household = households.get(member.householdId)
    if (!household) { plan.skipped.push({ path: member.path, reason: 'menage-introuvable' }); continue }
    const owner = ownerOf(household)
    if (!owner) { plan.skipped.push({ path: member.path, reason: 'menage-sans-compte' }); continue }
    plan.updates.push({ path: member.path, userId: owner })
  }
  return plan
}

type Fields = Record<string, { stringValue?: string, arrayValue?: { values?: { stringValue?: string }[] } }>
type Token = () => Promise<string>

function api(base: string, projectId: string, token: Token) {
  const database = `projects/${projectId}/databases/(default)`
  async function call(url: string, body: unknown) {
    const response = await fetch(`${base}/v1/${url}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await token()}`, 'Content-Type': 'application/json', 'x-goog-user-project': projectId },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(60_000)
    })
    if (!response.ok) throw new Error(`Firestore REST échoué (HTTP ${response.status}) : ${(await response.text()).slice(0, 500)}`)
    return response.json() as Promise<unknown>
  }
  return {
    database,
    async listMembers(): Promise<Member[]> {
      const members: Member[] = []
      for (let offset = 0; ; offset += 300) {
        const rows = await call(`${database}/documents:runQuery`, {
          structuredQuery: { from: [{ collectionId: 'members', allDescendants: true }], orderBy: [{ field: { fieldPath: '__name__' } }], offset, limit: 300 }
        }) as { document?: { name: string, fields?: Fields } }[]
        const documents = rows.flatMap((row) => (row.document ? [row.document] : []))
        for (const { name, fields } of documents) {
          const path = name.slice(`${database}/documents/`.length)
          const parts = path.split('/')
          // groups/{g}/members/{h} seulement (pas d'autre sous-collection « members »).
          if (parts.length !== 4 || parts[0] !== 'groups') continue
          members.push({ path, groupId: parts[1], householdId: parts[3], userId: fields?.userId?.stringValue || null })
        }
        if (documents.length < 300) return members
      }
    },
    async households(ids: string[]): Promise<Map<string, Household>> {
      const found = new Map<string, Household>()
      for (let start = 0; start < ids.length; start += 100) {
        const rows = await call(`${database}/documents:batchGet`, {
          documents: ids.slice(start, start + 100).map((id) => `${database}/documents/households/${id}`)
        }) as { found?: { name: string, fields?: Fields } }[]
        for (const { found: document } of rows) {
          if (!document) continue
          const id = document.name.slice(document.name.lastIndexOf('/') + 1)
          const userIds = (document.fields?.userIds?.arrayValue?.values ?? []).flatMap((value) => value.stringValue ? [value.stringValue] : [])
          found.set(id, { ownerId: document.fields?.ownerId?.stringValue || null, userIds })
        }
      }
      return found
    },
    async setUserIds(updates: Plan['updates']) {
      for (let start = 0; start < updates.length; start += 400) {
        await call(`${database}/documents:commit`, {
          writes: updates.slice(start, start + 400).map(({ path, userId }) => ({
            update: { name: `${database}/documents/${path}`, fields: { userId: { stringValue: userId } } },
            updateMask: { fieldPaths: ['userId'] },
            // Jamais de création : l'adhésion doit exister (supprimée entre-temps : l'écriture échoue, relancer).
            currentDocument: { exists: true }
          }))
        })
      }
    }
  }
}

// Jeton OAuth de la session `firebase login` (même mécanisme que seedFirestore.ts).
function firebaseCliToken(): Token {
  const configPath = join(homedir(), '.config', 'configstore', 'firebase-tools.json')
  let cached: { token: string, expiresAt: number } | null = null
  return async () => {
    if (!cached || cached.expiresAt - Date.now() < 120_000) {
      execFileSync('npx', ['-y', 'firebase-tools@latest', 'projects:list', '--json'], { stdio: 'ignore' })
      const tokens = JSON.parse(await readFile(configPath, 'utf8')).tokens ?? {}
      if (typeof tokens.access_token !== 'string') throw new Error('Pas de session Firebase : lancez `npx -y firebase-tools@latest login`.')
      cached = { token: tokens.access_token, expiresAt: Number(tokens.expires_at) || Date.now() + 1_800_000 }
    }
    return cached.token
  }
}

export function summarize(plan: Plan, written: boolean) {
  const count = (reason: Plan['skipped'][number]['reason']) => plan.skipped.filter((item) => item.reason === reason).length
  return [
    `${written ? 'Mises à jour' : '[dry-run] À mettre à jour'} : ${plan.updates.length}`,
    `Ignorées : ${plan.skipped.length}`,
    `  - userId déjà renseigné : ${count('deja-renseigne')}`,
    `  - ménage introuvable : ${count('menage-introuvable')}`,
    `  - ménage sans compte : ${count('menage-sans-compte')}`
  ].join('\n')
}

async function main() {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string', default: 'amc-2026-8ab03' },
      yes: { type: 'boolean', default: false }
    }
  })
  const projectId = values.project
  if (!/^[a-z0-9][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) throw new Error('Identifiant de projet invalide')
  if (values.target !== 'emulator' && values.target !== 'cloud') throw new Error('--target emulator|cloud')

  let client: ReturnType<typeof api>
  if (values.target === 'emulator') {
    const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080'
    if (!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(host)) throw new Error('FIRESTORE_EMULATOR_HOST doit être local')
    console.log(`Cible : émulateur ${host}, projet ${projectId}`)
    client = api(`http://${host}`, projectId, async () => 'owner')
  } else {
    console.log(`Cible : projet Firebase réel ${projectId}`)
    client = api('https://firestore.googleapis.com', projectId, firebaseCliToken())
  }

  const members = await client.listMembers()
  const missing = members.filter((member) => !member.userId)
  const households = await client.households([...new Set(missing.map((member) => member.householdId))])
  const plan = planBackfill(members, households)
  console.log(`${members.length} adhésions lues.`)
  if (values.yes) await client.setUserIds(plan.updates)
  console.log(summarize(plan, values.yes))
  if (!values.yes) console.log('Aucune écriture : relancez avec --yes pour appliquer.')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error)
    process.exitCode = 1
  })
}
