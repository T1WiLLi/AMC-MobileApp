import { readFile } from 'node:fs/promises'
import { Timestamp } from 'firebase-admin/firestore'

type Fixture = Record<string, unknown> & { id: string }

export const millisecondsPerDay = 86_400_000

async function readFixtures(directory: URL, filename: string): Promise<Fixture[]> {
  const source = new URL(filename, directory)
  let records: unknown
  try {
    records = JSON.parse(await readFile(source, 'utf8'))
  } catch (error) {
    throw new Error(`Impossible de lire ${filename}`, { cause: error })
  }
  if (!Array.isArray(records) || records.length === 0) {
    throw new Error(`${filename} doit contenir un tableau non vide`)
  }

  const ids = new Set<string>()
  return records.map((record: unknown) => {
    if (typeof record !== 'object' || !record || Array.isArray(record) ||
        !('id' in record) || typeof record.id !== 'string' ||
        !/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(record.id)) {
      throw new Error(`Identifiant de document invalide dans ${filename}`)
    }
    if (ids.has(record.id)) {
      throw new Error(`${filename} contient un identifiant en double : ${record.id}`)
    }
    ids.add(record.id)
    return { ...record, id: record.id }
  })
}

function requireFields(
  collection: string,
  records: Fixture[],
  fields: Record<string, (value: unknown) => boolean>
) {
  for (const record of records) {
    for (const [field, valid] of Object.entries(fields)) {
      if (!valid(record[field])) {
        throw new Error(`${collection}/${record.id} : champ ${field} invalide`)
      }
    }
  }
}

const isString = (value: unknown) => typeof value === 'string'
const isStringArray = (value: unknown) => Array.isArray(value) && value.every(isString)
const isInteger = (value: unknown) => Number.isSafeInteger(value)

export async function readCatalog(directory: URL, seedDay: number) {
  const [vendors, products, offerFixtures] = await Promise.all([
    readFixtures(directory, 'vendors.json'),
    readFixtures(directory, 'products.json'),
    readFixtures(directory, 'offers.json')
  ])

  requireFields('vendors', vendors, {
    legalName: isString,
    kind: isString,
    description: isString,
    photoURLs: isStringArray,
    servedZones: isStringArray,
    isVerified: (value) => typeof value === 'boolean'
  })
  const vendorIds = new Set(vendors.map(({ id }) => id))
  requireFields('products', products, {
    vendorId: (value) => typeof value === 'string' && vendorIds.has(value),
    name: isString,
    category: isString,
    unit: isString,
    origin: isString,
    tags: isStringArray,
    referenceGroceryPriceCents: isInteger
  })
  const productVendors = new Map(products.map(({ id, vendorId }) => [id, vendorId]))
  requireFields('offers', offerFixtures, {
    vendorId: (value) => typeof value === 'string' && vendorIds.has(value),
    productId: (value) => typeof value === 'string' && productVendors.has(value),
    shareUnit: isString,
    totalShares: isInteger,
    minimumSharesToLaunch: isInteger,
    zones: isStringArray,
    status: isString,
    tiers: (value) => Array.isArray(value) && value.length > 0 && value.every((tier) =>
      tier && typeof tier === 'object' && isInteger(tier.minShares) && isInteger(tier.priceCents)
    )
  })
  const offers = offerFixtures.map(({ deadlineInDays, ...offer }) => {
    if (productVendors.get(String(offer.productId)) !== offer.vendorId) {
      throw new Error(`offers/${offer.id} : le produit appartient à un autre vendeur`)
    }
    if (typeof deadlineInDays !== 'number' || !Number.isSafeInteger(deadlineInDays) ||
        deadlineInDays < 0) {
      throw new Error(`Échéance invalide dans offers.json : ${offer.id}`)
    }
    return { ...offer, deadline: Timestamp.fromMillis(seedDay + deadlineInDays * millisecondsPerDay) }
  })

  if (vendors.length + products.length + offers.length > 500) {
    throw new Error('Le catalogue dépasse 500 documents, la limite du lot Firestore')
  }
  return { vendors, products, offers }
}
