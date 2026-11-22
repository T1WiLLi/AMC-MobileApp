// T-197 : alimente `boroughStats/{boroughId}` (classement solidaire des arrondissements, RQ-093 / T-114) à partir
// des vraies données. Seul ce script (jeton propriétaire de l'émulateur ou session `firebase login`) écrit dans la collection :
// firestore.rules refuse toute écriture client.
//
// Sources (lecture seule, rien d'autre n'est modifié) :
//   groups/{g}.neighborhood                     → arrondissement du groupe (catalogue BOROUGHS ci-dessous)
//   groups/{g}/members/{h}                      → ménages inscrits (ménages distincts de l'arrondissement)
//   groupOrders/{o} (closed ou delivered)       → commandes fermées du groupe
//   groupOrders/{o}/shares/{h}                  → parts : quantité, prix final figé, panier suspendu, subvention
//   offers/{x}.productId, products/{p}.referenceGroceryPriceCents → prix d'épicerie de référence d'une part
//
// Mesures (mêmes règles que SavingsCalculator côté app) :
//   households        ménages distincts membres d'un groupe de l'arrondissement
//   activeHouseholds  ménages membres qui ont pris au moins une part (quantité > 0, prix final figé) d'une commande fermée
//   groupCount        groupes de l'arrondissement qui ont au moins un ménage
//   savingsCents      Σ max(0, prix de référence − prix unitaire final) × quantité
//   basketsOffered    paniers suspendus : Σ (montant suspendu ÷ prix unitaire final), arrondi à l'entier inférieur
//   familiesHelped    ménages distincts qui ont reçu une subvention (`subsidyCents` > 0) sur une part fermée
//
// Vie privée : le document ne porte que des totaux (aucun identifiant de groupe, de ménage ou d'utilisateur).
// K-anonymat : un arrondissement de moins de MIN_HOUSEHOLDS ménages (3) n'est pas publié (et son ancien document
// est supprimé), pour qu'un total ne désigne jamais une ou deux familles.
//
// Idempotent : chaque exécution réécrit l'agrégat complet (remplacement du document, `updatedAt` = maintenant).
// Dry-run par défaut : rien n'est écrit sans --yes.
//
//   Émulateur (défaut) : npm --prefix scripts/seed run aggregate:boroughs [-- --yes]
//   Projet réel        : npm --prefix scripts/seed run aggregate:boroughs -- --target cloud          (dry-run)
//                        npm --prefix scripts/seed run aggregate:boroughs -- --target cloud --yes    (écrit)
//
// Cloud : session de `firebase login` (jeton OAuth de la CLI Firebase), jamais de clé de service. Passe par l'API REST
// de Firestore (émulateur compris), comme backfillMemberUserId.ts.
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'

/** Seuil de k-anonymat : un arrondissement doit avoir au moins ce nombre de ménages pour être publié. */
export const MIN_HOUSEHOLDS = 3

export type Borough = { id: string, name: string, shortName: string, neighborhoods: string[], centerGeohash: string }

/** Les 19 arrondissements de Montréal ; `neighborhoods` = valeurs de `groups.neighborhood` rattachées (casse et accents ignorés). */
export const BOROUGHS: Borough[] = [
  { id: 'ahuntsic-cartierville', name: 'Ahuntsic-Cartierville', shortName: 'Ahuntsic', neighborhoods: ['Ahuntsic', 'Cartierville'], centerGeohash: 'f25e5t' },
  { id: 'anjou', name: 'Anjou', shortName: 'Anjou', neighborhoods: ['Anjou'], centerGeohash: 'f25eqq' },
  { id: 'cote-des-neiges-notre-dame-de-grace', name: 'Côte-des-Neiges–Notre-Dame-de-Grâce', shortName: 'CDN–NDG', neighborhoods: ['Côte-des-Neiges', 'Notre-Dame-de-Grâce'], centerGeohash: 'f25dsx' },
  { id: 'lachine', name: 'Lachine', shortName: 'Lachine', neighborhoods: ['Lachine'], centerGeohash: 'f25de2' },
  { id: 'lasalle', name: 'LaSalle', shortName: 'LaSalle', neighborhoods: ['LaSalle'], centerGeohash: 'f25dkq' },
  { id: 'le-plateau-mont-royal', name: 'Le Plateau-Mont-Royal', shortName: 'Plateau', neighborhoods: ['Plateau', 'Plateau-Mont-Royal', 'Mile End'], centerGeohash: 'f25dvx' },
  { id: 'le-sud-ouest', name: 'Le Sud-Ouest', shortName: 'Sud-Ouest', neighborhoods: ['Saint-Henri', 'Pointe-Saint-Charles', 'Petite-Bourgogne'], centerGeohash: 'f25dtw' },
  { id: 'l-ile-bizard-sainte-genevieve', name: 'L’Île-Bizard–Sainte-Geneviève', shortName: 'Île-Bizard', neighborhoods: ['Île-Bizard', 'Sainte-Geneviève'], centerGeohash: 'f256y6' },
  { id: 'mercier-hochelaga-maisonneuve', name: 'Mercier–Hochelaga-Maisonneuve', shortName: 'Hochelaga', neighborhoods: ['Hochelaga', 'Maisonneuve', 'Mercier'], centerGeohash: 'f25eq8' },
  { id: 'montreal-nord', name: 'Montréal-Nord', shortName: 'Montréal-Nord', neighborhoods: ['Montréal-Nord'], centerGeohash: 'f25ekk' },
  { id: 'outremont', name: 'Outremont', shortName: 'Outremont', neighborhoods: ['Outremont'], centerGeohash: 'f25duy' },
  { id: 'pierrefonds-roxboro', name: 'Pierrefonds-Roxboro', shortName: 'Pierrefonds', neighborhoods: ['Pierrefonds', 'Roxboro'], centerGeohash: 'f25db1' },
  { id: 'riviere-des-prairies-pointe-aux-trembles', name: 'Rivière-des-Prairies–Pointe-aux-Trembles', shortName: 'RDP–PAT', neighborhoods: ['Rivière-des-Prairies', 'Pointe-aux-Trembles'], centerGeohash: 'f25evc' },
  { id: 'rosemont-la-petite-patrie', name: 'Rosemont–La Petite-Patrie', shortName: 'Rosemont', neighborhoods: ['Rosemont', 'La Petite-Patrie', 'Petite-Patrie'], centerGeohash: 'f25ejs' },
  { id: 'saint-laurent', name: 'Saint-Laurent', shortName: 'Saint-Laurent', neighborhoods: ['Saint-Laurent'], centerGeohash: 'f25dgj' },
  { id: 'saint-leonard', name: 'Saint-Léonard', shortName: 'Saint-Léonard', neighborhoods: ['Saint-Léonard'], centerGeohash: 'f25em4' },
  { id: 'verdun', name: 'Verdun', shortName: 'Verdun', neighborhoods: ['Verdun', 'Île-des-Sœurs'], centerGeohash: 'f25dtf' },
  { id: 'ville-marie', name: 'Ville-Marie', shortName: 'Ville-Marie', neighborhoods: ['Centre-Sud', 'Centre-ville', 'Vieux-Montréal'], centerGeohash: 'f25dvg' },
  { id: 'villeray-saint-michel-parc-extension', name: 'Villeray–Saint-Michel–Parc-Extension', shortName: 'Saint-Michel', neighborhoods: ['Villeray', 'Saint-Michel', 'Parc-Extension'], centerGeohash: 'f25eht' }
]

export type Group = { id: string, neighborhood: string }
export type Member = { groupId: string, householdId: string }
export type Order = { id: string, groupId: string, offerId: string, status: string }
export type Share = { orderId: string, householdId: string, quantity: number, finalPriceCents: number | null, suspendedAmountCents: number, subsidyCents: number }
export type Input = {
  groups: Group[]
  members: Member[]
  orders: Order[]
  shares: Share[]
  /** Prix d'épicerie de référence d'une part (cents), par id de lot. Absent = économies non calculables. */
  referencePriceByOffer: Map<string, number>
}

/** Document écrit dans `boroughStats/{id}` : uniquement des totaux. */
export type BoroughDoc = Borough & {
  households: number
  activeHouseholds: number
  groupCount: number
  basketsOffered: number
  familiesHelped: number
  savingsCents: number
  updatedAt: Date
}
export type Excluded = { id: string, reason: 'sous-seuil' | 'aucun-menage', households: number }
export type Result = { docs: BoroughDoc[], excluded: Excluded[], unmatchedNeighborhoods: string[], ignoredShares: number }

/** Même normalisation que `SolidarityLeaderboard.normalizedName` : minuscules, sans accents, mots reliés par « - ». */
export function normalizeName(name: string): string {
  return name.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean).join('-')
}

const boroughByName = new Map<string, Borough>(BOROUGHS.flatMap((borough) =>
  [borough.id, borough.name, borough.shortName, ...borough.neighborhoods].map((name) => [normalizeName(name), borough] as const)))

/** Arrondissement d'un quartier de groupe, null si inconnu. */
export function boroughOf(neighborhood: string): Borough | null {
  return boroughByName.get(normalizeName(neighborhood)) ?? null
}

const isCents = (value: number | null): value is number => value !== null && Number.isFinite(value) && value >= 0

/** Calcul pur (testé) : agrégats par arrondissement, sans aucune donnée personnelle dans la sortie. */
export function computeBoroughStats(input: Input, now: Date, minHouseholds = MIN_HOUSEHOLDS): Result {
  const boroughOfGroup = new Map<string, string>()
  const unmatched = new Set<string>()
  for (const group of input.groups) {
    const borough = boroughOf(group.neighborhood)
    if (borough) boroughOfGroup.set(group.id, borough.id)
    else if (group.neighborhood.trim()) unmatched.add(group.neighborhood.trim())
  }

  type Acc = { households: Set<string>, groups: Set<string>, active: Set<string>, helped: Set<string>, savings: number, baskets: number }
  const acc = new Map<string, Acc>(BOROUGHS.map((borough) =>
    [borough.id, { households: new Set(), groups: new Set(), active: new Set(), helped: new Set(), savings: 0, baskets: 0 }]))

  for (const member of input.members) {
    const id = boroughOfGroup.get(member.groupId)
    if (!id) continue
    const a = acc.get(id)!
    a.households.add(member.householdId)
    a.groups.add(member.groupId)
  }

  const closedOrders = new Map(input.orders.filter((order) => order.status === 'closed' || order.status === 'delivered').map((order) => [order.id, order]))
  let ignoredShares = 0
  for (const share of input.shares) {
    const order = closedOrders.get(share.orderId)
    const boroughId = order ? boroughOfGroup.get(order.groupId) : undefined
    const quantity = Math.trunc(share.quantity)
    if (!order || !boroughId || quantity <= 0 || !isCents(share.finalPriceCents)) { ignoredShares += 1; continue }
    const a = acc.get(boroughId)!
    // Un ménage qui n'est plus membre d'un groupe de l'arrondissement ne compte pas dans les participants.
    if (a.households.has(share.householdId)) a.active.add(share.householdId)
    const unitPrice = Math.trunc(share.finalPriceCents / quantity)
    const reference = input.referencePriceByOffer.get(order.offerId)
    if (reference !== undefined && Number.isFinite(reference)) a.savings += Math.max(0, reference - unitPrice) * quantity
    if (share.suspendedAmountCents > 0 && unitPrice > 0) a.baskets += share.suspendedAmountCents / unitPrice
    if (share.subsidyCents > 0 && a.households.has(share.householdId)) a.helped.add(share.householdId)
  }

  const result: Result = { docs: [], excluded: [], unmatchedNeighborhoods: [...unmatched].sort(), ignoredShares }
  for (const borough of BOROUGHS) {
    const a = acc.get(borough.id)!
    if (a.households.size === 0) { result.excluded.push({ id: borough.id, reason: 'aucun-menage', households: 0 }); continue }
    if (a.households.size < minHouseholds) { result.excluded.push({ id: borough.id, reason: 'sous-seuil', households: a.households.size }); continue }
    result.docs.push({
      ...borough,
      households: a.households.size,
      activeHouseholds: a.active.size,
      groupCount: a.groups.size,
      basketsOffered: Math.floor(a.baskets + 1e-9),
      familiesHelped: a.helped.size,
      savingsCents: a.savings,
      updatedAt: now
    })
  }
  return result
}

/** Résumé lisible : une ligne par arrondissement publié, puis ceux qui ne le sont pas. */
export function summarize(result: Result, written: boolean): string {
  const lines = [`${written ? 'Écrits' : '[dry-run] À écrire'} : ${result.docs.length} arrondissement(s)`]
  for (const doc of result.docs) {
    lines.push(`  - ${doc.id} : ${doc.households} ménages (${doc.activeHouseholds} actifs), ${doc.groupCount} groupes, `
      + `${doc.basketsOffered} paniers, ${doc.familiesHelped} familles aidées, ${(doc.savingsCents / 100).toFixed(2)} $ d'économies`)
  }
  const small = result.excluded.filter(({ reason }) => reason === 'sous-seuil')
  if (small.length) {
    lines.push(`Non publiés (moins de ${MIN_HOUSEHOLDS} ménages, ancien document supprimé) : ${small.length}`)
    for (const item of small) lines.push(`  - ${item.id} : ${item.households} ménage(s)`)
  }
  lines.push(`Arrondissements sans ménage : ${result.excluded.filter(({ reason }) => reason === 'aucun-menage').length}`)
  if (result.unmatchedNeighborhoods.length) lines.push(`Quartiers de groupes sans arrondissement connu (ignorés) : ${result.unmatchedNeighborhoods.join(', ')}`)
  lines.push(`Parts ignorées (commande non fermée, groupe inconnu, prix non figé) : ${result.ignoredShares}`)
  return lines.join('\n')
}

// MARK: - API REST Firestore

type Value = { stringValue?: string, integerValue?: string, doubleValue?: number, nullValue?: null }
type Fields = Record<string, Value>
type Token = () => Promise<string>
type Row = { path: string, fields: Fields }

const str = (fields: Fields, key: string) => fields[key]?.stringValue ?? ''
function num(fields: Fields, key: string): number | null {
  const value = fields[key]
  if (value?.integerValue !== undefined) return Number(value.integerValue)
  if (value?.doubleValue !== undefined) return value.doubleValue
  return null
}

function api(base: string, projectId: string, token: Token) {
  const database = `projects/${projectId}/databases/(default)`
  const root = `${database}/documents/`
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
  /** Tous les documents d'une collection (ou d'un groupe de collections), par pages de 300. */
  async function listAll(collectionId: string, allDescendants: boolean): Promise<Row[]> {
    const rows: Row[] = []
    for (let offset = 0; ; offset += 300) {
      const page = await call(`${database}/documents:runQuery`, {
        structuredQuery: { from: [{ collectionId, allDescendants }], orderBy: [{ field: { fieldPath: '__name__' } }], offset, limit: 300 }
      }) as { document?: { name: string, fields?: Fields } }[]
      const documents = page.flatMap((row) => (row.document ? [row.document] : []))
      for (const { name, fields } of documents) rows.push({ path: name.slice(root.length), fields: fields ?? {} })
      if (documents.length < 300) return rows
    }
  }
  async function batchGet(collection: string, ids: string[]): Promise<Map<string, Fields>> {
    const found = new Map<string, Fields>()
    for (let start = 0; start < ids.length; start += 100) {
      const rows = await call(`${database}/documents:batchGet`, {
        documents: ids.slice(start, start + 100).map((id) => `${root}${collection}/${id}`)
      }) as { found?: { name: string, fields?: Fields } }[]
      for (const { found: document } of rows) {
        if (document) found.set(document.name.slice(document.name.lastIndexOf('/') + 1), document.fields ?? {})
      }
    }
    return found
  }
  return {
    async read(): Promise<Input> {
      const groups = (await listAll('groups', false)).map(({ path, fields }): Group => ({ id: path.split('/')[1], neighborhood: str(fields, 'neighborhood') }))
      const members = (await listAll('members', true)).flatMap(({ path }) => {
        const parts = path.split('/')
        // groups/{g}/members/{h} seulement (pas d'autre sous-collection « members »).
        return parts.length === 4 && parts[0] === 'groups' ? [{ groupId: parts[1], householdId: parts[3] }] : []
      })
      const orders = (await listAll('groupOrders', false)).map(({ path, fields }): Order =>
        ({ id: path.split('/')[1], groupId: str(fields, 'groupId'), offerId: str(fields, 'offerId'), status: str(fields, 'status') }))
      const closed = new Set(orders.filter(({ status }) => status === 'closed' || status === 'delivered').map(({ id }) => id))
      const shares = (await listAll('shares', true)).flatMap(({ path, fields }) => {
        const parts = path.split('/')
        if (parts.length !== 4 || parts[0] !== 'groupOrders' || !closed.has(parts[1])) return []
        return [{
          orderId: parts[1], householdId: parts[3], quantity: num(fields, 'quantity') ?? 0, finalPriceCents: num(fields, 'finalPriceCents'),
          suspendedAmountCents: num(fields, 'suspendedAmountCents') ?? 0, subsidyCents: num(fields, 'subsidyCents') ?? 0
        } satisfies Share]
      })
      const offerIds = [...new Set(orders.filter(({ id }) => closed.has(id)).map(({ offerId }) => offerId).filter(Boolean))]
      const offers = await batchGet('offers', offerIds)
      const products = await batchGet('products', [...new Set([...offers.values()].map((fields) => str(fields, 'productId')).filter(Boolean))])
      const referencePriceByOffer = new Map<string, number>()
      for (const [offerId, fields] of offers) {
        const price = num(products.get(str(fields, 'productId')) ?? {}, 'referenceGroceryPriceCents')
        if (price !== null) referencePriceByOffer.set(offerId, price)
      }
      return { groups, members, orders, shares, referencePriceByOffer }
    },
    /** Remplace chaque document publié (champs complets, sans masque) et supprime ceux qui ne le sont plus. */
    async write(result: Result) {
      const boroughs = `${root}boroughStats/`
      const writes: unknown[] = [
        ...result.docs.map((doc) => ({
          update: {
            name: `${boroughs}${doc.id}`,
            fields: {
              id: { stringValue: doc.id },
              name: { stringValue: doc.name },
              shortName: { stringValue: doc.shortName },
              neighborhoods: { arrayValue: { values: doc.neighborhoods.map((stringValue) => ({ stringValue })) } },
              centerGeohash: { stringValue: doc.centerGeohash },
              households: { integerValue: String(doc.households) },
              activeHouseholds: { integerValue: String(doc.activeHouseholds) },
              groupCount: { integerValue: String(doc.groupCount) },
              basketsOffered: { integerValue: String(doc.basketsOffered) },
              familiesHelped: { integerValue: String(doc.familiesHelped) },
              savingsCents: { integerValue: String(doc.savingsCents) },
              updatedAt: { timestampValue: doc.updatedAt.toISOString() }
            }
          }
        })),
        ...result.excluded.map(({ id }) => ({ delete: `${boroughs}${id}` }))
      ]
      for (let start = 0; start < writes.length; start += 400) {
        await call(`${database}/documents:commit`, { writes: writes.slice(start, start + 400) })
      }
    }
  }
}

// Jeton OAuth de la session `firebase login` (même mécanisme que backfillMemberUserId.ts).
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

  const input = await client.read()
  console.log(`${input.groups.length} groupes, ${input.members.length} adhésions, ${input.orders.length} commandes, ${input.shares.length} parts de commandes fermées lues.`)
  const result = computeBoroughStats(input, new Date())
  if (values.yes) await client.write(result)
  console.log(summarize(result, values.yes))
  if (!values.yes) console.log('Aucune écriture : relancez avec --yes pour appliquer.')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error)
    process.exitCode = 1
  })
}
