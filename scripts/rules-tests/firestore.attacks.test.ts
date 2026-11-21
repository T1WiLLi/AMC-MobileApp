// T-093 — QA adverse des règles Firestore : chaque test est une attaque (assertFails) ou le parcours
// légitime de l'app qu'un correctif ne doit pas casser (assertSucceeds).
// Les écritures « app » reproduisent FirestoreGroupOrderRepository : la part et la commande dans une même
// transaction (ici un writeBatch : les règles l'évaluent de la même façon, getAfter compris).
// Lancer depuis la racine : npm --prefix scripts/rules-tests run test:emulators
import { after, before, beforeEach, describe, test } from 'node:test'
import { readFile } from 'node:fs/promises'
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment
} from '@firebase/rules-unit-testing'
import {
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
  type Firestore
} from 'firebase/firestore'

let env: RulesTestEnvironment

const as = (uid: string) => env.authenticatedContext(uid).firestore()
const anonymous = () => env.unauthenticatedContext().firestore()

const GROUP = 'group-parc'
const OTHER_GROUP = 'group-rosemont'
const future = () => Timestamp.fromMillis(Date.now() + 86_400_000)
const past = () => Timestamp.fromMillis(Date.now() - 3_600_000)

// Paliers triés comme `Offer.sortedTiers` (8 → 7,39 $, 16 → 6,49 $, 24 → 5,59 $).
const tiers = [
  { minShares: 8, priceCents: 739 },
  { minShares: 16, priceCents: 649 },
  { minShares: 24, priceCents: 559 }
]
const offer = {
  id: 'offer-carottes', vendorId: 'vendor-lafleur', productId: 'product-carottes', totalShares: 40,
  shareUnit: 'sac de 5 kg', tiers, minimumSharesToLaunch: 8, zones: ['parc'], status: 'active'
}
const product = {
  id: 'product-carottes', vendorId: 'vendor-lafleur', name: 'Carottes', category: 'produce',
  unit: 'sac de 5 kg', origin: 'QC', tags: [], referenceGroceryPriceCents: 899
}

const familyShare = (householdId: string, quantity: number) => ({
  householdId, quantity, isPaid: false, suspendedAmountCents: 0, subsidyCents: 0, isPickedUp: false
})

const user = (id: string, householdId: string | null, extra: Record<string, unknown> = {}) => ({
  id, displayName: id, language: 'fr', roles: ['family'], neighborhood: 'parc',
  dietaryPreferences: [], seniorMode: false, householdId, ...extra
})

// Ordre ouvert de Parc : Bob a 2 parts. Ordre échu (date limite passée) : Amina 4, Bob 6 (10 parts, palier 0).
const openOrder = {
  id: 'order-open', groupId: GROUP, offerId: 'offer-carottes', status: 'open',
  committedShares: 2, committedHouseholds: 1, pickupPointId: null, pickupSlots: []
}
const dueOrder = {
  id: 'order-due', groupId: GROUP, offerId: 'offer-due', status: 'reached', currentTierIndex: 0,
  committedShares: 10, committedHouseholds: 2, pickupSlots: []
}
const lowOrder = {
  id: 'order-low', groupId: GROUP, offerId: 'offer-due', status: 'open',
  committedShares: 3, committedHouseholds: 1, pickupSlots: []
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-grenier-rules',
    firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') }
  })
})

after(async () => { await env.cleanup() })

beforeEach(async () => {
  await env.clearFirestore()
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore()
    const put = (path: string, data: Record<string, unknown>) => setDoc(doc(db, path), data)
    await put('users/amina', user('amina', 'household-amina'))
    await put('users/bob', user('bob', 'household-bob'))
    await put('users/jean', user('jean', 'household-jean'))
    await put('users/intrus', user('intrus', null))
    await put('users/rival', user('rival', 'household-rival'))
    await put('users/lafleur', user('lafleur', null, { roles: ['vendor'], vendorId: 'vendor-lafleur' }))
    await put('users/autre', user('autre', null, { roles: ['vendor'], vendorId: 'vendor-autre' }))
    for (const [id, uid] of [['household-amina', 'amina'], ['household-bob', 'bob'], ['household-jean', 'jean'], ['household-rival', 'rival']]) {
      await put(`households/${id}`, { id, name: id, size: 3, geohash: 'f25', userIds: [uid] })
      await put(`households/${id}/private/profile`, { isSubsidized: false })
    }
    await put('households/household-bob/private/profile', { isSubsidized: true, referralCode: 'ORG-PE-00035' })
    await put(`groups/${GROUP}`, { id: GROUP, name: 'Parc', isPublic: true, coordinatorIds: ['jean'] })
    await put(`groups/${OTHER_GROUP}`, { id: OTHER_GROUP, name: 'Rosemont', isPublic: true, coordinatorIds: ['rival'] })
    for (const h of ['household-amina', 'household-bob', 'household-jean']) {
      await put(`groups/${GROUP}/members/${h}`, { householdId: h, role: 'member', joinedAt: Timestamp.now() })
    }
    await put(`groups/${OTHER_GROUP}/members/household-rival`, { householdId: 'household-rival', role: 'member', joinedAt: Timestamp.now() })
    await put('vendors/vendor-lafleur', { id: 'vendor-lafleur', legalName: 'Lafleur', kind: 'farm', description: 'x', photoURLs: [], servedZones: [], isVerified: true })
    await put('vendors/vendor-autre', { id: 'vendor-autre', legalName: 'Autre', kind: 'farm', description: 'x', photoURLs: [], servedZones: [], isVerified: false })
    await put('products/product-carottes', product)
    await put('products/product-autre', { ...product, id: 'product-autre', vendorId: 'vendor-autre' })
    await put('offers/offer-carottes', { ...offer, deadline: future() })
    await put('offers/offer-due', { ...offer, id: 'offer-due', deadline: past() })
    await put('offers/offer-autre', { ...offer, id: 'offer-autre', vendorId: 'vendor-autre', productId: 'product-autre', deadline: past() })
    await put('groupOrders/order-open', openOrder)
    // Part du seed : null explicites pour le prix et le QR (le SDK Swift, lui, omet les nil).
    await put('groupOrders/order-open/shares/household-bob', { ...familyShare('household-bob', 2), finalPriceCents: null, qrCode: null })
    await put('groupOrders/order-due', dueOrder)
    await put('groupOrders/order-due/shares/household-amina', familyShare('household-amina', 4))
    await put('groupOrders/order-due/shares/household-bob', familyShare('household-bob', 6))
    await put('groupOrders/order-low', lowOrder)
    await put('groupOrders/order-low/shares/household-amina', familyShare('household-amina', 3))
    await put('pickupPoints/pickup-1', { id: 'pickup-1', hostUserId: 'jean', name: 'Église', address: '1 rue', capacity: 40, accessibility: [], slots: [] })
  })
})

/** Ce que fait `setShare` : la part (ou sa suppression) et la commande recalculée, en une écriture atomique. */
function setShareBatch(
  db: Firestore, orderId: string, householdId: string,
  share: Record<string, unknown> | null, order: Record<string, unknown>
) {
  const batch = writeBatch(db)
  const shareRef = doc(db, `groupOrders/${orderId}/shares/${householdId}`)
  if (share) batch.set(shareRef, share)
  else batch.delete(shareRef)
  batch.set(doc(db, `groupOrders/${orderId}`), order)
  return batch.commit()
}

/** Ce que fait `closeGroupOrder` : les parts avec prix, subvention, QR, puis la commande figée. */
function closeBatch(db: Firestore, orderId: string, shares: Record<string, unknown>[], order: Record<string, unknown>) {
  const batch = writeBatch(db)
  for (const share of shares) batch.set(doc(db, `groupOrders/${orderId}/shares/${share.householdId}`), share)
  batch.set(doc(db, `groupOrders/${orderId}`), order)
  return batch.commit()
}

// Swift : FNV-1a 32 bits de "orderId|householdId".
function qr(orderId: string, householdId: string) {
  let hash = 2166136261
  for (const byte of new TextEncoder().encode(`${orderId}|${householdId}`)) {
    hash ^= byte
    hash = Math.imul(hash, 16777619) >>> 0
  }
  return `GRENIER:${orderId}:${householdId}:${hash.toString(16).padStart(8, '0')}`
}

const closedShare = (householdId: string, quantity: number, unit: number, subsidyCents = 0) => ({
  ...familyShare(householdId, quantity), finalPriceCents: quantity * unit, subsidyCents, qrCode: qr('order-due', householdId)
})

describe('parcours légitimes de l’app (ne doivent pas casser)', () => {
  test('Amina réserve 3 parts : part + commande recalculée', async () => {
    await assertSucceeds(setShareBatch(as('amina'), 'order-open', 'household-amina',
      { ...familyShare('household-amina', 3), updatedAt: Timestamp.now() },
      { ...openOrder, committedShares: 5, committedHouseholds: 2 }))
  })
  test('Amina franchit le minimum et le premier palier (status reached, palier 0)', async () => {
    await assertSucceeds(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 6),
      { ...openOrder, committedShares: 8, committedHouseholds: 2, status: 'reached', currentTierIndex: 0 }))
  })
  test('Bob (part du seed avec null explicites) change sa quantité', async () => {
    const { pickupPointId, ...orderWithoutNull } = openOrder
    await assertSucceeds(setShareBatch(as('bob'), 'order-open', 'household-bob',
      { ...familyShare('household-bob', 4), updatedAt: Timestamp.now() },
      { ...orderWithoutNull, committedShares: 4 }))
  })
  test('Bob retire sa part', async () => {
    await assertSucceeds(setShareBatch(as('bob'), 'order-open', 'household-bob', null,
      { ...openOrder, committedShares: 0, committedHouseholds: 0 }))
  })
  test('Bob ajoute un panier suspendu (sans toucher à la commande)', async () => {
    await assertSucceeds(updateDoc(doc(as('bob'), 'groupOrders/order-open/shares/household-bob'), { suspendedAmountCents: 1500 }))
  })
  test('une part du seed déjà subventionnée peut encore changer de quantité', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'groupOrders/order-open/shares/household-bob'), { subsidyCents: 739 })
    })
    await assertSucceeds(setShareBatch(as('bob'), 'order-open', 'household-bob',
      { ...familyShare('household-bob', 3), subsidyCents: 739 },
      { ...openOrder, committedShares: 3 }))
  })
  test('un membre ouvre une commande vide', async () => {
    await assertSucceeds(setDoc(doc(as('amina'), 'groupOrders/order-group-parc-offer-carottes'), {
      id: 'order-group-parc-offer-carottes', groupId: GROUP, offerId: 'offer-carottes', status: 'open',
      committedShares: 0, committedHouseholds: 0, pickupSlots: []
    }))
  })
  test('le coordonnateur clôture au palier atteint, avec la subvention de Bob (subventionné)', async () => {
    await assertSucceeds(closeBatch(as('jean'), 'order-due', [
      closedShare('household-amina', 4, 739),
      closedShare('household-bob', 6, 739, 2000)
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('le vendeur du lot clôture aussi', async () => {
    await assertSucceeds(closeBatch(as('lafleur'), 'order-due', [
      closedShare('household-amina', 4, 739), closedShare('household-bob', 6, 739)
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('minimum non atteint : le coordonnateur annule', async () => {
    await assertSucceeds(setDoc(doc(as('jean'), 'groupOrders/order-low'), { ...lowOrder, status: 'cancelled' }))
  })
  test('clôture d’une grosse commande (20 ménages dont 8 subventionnés) : limite d’accès des règles', async () => {
    const n = Number(process.env.BIG_N ?? 20)
    const subsidized = Number(process.env.BIG_SUB ?? 8)
    const ids = Array.from({ length: n }, (_, i) => `household-g${String(i).padStart(2, '0')}`)
    const tierIndex = 2 * n >= 24 ? 2 : 2 * n >= 16 ? 1 : 0
    const unit = tiers[tierIndex].priceCents
    const big = { ...dueOrder, id: 'order-big', committedShares: 2 * n, committedHouseholds: n, currentTierIndex: tierIndex }
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, 'groupOrders/order-big'), big)
      for (const [i, id] of ids.entries()) {
        await setDoc(doc(db, `groupOrders/order-big/shares/${id}`), familyShare(id, 2))
        if (i < subsidized) await setDoc(doc(db, `households/${id}/private/profile`), { isSubsidized: true, referralCode: 'ORG-PE-00035' })
      }
    })
    const shares = ids.map((id, i) => ({
      ...familyShare(id, 2), finalPriceCents: 2 * unit, subsidyCents: i < subsidized ? 500 : 0, qrCode: qr('order-big', id)
    }))
    await assertSucceeds(closeBatch(as('jean'), 'order-big', shares, { ...big, status: 'closed' }))
  })
  test('forme exacte de setShare (updateData des champs qui changent) avec créneaux et réservation', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await updateDoc(doc(db, 'groupOrders/order-open'), {
        pickupPointId: 'pickup-1', pickupSlots: [{ start: Timestamp.fromMillis(Date.now() + 1234567), end: Timestamp.fromMillis(Date.now() + 9234567) }]
      })
      await updateDoc(doc(db, 'groupOrders/order-open/shares/household-bob'), { pickupSlotStart: Timestamp.fromMillis(Date.now() + 1234567) })
    })
    const db = as('bob')
    const batch = writeBatch(db)
    batch.update(doc(db, 'groupOrders/order-open/shares/household-bob'), { quantity: 9, updatedAt: Timestamp.now() })
    batch.update(doc(db, 'groupOrders/order-open'), { committedShares: 9, committedHouseholds: 1, currentTierIndex: 0, status: 'reached' })
    await assertSucceeds(batch.commit())
    const back = writeBatch(db)
    back.update(doc(db, 'groupOrders/order-open/shares/household-bob'), { quantity: 2, updatedAt: Timestamp.now() })
    back.update(doc(db, 'groupOrders/order-open'), { committedShares: 2, committedHouseholds: 1, currentTierIndex: deleteField(), status: 'open' })
    await assertSucceeds(back.commit())
  })
  test('forme exacte de closeGroupOrder (updateData)', async () => {
    const db = as('jean')
    const batch = writeBatch(db)
    for (const [h, q] of [['household-amina', 4], ['household-bob', 6]] as const) {
      batch.update(doc(db, `groupOrders/order-due/shares/${h}`), { finalPriceCents: q * 739, subsidyCents: 0, qrCode: qr('order-due', h) })
    }
    batch.update(doc(db, 'groupOrders/order-due'), { committedShares: 10, committedHouseholds: 2, currentTierIndex: 0, status: 'closed' })
    await assertSucceeds(batch.commit())
  })
  test('annulation sous le minimum, forme exacte (currentTierIndex supprimé alors qu’absent)', async () => {
    await assertSucceeds(updateDoc(doc(as('jean'), 'groupOrders/order-low'), {
      committedShares: 3, committedHouseholds: 1, currentTierIndex: deleteField(), status: 'cancelled'
    }))
  })
  test('le coordonnateur choisit un point de cueillette existant', async () => {
    await assertSucceeds(updateDoc(doc(as('jean'), 'groupOrders/order-open'), { pickupPointId: 'pickup-1', pickupSlots: [] }))
  })
  test('membre et vendeur du lot lisent les parts', async () => {
    await assertSucceeds(getDocs(collection(as('amina'), 'groupOrders/order-open/shares')))
    await assertSucceeds(getDocs(collection(as('lafleur'), 'groupOrders/order-open/shares')))
  })
})

describe('attaques : identité et ménage', () => {
  test('un étranger se déclare du ménage d’Amina puis écrit sa part', async () => {
    await updateDoc(doc(as('intrus'), 'users/intrus'), { householdId: 'household-amina' })
    await assertFails(setShareBatch(as('intrus'), 'order-open', 'household-amina',
      familyShare('household-amina', 3), { ...openOrder, committedShares: 5, committedHouseholds: 2 }))
  })
  test('un étranger qui se déclare du ménage de Bob ne lit pas les parts du groupe', async () => {
    await updateDoc(doc(as('intrus'), 'users/intrus'), { householdId: 'household-bob' })
    await assertFails(getDocs(collection(as('intrus'), 'groupOrders/order-open/shares')))
    await assertFails(getDoc(doc(as('intrus'), 'groupOrders/order-open/shares/household-bob')))
  })
  test('un étranger qui se déclare du ménage de Bob ne retire pas sa part', async () => {
    await updateDoc(doc(as('intrus'), 'users/intrus'), { householdId: 'household-bob' })
    await assertFails(setShareBatch(as('intrus'), 'order-open', 'household-bob', null,
      { ...openOrder, committedShares: 0, committedHouseholds: 0 }))
  })
  test('un étranger qui se déclare du ménage d’Amina n’ouvre pas de commande', async () => {
    await updateDoc(doc(as('intrus'), 'users/intrus'), { householdId: 'household-amina' })
    await assertFails(setDoc(doc(as('intrus'), 'groupOrders/order-x'), {
      id: 'order-x', groupId: GROUP, offerId: 'offer-carottes', status: 'open', committedShares: 0, committedHouseholds: 0, pickupSlots: []
    }))
  })
  test('un membre retiré du ménage (users.householdId périmé) perd ses droits sur la part', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'households/household-bob'), { userIds: ['autre-membre'] })
    })
    await assertFails(setShareBatch(as('bob'), 'order-open', 'household-bob',
      { ...familyShare('household-bob', 5), finalPriceCents: null, qrCode: null }, { ...openOrder, committedShares: 5 }))
  })
  test('un ménage se déclare subventionné sans code d’organisme', async () => {
    await assertFails(setDoc(doc(as('amina'), 'households/household-amina/private/profile'), { isSubsidized: true }))
    await assertFails(setDoc(doc(as('amina'), 'households/household-amina/private/profile'), { isSubsidized: true, referralCode: 'n’importe quoi' }))
  })
  test('un ménage avec un code bien formé devient subventionné (RQ-082)', async () => {
    await assertSucceeds(setDoc(doc(as('amina'), 'households/household-amina/private/profile'), { isSubsidized: true, referralCode: 'ORG-CB-04273' }))
  })
  test('un ménage n’écrit pas le profil privé d’un autre', async () => {
    await assertFails(setDoc(doc(as('amina'), 'households/household-bob/private/profile'), { isSubsidized: false }))
  })
  test('anonyme : ni commande, ni part, ni profil', async () => {
    await assertFails(getDoc(doc(anonymous(), 'groupOrders/order-open')))
    await assertFails(getDocs(collection(anonymous(), 'groupOrders/order-open/shares')))
    await assertFails(setDoc(doc(anonymous(), 'groupOrders/order-open/shares/household-amina'), familyShare('household-amina', 1)))
    await assertFails(getDoc(doc(anonymous(), 'users/amina')))
  })
})

describe('attaques : membre d’un autre groupe, étranger, vendeur', () => {
  test('membre d’un autre groupe : pas de part, pas de lecture des parts', async () => {
    await assertFails(setShareBatch(as('rival'), 'order-open', 'household-rival',
      familyShare('household-rival', 3), { ...openOrder, committedShares: 5, committedHouseholds: 2 }))
    await assertFails(getDocs(collection(as('rival'), 'groupOrders/order-open/shares')))
  })
  test('le vendeur d’un autre lot ne lit pas les parts', async () => {
    await assertFails(getDocs(collection(as('autre'), 'groupOrders/order-open/shares')))
  })
  test('un étranger ne lit aucune part', async () => {
    await assertFails(getDoc(doc(as('intrus'), 'groupOrders/order-open/shares/household-bob')))
  })
})

describe('attaques : compteurs, palier, statut', () => {
  test('changer le palier affiché sans changer de part', async () => {
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-open'), { ...openOrder, currentTierIndex: 2 }))
  })
  test('réserver en annonçant un faux palier (meilleur prix)', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 6),
      { ...openOrder, committedShares: 8, committedHouseholds: 2, status: 'reached', currentTierIndex: 2 }))
  })
  test('réserver sans mettre le palier à jour', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 6),
      { ...openOrder, committedShares: 8, committedHouseholds: 2, status: 'reached' }))
  })
  test('compteur gonflé plus que sa part', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 1), { ...openOrder, committedShares: 20, committedHouseholds: 2, status: 'reached', currentTierIndex: 1 }))
  })
  test('compteur modifié sans écrire de part', async () => {
    await assertFails(updateDoc(doc(as('amina'), 'groupOrders/order-open'), { committedShares: 3, committedHouseholds: 1 }))
  })
  test('ménages comptés deux fois', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 3), { ...openOrder, committedShares: 5, committedHouseholds: 3 }))
  })
  test('dépasser le total du lot', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 39), { ...openOrder, committedShares: 41, committedHouseholds: 2, status: 'reached', currentTierIndex: 2 }))
  })
  test('statut « reached » sous le minimum', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 1), { ...openOrder, committedShares: 3, committedHouseholds: 2, status: 'reached' }))
  })
  test('une famille clôture ou livre la commande', async () => {
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-due'), { ...dueOrder, status: 'closed' }))
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-open'), { ...openOrder, status: 'delivered' }))
  })
  test('ouvrir une commande avec un palier, des parts ou des créneaux', async () => {
    const base = { id: 'order-x', groupId: GROUP, offerId: 'offer-carottes', status: 'open', committedShares: 0, committedHouseholds: 0, pickupSlots: [] }
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-x'), { ...base, currentTierIndex: 2 }))
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-x'), { ...base, committedShares: 30 }))
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-x'), { ...base, pickupPointId: 'pickup-1' }))
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-x'), { ...base, pickupSlots: Array(20).fill({ start: 'x'.repeat(10_000) }) }))
  })
  test('ouvrir une commande sur un lot échu, pour un autre groupe', async () => {
    const base = { id: 'order-x', groupId: GROUP, offerId: 'offer-due', status: 'open', committedShares: 0, committedHouseholds: 0, pickupSlots: [] }
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-x'), base))
    await assertFails(setDoc(doc(as('amina'), 'groupOrders/order-x'), { ...base, offerId: 'offer-carottes', groupId: OTHER_GROUP }))
  })
  test('supprimer une commande, rouvrir une commande fermée', async () => {
    await assertFails(deleteDoc(doc(as('jean'), 'groupOrders/order-open')))
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'groupOrders/order-due'), { status: 'closed' })
    })
    await assertFails(setDoc(doc(as('jean'), 'groupOrders/order-due'), { ...dueOrder, status: 'reached' }))
  })
  test('changer groupId, offerId ou le point de cueillette en passant', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 1), { ...openOrder, committedShares: 3, committedHouseholds: 2, offerId: 'offer-autre' }))
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-amina',
      familyShare('household-amina', 1), { ...openOrder, committedShares: 3, committedHouseholds: 2, pickupPointId: 'pickup-1' }))
  })
})

describe('attaques : la part d’une famille', () => {
  const create = (data: Record<string, unknown>, quantity = 3) => setShareBatch(as('amina'), 'order-open', 'household-amina',
    data, { ...openOrder, committedShares: 2 + quantity, committedHouseholds: 2 })
  test('type confusion sur la quantité', async () => {
    await assertFails(create({ ...familyShare('household-amina', 3), quantity: '3' }))
    await assertFails(create({ ...familyShare('household-amina', 3), quantity: 2.5 }, 2.5))
    await assertFails(create({ ...familyShare('household-amina', 3), quantity: 0 }, 0))
    await assertFails(create({ ...familyShare('household-amina', 3), quantity: -3 }, -3))
  })
  test('prix, paiement, QR, cueillette auto-attribués', async () => {
    await assertFails(create({ ...familyShare('household-amina', 3), finalPriceCents: 0 }))
    await assertFails(create({ ...familyShare('household-amina', 3), isPaid: true }))
    await assertFails(create({ ...familyShare('household-amina', 3), qrCode: qr('order-open', 'household-amina') }))
    await assertFails(create({ ...familyShare('household-amina', 3), isPickedUp: true }))
    await assertFails(create({ ...familyShare('household-amina', 3), subsidyCents: 1 }))
  })
  test('champ inconnu ou householdId différent du document', async () => {
    await assertFails(create({ ...familyShare('household-amina', 3), isAdmin: true }))
    await assertFails(create({ ...familyShare('household-bob', 3) }))
  })
  test('panier suspendu au-delà de 200 $ (SolidarityLedger.maxSuspendedAmountCents)', async () => {
    await assertFails(updateDoc(doc(as('bob'), 'groupOrders/order-open/shares/household-bob'), { suspendedAmountCents: 20_001 }))
    await assertFails(updateDoc(doc(as('bob'), 'groupOrders/order-open/shares/household-bob'), { suspendedAmountCents: -500 }))
    await assertFails(updateDoc(doc(as('bob'), 'groupOrders/order-open/shares/household-bob'), { suspendedAmountCents: 99.5 }))
  })
  test('modifier sa subvention, son prix ou son paiement en cours de commande', async () => {
    const ref = doc(as('bob'), 'groupOrders/order-open/shares/household-bob')
    await assertFails(updateDoc(ref, { subsidyCents: 739 }))
    await assertFails(updateDoc(ref, { finalPriceCents: 1 }))
    await assertFails(updateDoc(ref, { isPaid: true }))
    await assertFails(updateDoc(ref, { isPickedUp: true }))
  })
  test('changer sa quantité après la date limite ou une fois fermée', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-due', 'household-amina',
      familyShare('household-amina', 5), { ...dueOrder, committedShares: 11 }))
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'offers/offer-carottes'), { deadline: future() })
      await updateDoc(doc(c.firestore(), 'groupOrders/order-open'), { status: 'closed' })
    })
    await assertFails(setShareBatch(as('bob'), 'order-open', 'household-bob',
      familyShare('household-bob', 3), { ...openOrder, status: 'closed', committedShares: 3 }))
  })
  test('marquer sa part payée ou récupérée après la clôture', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'groupOrders/order-due/shares/household-amina'), closedShare('household-amina', 4, 739))
      await updateDoc(doc(c.firestore(), 'groupOrders/order-due'), { status: 'closed' })
    })
    await assertFails(updateDoc(doc(as('amina'), 'groupOrders/order-due/shares/household-amina'), { isPaid: true }))
    await assertFails(updateDoc(doc(as('amina'), 'groupOrders/order-due/shares/household-amina'), { isPickedUp: true }))
    await assertFails(deleteDoc(doc(as('amina'), 'groupOrders/order-due/shares/household-amina')))
  })
  test('supprimer la part d’un autre ménage', async () => {
    await assertFails(setShareBatch(as('amina'), 'order-open', 'household-bob', null,
      { ...openOrder, committedShares: 0, committedHouseholds: 0 }))
  })
})

describe('attaques : coordonnateur et vendeur à la clôture', () => {
  test('clôturer avant la date limite', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'offers/offer-due'), { deadline: future() })
    })
    await assertFails(closeBatch(as('jean'), 'order-due', [], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('confirmer (closed) une commande sous le minimum', async () => {
    await assertFails(setDoc(doc(as('jean'), 'groupOrders/order-low'), { ...lowOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('annuler une commande qui a atteint le minimum', async () => {
    await assertFails(setDoc(doc(as('jean'), 'groupOrders/order-due'), { ...dueOrder, status: 'cancelled' }))
  })
  test('figer un meilleur palier que celui atteint', async () => {
    await assertFails(closeBatch(as('jean'), 'order-due', [
      closedShare('household-amina', 4, 559), closedShare('household-bob', 6, 559)
    ], { ...dueOrder, status: 'closed', currentTierIndex: 2 }))
  })
  test('prix final de sa propre part à 0 $', async () => {
    await assertFails(closeBatch(as('jean'), 'order-due', [
      { ...closedShare('household-amina', 4, 739), finalPriceCents: 0 }, closedShare('household-bob', 6, 739)
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('subvention à un ménage non subventionné (Amina)', async () => {
    await assertFails(closeBatch(as('jean'), 'order-due', [
      closedShare('household-amina', 4, 739, 1000), closedShare('household-bob', 6, 739)
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('subvention plus grande que le prix', async () => {
    await assertFails(closeBatch(as('jean'), 'order-due', [
      closedShare('household-amina', 4, 739), closedShare('household-bob', 6, 739, 6 * 739 + 1)
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('QR d’une autre commande ou d’un autre ménage', async () => {
    await assertFails(closeBatch(as('jean'), 'order-due', [
      { ...closedShare('household-amina', 4, 739), qrCode: qr('order-due', 'household-bob') }
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
    await assertFails(closeBatch(as('jean'), 'order-due', [
      { ...closedShare('household-amina', 4, 739), qrCode: 'GRENIER:order-x:household-amina:00000000' }
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('marquer payé ou changer la quantité pendant la clôture', async () => {
    await assertFails(closeBatch(as('jean'), 'order-due', [
      { ...closedShare('household-amina', 4, 739), isPaid: true }
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
    await assertFails(closeBatch(as('jean'), 'order-due', [
      { ...closedShare('household-amina', 1, 739) }
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('modifier les compteurs à la clôture', async () => {
    await assertFails(setDoc(doc(as('jean'), 'groupOrders/order-low'), { ...lowOrder, status: 'closed', committedShares: 8, currentTierIndex: 0 }))
  })
  test('prix posé sans clôturer la commande', async () => {
    await assertFails(setDoc(doc(as('jean'), 'groupOrders/order-due/shares/household-amina'), closedShare('household-amina', 4, 739)))
  })
  test('un membre non coordonnateur clôture', async () => {
    await assertFails(closeBatch(as('amina'), 'order-due', [
      closedShare('household-amina', 4, 739), closedShare('household-bob', 6, 739)
    ], { ...dueOrder, status: 'closed', currentTierIndex: 0 }))
  })
  test('le coordonnateur d’un autre groupe ou le vendeur d’un autre lot clôture', async () => {
    await assertFails(setDoc(doc(as('rival'), 'groupOrders/order-low'), { ...lowOrder, status: 'cancelled' }))
    await assertFails(setDoc(doc(as('autre'), 'groupOrders/order-low'), { ...lowOrder, status: 'cancelled' }))
  })
  test('le coordonnateur choisit un point de cueillette inexistant', async () => {
    await assertFails(updateDoc(doc(as('jean'), 'groupOrders/order-open'), { pickupPointId: 'pickup-fantome' }))
  })
  test('un membre non coordonnateur choisit le point de cueillette', async () => {
    await assertFails(updateDoc(doc(as('amina'), 'groupOrders/order-open'), { pickupPointId: 'pickup-1' }))
  })
  test('un étranger qui se déclare du ménage de Bob lui change son créneau', async () => {
    await updateDoc(doc(as('intrus'), 'users/intrus'), { householdId: 'household-bob' })
    await assertFails(updateDoc(doc(as('intrus'), 'groupOrders/order-open/shares/household-bob'), { pickupSlotStart: Timestamp.now() }))
  })
  test('le coordonnateur modifie la part d’une famille en cours de commande', async () => {
    await assertFails(updateDoc(doc(as('jean'), 'groupOrders/order-open/shares/household-bob'), { quantity: 1 }))
  })
})

describe('attaques : lots et produits (vendeur)', () => {
  const offerRef = (uid: string, id = 'offer-carottes') => doc(as(uid), `offers/${id}`)
  test('paliers piégés : prix négatif, seuil 0, non triés, prix croissant, type, champ en trop', async () => {
    for (const bad of [
      [{ minShares: 8, priceCents: -100 }],
      [{ minShares: 0, priceCents: 739 }],
      [{ minShares: 16, priceCents: 649 }, { minShares: 8, priceCents: 739 }],
      [{ minShares: 8, priceCents: 649 }, { minShares: 16, priceCents: 739 }],
      [{ minShares: '8', priceCents: 739 }],
      [{ minShares: 8, priceCents: 7.5 }],
      [{ minShares: 8, priceCents: 739, note: 'x'.repeat(100_000) }],
      [{ minShares: 41, priceCents: 739 }],
      ['palier'],
      []
    ]) {
      await assertFails(updateDoc(offerRef('lafleur'), { tiers: bad }))
    }
  })
  test('le vendeur modifie ses paliers correctement', async () => {
    await assertSucceeds(updateDoc(offerRef('lafleur'), { tiers: [{ minShares: 8, priceCents: 700 }, { minShares: 16, priceCents: 600 }] }))
  })
  test('reculer la date limite dans le passé pour clôturer avant l’heure', async () => {
    await assertFails(updateDoc(offerRef('lafleur'), { deadline: past() }))
  })
  test('repousser la date limite', async () => {
    await assertSucceeds(updateDoc(offerRef('lafleur'), { deadline: Timestamp.fromMillis(Date.now() + 5 * 86_400_000) }))
  })
  test('changer le produit d’un lot publié (RQ-036)', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'products/product-oeufs'), { ...product, id: 'product-oeufs' })
    })
    await assertFails(updateDoc(offerRef('lafleur'), { productId: 'product-oeufs' }))
  })
  test('supprimer un lot publié qui a des commandes', async () => {
    await assertFails(deleteDoc(offerRef('lafleur')))
  })
  test('supprimer un brouillon', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'offers/offer-draft'), { ...offer, id: 'offer-draft', status: 'draft', deadline: future() })
    })
    await assertSucceeds(deleteDoc(offerRef('lafleur', 'offer-draft')))
  })
  test('un autre vendeur modifie, supprime ou crée un lot sur ce produit', async () => {
    await assertFails(updateDoc(offerRef('autre'), { totalShares: 1, minimumSharesToLaunch: 1, tiers: [{ minShares: 1, priceCents: 1 }] }))
    await assertFails(deleteDoc(offerRef('autre')))
    await assertFails(setDoc(doc(as('autre'), 'offers/offer-vol'), { ...offer, id: 'offer-vol', vendorId: 'vendor-autre', deadline: future() }))
  })
  test('un vendeur modifie le produit d’un autre ou le lui vole', async () => {
    await assertFails(updateDoc(doc(as('autre'), 'products/product-carottes'), { name: 'pirate' }))
    await assertFails(updateDoc(doc(as('lafleur'), 'products/product-autre'), { vendorId: 'vendor-lafleur' }))
    await assertFails(deleteDoc(doc(as('autre'), 'products/product-carottes')))
  })
  test('type confusion et gros documents sur un produit', async () => {
    const ref = doc(as('lafleur'), 'products/product-carottes')
    await assertFails(updateDoc(ref, { referenceGroceryPriceCents: '899' }))
    await assertFails(updateDoc(ref, { referenceGroceryPriceCents: -1 }))
    await assertFails(updateDoc(ref, { name: 'x'.repeat(121) }))
    await assertFails(updateDoc(ref, { category: 'weapons' }))
  })
  test('un vendeur se rattache à un autre vendeur ou se crée une vitrine', async () => {
    await assertFails(updateDoc(doc(as('lafleur'), 'users/lafleur'), { vendorId: 'vendor-autre' }))
    await assertFails(updateDoc(doc(as('lafleur'), 'users/lafleur'), { vendorId: deleteField() }))
    await assertFails(setDoc(doc(as('intrus'), 'vendors/vendor-intrus'), { id: 'vendor-intrus', legalName: 'x' }))
    await assertFails(updateDoc(doc(as('lafleur'), 'vendors/vendor-lafleur'), { description: 42 }))
  })
})

describe('attaques : groupes, points de cueillette, profils', () => {
  test('un ménage se fait coordonnateur ou réécrit le groupe', async () => {
    await assertFails(updateDoc(doc(as('jean'), `groups/${GROUP}`), { coordinatorIds: ['jean', 'amina'] }))
    await assertFails(updateDoc(doc(as('jean'), `groups/${GROUP}/members/household-jean`), { role: 'coordinator' }))
  })
  test('le coordonnateur expulse un ménage', async () => {
    await assertFails(deleteDoc(doc(as('jean'), `groups/${GROUP}/members/household-amina`)))
  })
  test('adhésion antidatée', async () => {
    await assertFails(setDoc(doc(as('rival'), `groups/${GROUP}/members/household-rival`), { householdId: 'household-rival', role: 'member', joinedAt: Timestamp.fromMillis(0) }))
  })
  test('adhésion légitime', async () => {
    await assertSucceeds(setDoc(doc(as('rival'), `groups/${GROUP}/members/household-rival`), { householdId: 'household-rival', role: 'member', joinedAt: serverTimestamp() }))
  })
  test('l’hôte : capacité négative, type, hôte changé', async () => {
    const ref = doc(as('jean'), 'pickupPoints/pickup-1')
    await assertFails(updateDoc(ref, { capacity: -1 }))
    await assertFails(updateDoc(ref, { capacity: '40' }))
    await assertFails(updateDoc(ref, { hostUserId: 'amina' }))
    await assertFails(updateDoc(ref, { slots: Array(51).fill({}) }))
  })
  test('lire le ménage ou le profil privé d’un autre ménage du groupe', async () => {
    await assertFails(getDoc(doc(as('amina'), 'households/household-bob')))
    await assertFails(getDoc(doc(as('amina'), 'households/household-bob/private/profile')))
    await assertFails(getDoc(doc(as('jean'), 'users/amina')))
  })
  test('profil : nom géant, langue inconnue, rôle inventé, id changé', async () => {
    const ref = doc(as('amina'), 'users/amina')
    await assertFails(updateDoc(ref, { displayName: 'x'.repeat(81) }))
    await assertFails(updateDoc(ref, { language: 'xx' }))
    await assertFails(updateDoc(ref, { roles: ['admin'] }))
    await assertFails(updateDoc(ref, { id: 'bob' }))
    await assertFails(updateDoc(ref, { seniorMode: 'yes' }))
  })
  test('s’ajouter au ménage d’un autre, ou le supprimer', async () => {
    await assertFails(updateDoc(doc(as('intrus'), 'households/household-bob'), { userIds: ['bob', 'intrus'] }))
    await assertFails(deleteDoc(doc(as('bob'), 'households/household-bob')))
  })
})
