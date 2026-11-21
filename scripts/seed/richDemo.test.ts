import assert from 'node:assert/strict'
import { test } from 'node:test'
import { Timestamp } from 'firebase-admin/firestore'
import { millisecondsPerDay, readDemoSeed } from './catalog.ts'
import { encodeGeohash, pickupQRCode, referralCode } from './richDemo.ts'

const fixtures = new URL('./fixtures/', import.meta.url)
const start = Date.UTC(2026, 10, 21)
type Doc = Record<string, any>

async function richSeed() {
  return await readDemoSeed(fixtures, start) as unknown as Record<string, Doc[]> & { documents: { path: string, data: Doc }[] }
}

const daysFromStart = (value: Timestamp) => (value.toMillis() - start) / millisecondsPerDay

test('encodes geohashes, referral codes and pickup QR codes like the app', () => {
  assert.equal(encodeGeohash(57.64911, 10.40744, 11), 'u4pruydqqvj')
  assert.equal(encodeGeohash(45.531, -73.629, 6), 'f25eh8')
  assert.equal(referralCode('CB', 42), 'ORG-CB-00420') // ReferralCodeTests.swift
  assert.match(pickupQRCode('order-x', 'household-y'), /^GRENIER:order-x:household-y:[0-9a-f]{8}$/)
  assert.notEqual(pickupQRCode('order-x', 'household-y'), pickupQRCode('order-x', 'household-z'))
})

test('the rich demo is deterministic and every document path is unique', async () => {
  const [first, second] = [await richSeed(), await richSeed()]
  assert.deepEqual(second.documents, first.documents)
  assert.equal(new Set(first.documents.map(({ path }) => path)).size, first.documents.length)
})

test('the rich demo has the expected volume', async () => {
  const seed = await richSeed()
  assert.ok(seed.vendors.length >= 10, 'vendeurs')
  assert.ok(seed.products.length >= 60, 'produits')
  assert.ok(seed.offers.filter(({ status }) => status === 'active').length >= 30, 'lots actifs')
  assert.equal(seed.groups.length, 9)
  for (const group of seed.groups) {
    // B-056 : le groupe privé de démo n'a encore aucun membre (on y entre sur invitation).
    if (group.isPublic) assert.ok(group.householdCount >= 8 && group.householdCount <= 25, group.id)
    assert.equal(seed.members.filter(({ groupId }) => groupId === group.id).length, group.householdCount)
  }
  assert.ok(seed.wishes.length >= 50, 'envies')
  assert.ok(seed.supplies.length >= 15, 'disponibilités')
  for (const vendor of seed.vendors) {
    assert.match(vendor.storefrontGeohash, /^[0-9b-hjkmnp-z]{7}$/, vendor.id)
  }
  // Chaque groupe est centré sur ses vraies coordonnées.
  for (const group of seed.groups) {
    assert.equal(encodeGeohash(group.latitude, group.longitude, 6), group.centerGeohash, group.id)
  }
})

test('zones are geohashes that the app matches against each group', async () => {
  const seed = await richSeed()
  const centers = seed.groups.map(({ centerGeohash }) => centerGeohash as string)
  const serves = (zones: string[], center: string) => zones.some((zone) => center.startsWith(zone) || zone.startsWith(center))
  for (const vendor of seed.vendors) {
    assert.ok(vendor.servedZones.every((zone: string) => zone.length === 4 && centers.some((center) => center.startsWith(zone))), vendor.id)
  }
  for (const offer of seed.offers) {
    assert.ok(offer.zones.length > 0 && offer.zones.every((zone: string) => centers.includes(zone)), offer.id)
  }
  for (const center of centers) {
    const visible = seed.offers.filter(({ status, zones, deadline }) =>
      status === 'active' && serves(zones, center) && daysFromStart(deadline) > 0)
    assert.ok(visible.length >= 15, `${center} : ${visible.length} lots`)
  }
})

test('active orders cover every tier stage, with deadlines over the next two weeks', async () => {
  const seed = await richSeed()
  const offers = new Map(seed.offers.map((offer) => [offer.id, offer]))
  const active = seed.groupOrders.filter(({ status }) => status === 'open' || status === 'reached')
  const stage = (order: Doc): string => {
    const offer = offers.get(order.offerId)!
    const tiers = offer.tiers as { minShares: number }[]
    const next = tiers.find(({ minShares }) => minShares > order.committedShares)
    if (order.committedShares < offer.minimumSharesToLaunch) return daysFromStart(offer.deadline) <= 4 ? 'atRisk' : 'belowMinimum'
    if (tiers.slice(1).some(({ minShares }) => minShares === order.committedShares)) return 'justUnlocked'
    if (!next) return 'best'
    return next.minShares - order.committedShares <= 2 ? 'closeToNext' : 'progress'
  }
  const stages = new Set<string>(active.map(stage))
  for (const expected of ['atRisk', 'justUnlocked', 'closeToNext', 'best']) {
    assert.ok(stages.has(expected), expected)
  }
  const deadlines = seed.offers.filter(({ status }) => status === 'active').map(({ deadline }) => daysFromStart(deadline))
  assert.ok(Math.min(...deadlines) >= 1 && Math.max(...deadlines) <= 14)
  assert.ok(seed.shares.some(({ suspendedAmountCents }) => suspendedAmountCents > 0), 'paniers suspendus')
})

test('past orders give history, savings and revenue', async () => {
  const seed = await richSeed()
  const offers = new Map(seed.offers.map((offer) => [offer.id, offer]))
  const past = seed.groupOrders.filter(({ status }) => ['closed', 'delivered', 'cancelled'].includes(status))
  assert.ok(past.length >= 30)
  for (const order of past) {
    const offer = offers.get(order.offerId)!
    assert.equal(offer.status, 'closed', order.id)
    assert.ok(daysFromStart(offer.deadline) < 0, order.id)
    for (const share of seed.shares.filter(({ groupOrderId }) => groupOrderId === order.id)) {
      if (order.status === 'cancelled') {
        assert.equal(share.finalPriceCents, null)
        continue
      }
      const price = offer.tiers[order.currentTierIndex].priceCents
      assert.equal(share.finalPriceCents, price * share.quantity, `${order.id}/${share.householdId}`)
      assert.ok(share.subsidyCents >= 0 && share.subsidyCents <= share.finalPriceCents)
      assert.equal(share.qrCode, pickupQRCode(order.id, share.householdId))
      assert.equal(share.isPickedUp, order.status === 'delivered')
    }
  }
  // Commandes clôturées en attente de cueillette : créneaux à venir.
  const waiting = past.filter(({ status }) => status === 'closed')
  assert.ok(waiting.length > 0 && waiting.every(({ pickupSlots }) => daysFromStart(pickupSlots[0].start) > 0))
  assert.ok(past.some(({ status }) => status === 'cancelled'))
  assert.ok(seed.shares.some(({ subsidyCents }) => subsidyCents > 0), 'subventions du fonds')
})

test('the three personas have full, coherent data', async () => {
  const seed = await richSeed()
  const orders = new Map(seed.groupOrders.map((order) => [order.id, order]))
  const offers = new Map(seed.offers.map((offer) => [offer.id, offer]))

  const aminaOrders = seed.shares.filter(({ householdId }) => householdId === 'household-amina')
    .map(({ groupOrderId }) => orders.get(groupOrderId)!)
  assert.ok(aminaOrders.filter(({ status }) => status === 'open' || status === 'reached').length >= 4, 'Amina : commandes en cours')
  assert.ok(aminaOrders.filter(({ status }) => status === 'delivered').length >= 5, 'Amina : historique')
  assert.ok(seed.shares.some(({ householdId, pickupSlotStart }) => householdId === 'household-amina' && pickupSlotStart))
  assert.ok(seed.wishes.filter(({ householdId }) => householdId === 'household-amina').length >= 3)

  const lafleur = 'vendor-ferme-lafleur'
  assert.ok(seed.products.filter(({ vendorId }) => vendorId === lafleur).length >= 8)
  assert.ok(seed.offers.filter(({ vendorId, status }) => vendorId === lafleur && status === 'active').length >= 6)
  const revenue = seed.groupOrders.filter(({ offerId, status }) =>
    offers.get(offerId)!.vendorId === lafleur && (status === 'closed' || status === 'delivered'))
  assert.ok(revenue.length >= 10, 'Ferme Lafleur : revenus')
  assert.ok(seed.supplies.some(({ vendorId }) => vendorId === lafleur))

  const jeanPoints = seed.pickupPoints.filter(({ hostUserId }) => hostUserId === 'user-jean')
  assert.equal(jeanPoints.length, 1)
  assert.ok(jeanPoints[0]!.slots.filter(({ start }: Doc) => daysFromStart(start) > 0).length >= 6)
  assert.ok(seed.groupOrders.filter(({ pickupPointId, status }) =>
    pickupPointId === jeanPoints[0]!.id && status === 'closed').length >= 1, 'Jean : cueillettes à préparer')
})

test('wishes and supplies produce Matcher pairs, some of them partial', async () => {
  const seed = await richSeed()
  const centers = new Map(seed.groups.map(({ id, centerGeohash }) => [id, centerGeohash as string]))
  const millis = (value?: Timestamp) => value?.toMillis()
  // Mêmes critères que Matcher.swift : catégorie, unité, produit, zone (préfixe), périodes.
  const lines = new Map<string, { wanted: number, available: Set<string> }>()
  const supplyById = new Map(seed.supplies.map((supply) => [supply.id, supply]))
  for (const wish of seed.wishes) {
    for (const supply of seed.supplies) {
      if (wish.category !== supply.category || wish.unit !== supply.unit) continue
      if (wish.productId && supply.productId && wish.productId !== supply.productId) continue
      if (!supply.servedZones.some((zone: string) => centers.get(wish.groupId)!.startsWith(zone))) continue
      const from = millis(wish.wantedFrom) ?? -Infinity
      const until = millis(wish.wantedUntil) ?? Infinity
      if (!(from <= millis(supply.availableTo)! && millis(supply.availableFrom)! <= until)) continue
      const key = `${wish.groupId}|${supply.vendorId}|${wish.category}|${wish.unit}`
      const line = lines.get(key) ?? { wanted: 0, available: new Set<string>() }
      line.available.add(supply.id)
      lines.set(key, line)
    }
  }
  for (const wish of seed.wishes) {
    for (const [key, line] of lines) {
      const [groupId, , category, unit] = key.split('|')
      if (wish.groupId === groupId && wish.category === category && wish.unit === unit &&
          [...line.available].some((id) => !wish.productId || !supplyById.get(id)!.productId ||
            supplyById.get(id)!.productId === wish.productId)) {
        line.wanted += wish.quantity
      }
    }
  }
  const pairs = new Set([...lines.keys()].map((key) => key.split('|').slice(0, 2).join('|')))
  assert.ok(pairs.size >= 20, `${pairs.size} paires`)
  const partial = [...lines.values()].some(({ wanted, available }) =>
    [...available].reduce((total, id) => total + supplyById.get(id)!.quantity, 0) < wanted)
  assert.ok(partial, 'au moins une ligne partielle')
})
