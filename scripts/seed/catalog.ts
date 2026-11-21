import { readFile } from 'node:fs/promises'
import { randomBytes } from 'node:crypto'
import { Timestamp } from 'firebase-admin/firestore'

type Fixture = Record<string, unknown> & { id: string }

export const millisecondsPerDay = 86_400_000
const firestoreBatchLimit = 500

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

  if (vendors.length + products.length + offers.length > firestoreBatchLimit) {
    throw new Error('Le catalogue dépasse 500 documents, la limite du lot Firestore')
  }
  return { vendors, products, offers }
}

const montrealClock = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Toronto', // fuseau de Montréal
  hourCycle: 'h23',
  year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit'
})

function montrealOffset(instant: number): number {
  const parts = Object.fromEntries(montrealClock.formatToParts(instant).map(({ type, value }) => [type, value]))
  return Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day),
    Number(parts.hour), Number(parts.minute), Number(parts.second)) - instant
}

/** Instant où il est `minutes` après minuit, heure de Montréal, à la date UTC de `day`. */
export function montrealTime(day: number, minutes: number): number {
  const wallClock = day + minutes * 60_000
  return wallClock - montrealOffset(wallClock - montrealOffset(wallClock))
}

const isDayOffset = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 && value <= 365

type Slot = { start: Timestamp, end: Timestamp }

function slot(owner: string, day: number, start: number, end: number): Slot {
  if (!(start < end)) {
    throw new Error(`${owner} : créneau invalide`)
  }
  return {
    start: Timestamp.fromMillis(montrealTime(day, start)),
    end: Timestamp.fromMillis(montrealTime(day, end))
  }
}

function clockMinutes(owner: string, value: unknown): number {
  const match = typeof value === 'string' ? /^([01][0-9]|2[0-3]):([0-5][0-9])$/.exec(value) : null
  if (!match) {
    throw new Error(`${owner} : heure invalide (HH:mm attendu)`)
  }
  return Number(match[1]) * 60 + Number(match[2])
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)
const isRecordArray = (value: unknown): value is Record<string, unknown>[] =>
  Array.isArray(value) && value.every(isRecord)
const isOptionalString = (value: unknown) => value === undefined || isString(value)
const isNullableInteger = (value: unknown) => value === null || isInteger(value)
const isBoolean = (value: unknown) => typeof value === 'boolean'

/** Personas de démo (B-029) : ils doivent exister dans users.json. */
export const personaUserIds = ['user-amina', 'user-ferme-lafleur', 'user-jean'] as const
export const demoEmailDomain = 'demo.grenier.local'

export type SeedDocument = { path: string, data: Record<string, unknown> }

/**
 * Charge toutes les fixtures et les convertit au format lu par l'app :
 * collections racines, plus `groups/{id}/members`, `households/{id}/private/profile`
 * et `groupOrders/{id}/shares`.
 */
export async function readDemoSeed(directory: URL, seedDay: number) {
  const [catalog, groupFixtures, pickupFixtures, users, householdFixtures, orderFixtures] = await Promise.all([
    readCatalog(directory, seedDay),
    readFixtures(directory, 'groups.json'),
    readFixtures(directory, 'pickupPoints.json'),
    readFixtures(directory, 'users.json'),
    readFixtures(directory, 'households.json'),
    readFixtures(directory, 'groupOrders.json')
  ])
  const vendorIds = new Set(catalog.vendors.map(({ id }) => id))
  const offerIds = new Set(catalog.offers.map(({ id }) => id))
  const groupIds = new Set(groupFixtures.map(({ id }) => id))
  const pickupIds = new Set(pickupFixtures.map(({ id }) => id))
  const userIds = new Set(users.map(({ id }) => id))
  const householdIds = new Set(householdFixtures.map(({ id }) => id))
  const isIn = (ids: Set<string>) => (value: unknown) => typeof value === 'string' && ids.has(value)
  const allIn = (ids: Set<string>) => (value: unknown) => Array.isArray(value) && value.every(isIn(ids))

  requireFields('groups', groupFixtures, {
    name: isString,
    neighborhood: isString,
    centerGeohash: isString,
    radiusMeters: isInteger,
    coordinatorIds: allIn(userIds),
    householdCount: isInteger,
    isPublic: isBoolean,
    inviteCode: isString,
    pickupPointIds: allIn(pickupIds)
  })
  requireFields('pickupPoints', pickupFixtures, {
    groupId: isIn(groupIds),
    hostUserId: isIn(userIds),
    name: isString,
    address: isString,
    capacity: isInteger,
    accessibility: isStringArray,
    slotTemplates: (value) => isRecordArray(value) && value.length > 0
  })
  requireFields('users', users, {
    displayName: isString,
    language: isString,
    roles: isStringArray,
    neighborhood: isString,
    dietaryPreferences: isStringArray,
    seniorMode: isBoolean,
    householdId: (value) => value === undefined || isIn(householdIds)(value),
    vendorId: (value) => value === undefined || isIn(vendorIds)(value)
  })
  requireFields('households', householdFixtures, {
    name: isString,
    size: isInteger,
    geohash: isString,
    userIds: allIn(userIds),
    groupId: isIn(groupIds),
    memberRole: (value) => value === 'member' || value === 'coordinator',
    private: (value) => isRecord(value) && isBoolean(value.isSubsidized) && isOptionalString(value.referralCode)
  })
  requireFields('groupOrders', orderFixtures, {
    groupId: isIn(groupIds),
    offerId: isIn(offerIds),
    status: isString,
    currentTierIndex: isNullableInteger,
    committedShares: isInteger,
    committedHouseholds: isInteger,
    pickupPointId: (value) => value === null || isIn(pickupIds)(value),
    pickupSlotsInDays: (value) => isRecordArray(value) && value.length > 0,
    shares: isRecordArray
  })
  for (const id of personaUserIds) {
    if (!userIds.has(id)) {
      throw new Error(`users.json doit contenir le persona ${id}`)
    }
  }

  const pickupPoints = pickupFixtures.map(({ slotTemplates, ...point }): Fixture & { slots: Slot[] } => ({
    ...point,
    slots: (slotTemplates as Record<string, unknown>[]).map((template) => {
      const owner = `pickupPoints/${point.id}`
      const { inDays } = template
      if (!isDayOffset(inDays)) {
        throw new Error(`${owner} : inDays invalide`)
      }
      return slot(owner, seedDay + inDays * millisecondsPerDay,
        clockMinutes(owner, template.start), clockMinutes(owner, template.end))
    })
  }))

  const joinedAt = Timestamp.fromMillis(seedDay)
  const groupOf = new Map<string, string>()
  const members: (Record<string, unknown> & { groupId: string, householdId: string })[] = []
  const householdProfiles: (Record<string, unknown> & { householdId: string })[] = []
  const households = householdFixtures.map(({ groupId, memberRole, private: profile, ...household }): Fixture => {
    groupOf.set(household.id, String(groupId))
    members.push({ groupId: String(groupId), householdId: household.id, role: memberRole, joinedAt })
    householdProfiles.push({ ...(profile as Record<string, unknown>), householdId: household.id })
    return household
  })
  for (const group of groupFixtures) {
    const count = members.filter(({ groupId }) => groupId === group.id).length
    if (count !== group.householdCount) {
      throw new Error(`groups/${group.id} : householdCount (${group.householdCount}) diffère des ${count} ménages membres`)
    }
  }

  const shares: (Record<string, unknown> & { groupOrderId: string, householdId: string })[] = []
  const groupOrders = orderFixtures.map(({ pickupSlotsInDays, shares: orderShares, ...order }): Fixture & { pickupSlots: Slot[] } => {
    const owner = `groupOrders/${order.id}`
    const seen = new Set<string>()
    for (const share of orderShares as Record<string, unknown>[]) {
      const householdId = share.householdId
      if (typeof householdId !== 'string' || groupOf.get(householdId) !== order.groupId || seen.has(householdId)) {
        throw new Error(`${owner} : part invalide pour ${String(householdId)}`)
      }
      if (!isInteger(share.quantity) || !isNullableInteger(share.finalPriceCents) || !isBoolean(share.isPaid) ||
          !isInteger(share.suspendedAmountCents) || !isInteger(share.subsidyCents) ||
          !(share.qrCode === null || isString(share.qrCode)) || !isBoolean(share.isPickedUp)) {
        throw new Error(`${owner}/shares/${householdId} : champ invalide`)
      }
      seen.add(householdId)
      shares.push({ ...share, householdId, groupOrderId: order.id })
    }
    return {
      ...order,
      pickupSlots: (pickupSlotsInDays as Record<string, unknown>[]).map((template) => {
        const { inDays, startHour, endHour } = template
        if (!isDayOffset(inDays) || !isInteger(startHour) || !isInteger(endHour) ||
            Number(startHour) < 0 || Number(endHour) > 24) {
          throw new Error(`${owner} : créneau invalide`)
        }
        return slot(owner, seedDay + inDays * millisecondsPerDay, Number(startHour) * 60, Number(endHour) * 60)
      })
    }
  })

  const roots = { ...catalog, groups: groupFixtures, pickupPoints, users, households, groupOrders }
  const documents: SeedDocument[] = [
    ...Object.entries(roots as Record<string, Fixture[]>).flatMap(([collection, records]) =>
      records.map((data) => ({ path: `${collection}/${data.id}`, data }))),
    ...members.map(({ groupId, ...data }) => ({ path: `groups/${groupId}/members/${data.householdId}`, data })),
    ...householdProfiles.map(({ householdId, ...data }) => ({ path: `households/${householdId}/private/profile`, data })),
    ...shares.map(({ groupOrderId, ...data }) => ({ path: `groupOrders/${groupOrderId}/shares/${data.householdId}`, data }))
  ]
  if (documents.length > firestoreBatchLimit) {
    throw new Error(`Le seed compte ${documents.length} documents, au-delà de la limite du lot Firestore (500)`)
  }
  return { ...roots, members, householdProfiles, shares, documents }
}

/** Comptes Auth de démo : un par utilisateur de users.json, uid = id du document. */
export function demoAccounts(users: Fixture[]) {
  return users.map(({ id, displayName }) => ({
    uid: id,
    email: `${id.replace(/^user-/, '')}@${demoEmailDomain}`,
    displayName: String(displayName)
  }))
}

/**
 * Mot de passe commun des comptes de démo : GRENIER_DEMO_PASSWORD, sinon un mot de passe aléatoire
 * à afficher une seule fois. Il n'est jamais écrit dans le dépôt.
 */
export function demoPassword(env: NodeJS.ProcessEnv = process.env) {
  const configured = env.GRENIER_DEMO_PASSWORD
  if (configured !== undefined && configured.length < 6) {
    throw new Error('GRENIER_DEMO_PASSWORD doit compter au moins 6 caractères')
  }
  return configured === undefined
    ? { password: randomBytes(12).toString('base64url'), generated: true }
    : { password: configured, generated: false }
}

export function passwordNotice(generated: boolean, password: string, scope = '') {
  return generated
    ? `Mot de passe généré pour ces comptes ${scope}: ${password}`
    : 'Mot de passe : valeur de GRENIER_DEMO_PASSWORD'
}
