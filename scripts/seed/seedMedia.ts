// T-205 : met une vraie image partout où l'app affichait un placeholder, sans rien réinitialiser.
// Images libres (Wikimedia Commons, crédits dans media/CREDITS.md) déjà recadrées et compressées dans media/ :
//   groups/<quartier>-photo.jpg (400×400) et -banner.jpg (1200×450)  → groups/{id}/media/{photo|banner} + photoUpdatedAt/bannerUpdatedAt
//   vendors/<nom>.jpg (1000×750)                                      → vendors/{id}/media/photo-seed + photoURLs
//   families/family-NN.jpg (400×400)                                  → households/{id}/media/photo
//   organizations/food-bank.jpg (400×400)                             → organizations/{id}/media/logo
// N'écrit que ce qui manque (une image déjà envoyée par quelqu'un reste) ; --force remplace aussi les images du seed.
// Dry-run par défaut : rien n'est écrit sans --yes.
//   Émulateur (défaut) : npm --prefix scripts/seed run seed:media [-- --yes]
//   Projet réel        : npm --prefix scripts/seed run seed:media -- --target cloud          (dry-run)
//                        npm --prefix scripts/seed run seed:media -- --target cloud --yes    (écrit)
import { readFile } from 'node:fs/promises'
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'
import { connect, type RestFields, type RestWrite } from './firestoreRest.ts'

export type ImageRef = { file: string, width: number, height: number }
export type Inventory = {
  groups: { id: string, neighborhood: string, hasPhoto: boolean, hasBanner: boolean }[]
  vendors: { id: string, kind: string, photoURLs: string[] }[]
  households: { id: string, hasPhoto: boolean }[]
  organizations: { id: string, hasLogo: boolean }[]
}
/** Une image à écrire, et le champ du document parent qui la signale à l'app. */
export type MediaWrite = {
  path: string
  image: ImageRef
  parent?: { path: string, field: 'photoUpdatedAt' | 'bannerUpdatedAt' | 'photoURLs' }
}

export const SEED_VENDOR_PHOTO_ID = 'photo-seed'
export const FAMILY_IMAGE_COUNT = 8
const square = (file: string): ImageRef => ({ file, width: 400, height: 400 })
const banner = (file: string): ImageRef => ({ file, width: 1_200, height: 450 })
const showcase = (file: string): ImageRef => ({ file, width: 1_000, height: 750 })

export const GROUP_NEIGHBORHOODS = [
  'ahuntsic', 'centre-sud', 'cote-des-neiges', 'hochelaga', 'mile-end', 'montreal-nord', 'notre-dame-de-grace',
  'parc-extension', 'petite-patrie', 'plateau-mont-royal', 'pointe-saint-charles', 'rosemont', 'saint-henri',
  'saint-michel', 'verdun', 'villeray'
]

/** Photo de vitrine d'un vendeur : par id connu, sinon selon son type. */
export function vendorImage(id: string, kind: string): ImageRef {
  const known = id.replace(/^vendor-/, '')
  const byId = ['boucherie-cantons', 'coop-ile-orleans', 'coop-lanaudiere', 'ferme-bio-rive', 'ferme-lafleur',
    'ferme-trois-collines', 'fournil-terrebonne', 'marche-central', 'moulin-chaudiere', 'moulins-du-nord',
    'savonnerie-laurentides']
  if (byId.includes(known)) return showcase(`vendors/${known}.jpg`)
  const byKind: Record<string, string> = {
    bakery: 'fournil-terrebonne', cooperative: 'coop-ile-orleans', wholesaler: 'marche-central'
  }
  return showcase(`vendors/${byKind[kind] ?? (hash(id) % 2 === 0 ? 'farm-a' : 'farm-b')}.jpg`)
}

/** Image d'une famille, stable d'un lancement à l'autre (même ménage → même image). */
export function familyImage(householdId: string): ImageRef {
  return square(`families/family-${String(hash(householdId) % FAMILY_IMAGE_COUNT + 1).padStart(2, '0')}.jpg`)
}

function hash(text: string): number {
  let value = 0
  for (const char of text) value = (value * 31 + char.codePointAt(0)!) >>> 0
  return value
}

/** Une vraie image de vitrine : un média Firestore ou une URL http(s) (pas un fichier d'un simulateur). */
function isRealVendorPhoto(url: string): boolean {
  return /^(grenier-media|https?):/.test(url)
}

export function planMediaWrites(inventory: Inventory, options: { force?: boolean, availableGroups?: Set<string> } = {}): MediaWrite[] {
  const writes: MediaWrite[] = []
  const available = options.availableGroups ?? new Set(GROUP_NEIGHBORHOODS)
  for (const group of inventory.groups) {
    if (!available.has(group.neighborhood)) continue
    if (!group.hasPhoto || options.force) {
      writes.push({ path: `groups/${group.id}/media/photo`, image: square(`groups/${group.neighborhood}-photo.jpg`),
        parent: { path: `groups/${group.id}`, field: 'photoUpdatedAt' } })
    }
    if (!group.hasBanner || options.force) {
      writes.push({ path: `groups/${group.id}/media/banner`, image: banner(`groups/${group.neighborhood}-banner.jpg`),
        parent: { path: `groups/${group.id}`, field: 'bannerUpdatedAt' } })
    }
  }
  for (const vendor of inventory.vendors) {
    const real = vendor.photoURLs.filter(isRealVendorPhoto)
    const onlySeed = real.length > 0 && real.every((url) => url.includes(`/media/${SEED_VENDOR_PHOTO_ID}?`))
    if (real.length > 0 && !(options.force && onlySeed)) continue
    writes.push({ path: `vendors/${vendor.id}/media/${SEED_VENDOR_PHOTO_ID}`, image: vendorImage(vendor.id, vendor.kind),
      parent: { path: `vendors/${vendor.id}`, field: 'photoURLs' } })
  }
  for (const household of inventory.households) {
    if (household.hasPhoto && !options.force) continue
    writes.push({ path: `households/${household.id}/media/photo`, image: familyImage(household.id) })
  }
  for (const organization of inventory.organizations) {
    if (organization.hasLogo && !options.force) continue
    writes.push({ path: `organizations/${organization.id}/media/logo`, image: square('organizations/food-bank.jpg') })
  }
  return writes
}

function restWrites(docName: (path: string) => string, write: MediaWrite, data: Buffer, now: Date): RestWrite[] {
  const fields: RestFields = {
    data: { bytesValue: data.toString('base64') },
    contentType: { stringValue: 'image/jpeg' },
    width: { integerValue: String(write.image.width) },
    height: { integerValue: String(write.image.height) },
    updatedAt: { timestampValue: now.toISOString() }
  }
  const out: RestWrite[] = [{ update: { name: docName(write.path), fields } }]
  if (write.parent?.field === 'photoURLs') {
    const url = `grenier-media:///${write.path}?v=${now.getTime()}`
    out.push({ update: { name: docName(write.parent.path), fields: { photoURLs: { arrayValue: { values: [{ stringValue: url }] } } } },
      updateMask: { fieldPaths: ['photoURLs'] }, currentDocument: { exists: true } })
  } else if (write.parent) {
    out.push({ update: { name: docName(write.parent.path), fields: { [write.parent.field]: { timestampValue: now.toISOString() } } },
      updateMask: { fieldPaths: [write.parent.field] }, currentDocument: { exists: true } })
  }
  return out
}

async function main() {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string', default: 'amc-2026-8ab03' },
      yes: { type: 'boolean', default: false },
      force: { type: 'boolean', default: false }
    }
  })
  const client = connect(values.target, values.project)
  console.log(`Cible : ${client.label}`)
  const mediaDir = new URL('./media/', import.meta.url)
  const exists = async (path: string) => (await client.getFields(path)) !== null

  const groups = await client.listDocuments('groups', ['neighborhood', 'photoUpdatedAt', 'bannerUpdatedAt'])
  const vendors = await client.listDocuments('vendors', ['kind', 'photoURLs'])
  const households = await client.listDocuments('households', ['name'])
  const organizations = await client.listDocuments('organizations', ['name'])
  const inventory: Inventory = {
    groups: groups.map(({ id, fields }) => ({
      id, neighborhood: fields.neighborhood?.stringValue as string ?? '',
      hasPhoto: 'photoUpdatedAt' in fields && !('nullValue' in fields.photoUpdatedAt),
      hasBanner: 'bannerUpdatedAt' in fields && !('nullValue' in fields.bannerUpdatedAt)
    })),
    vendors: vendors.map(({ id, fields }) => ({
      id, kind: fields.kind?.stringValue as string ?? 'other',
      photoURLs: ((fields.photoURLs?.arrayValue as { values?: { stringValue?: string }[] } | undefined)?.values ?? [])
        .map((value) => value.stringValue ?? '')
    })),
    households: await Promise.all(households.map(async ({ id }) => ({ id, hasPhoto: await exists(`households/${id}/media/photo`) }))),
    organizations: await Promise.all(organizations.map(async ({ id }) => ({ id, hasLogo: await exists(`organizations/${id}/media/logo`) })))
  }
  const files = new Set<string>()
  for (const name of GROUP_NEIGHBORHOODS) {
    try { await readFile(new URL(`groups/${name}-photo.jpg`, mediaDir)); files.add(name) } catch { /* pas d'image pour ce quartier */ }
  }
  const writes = planMediaWrites(inventory, { force: values.force, availableGroups: files })
  const count = (prefix: string) => writes.filter((write) => write.path.startsWith(prefix)).length
  console.log(`Images à écrire : ${count('groups/')} de groupe, ${count('vendors/')} de vendeur, ` +
    `${count('households/')} de famille, ${count('organizations/')} d'organisme.`)
  const missing = inventory.groups.filter((group) => !files.has(group.neighborhood)).map((group) => group.id)
  if (missing.length > 0) console.log(`Sans image de quartier (laissés tels quels) : ${missing.join(', ')}`)
  if (!values.yes) {
    console.log('[dry-run] Aucune écriture : relancez avec --yes pour appliquer.')
    return
  }
  const now = new Date()
  const cache = new Map<string, Buffer>()
  const batch: RestWrite[] = []
  for (const write of writes) {
    if (!cache.has(write.image.file)) cache.set(write.image.file, await readFile(new URL(write.image.file, mediaDir)))
    batch.push(...restWrites(client.docName, write, cache.get(write.image.file)!, now))
  }
  // Un commit REST est limité à 10 Mio : petits lots (les images font jusqu'à 300 Kio, ~400 Kio en base64).
  for (let start = 0; start < batch.length; start += 16) await client.commit(batch.slice(start, start + 16))
  console.log(`Écrit : ${writes.length} images.`)
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main()
}
