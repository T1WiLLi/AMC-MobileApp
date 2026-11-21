// Tests des règles Firestore (firestore.rules) sur l'émulateur.
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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  collection,
  collectionGroup,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc
} from 'firebase/firestore'

let env: RulesTestEnvironment

const amina = () => env.authenticatedContext('amina').firestore()
const lafleur = () => env.authenticatedContext('lafleur').firestore()
const intruder = () => env.authenticatedContext('intrus').firestore()
const anonymous = () => env.unauthenticatedContext().firestore()

const aminaUser = {
  id: 'amina', displayName: 'Amina', language: 'fr', roles: ['family'], neighborhood: 'parc-extension',
  dietaryPreferences: ['halal'], seniorMode: false, householdId: 'household-amina'
}
const product = {
  id: 'product-carottes', vendorId: 'vendor-lafleur', name: 'Carottes', category: 'produce',
  unit: 'sac de 5 kg', origin: 'Saint-Rémi, QC', tags: ['local'], referenceGroceryPriceCents: 899
}
const offer = {
  id: 'offer-carottes', vendorId: 'vendor-lafleur', productId: 'product-carottes', totalShares: 40,
  shareUnit: 'sac de 5 kg', tiers: [{ minShares: 10, priceCents: 700 }], minimumSharesToLaunch: 10,
  deadline: Timestamp.fromMillis(Date.now() + 86_400_000), zones: ['parc-extension'], status: 'active'
}
const share = {
  householdId: 'household-amina', quantity: 2, isPaid: false, suspendedAmountCents: 0,
  subsidyCents: 0, isPickedUp: false
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
    await setDoc(doc(db, 'users/amina'), aminaUser)
    await setDoc(doc(db, 'users/lafleur'), { ...aminaUser, id: 'lafleur', displayName: 'Ferme Lafleur', roles: ['vendor'], householdId: null, vendorId: 'vendor-lafleur' })
    await setDoc(doc(db, 'users/intrus'), { ...aminaUser, id: 'intrus', displayName: 'Intrus', householdId: null })
    await setDoc(doc(db, 'households/household-amina'), { id: 'household-amina', name: 'Famille Benali', size: 5, geohash: 'f25du', userIds: ['amina'] })
    await setDoc(doc(db, 'households/household-amina/private/profile'), { isSubsidized: true })
    await setDoc(doc(db, 'groups/group-parc-extension'), { id: 'group-parc-extension', name: 'Voisins de Parc-Ex', isPublic: true, inviteCode: 'PARC' })
    await setDoc(doc(db, 'vendors/vendor-lafleur'), { id: 'vendor-lafleur', legalName: 'Ferme Lafleur', kind: 'farm', description: 'x', photoURLs: [], servedZones: [], isVerified: true })
    await setDoc(doc(db, 'vendors/vendor-autre'), { id: 'vendor-autre', legalName: 'Autre', kind: 'farm', description: 'x', photoURLs: [], servedZones: [], isVerified: false })
    await setDoc(doc(db, 'products/product-carottes'), product)
    await setDoc(doc(db, 'offers/offer-carottes'), offer)
    await setDoc(doc(db, 'groupOrders/order-1'), { id: 'order-1', groupId: 'group-parc-extension', offerId: 'offer-carottes', status: 'open', committedShares: 0, committedHouseholds: 0, pickupSlots: [] })
    await setDoc(doc(db, 'groupOrders/order-closed'), { id: 'order-closed', status: 'closed' })
    await setDoc(doc(db, 'pickupPoints/pickup-1'), { id: 'pickup-1', hostUserId: 'amina', name: 'Église', address: '1 rue', capacity: 40, accessibility: [], slots: [] })
  })
})

describe('lecture publique pour les connectés', () => {
  for (const path of ['groups/group-parc-extension', 'vendors/vendor-lafleur', 'products/product-carottes',
                      'offers/offer-carottes', 'groupOrders/order-1', 'pickupPoints/pickup-1']) {
    test(`connecté lit ${path}`, async () => { await assertSucceeds(getDoc(doc(intruder(), path))) })
    test(`anonyme ne lit pas ${path}`, async () => { await assertFails(getDoc(doc(anonymous(), path))) })
  }
  test('connecté liste les lots', async () => { await assertSucceeds(getDocs(collection(intruder(), 'offers'))) })
  test('personne n’écrit un groupe', async () => {
    await assertFails(setDoc(doc(amina(), 'groups/nouveau'), { id: 'nouveau', name: 'x', isPublic: true }))
  })
  test('personne n’écrit une commande groupée', async () => {
    await assertFails(updateDoc(doc(amina(), 'groupOrders/order-1'), { committedShares: 99 }))
  })
})

describe('users', () => {
  test('lit son profil', async () => { await assertSucceeds(getDoc(doc(amina(), 'users/amina'))) })
  test('ne lit pas le profil d’un autre', async () => { await assertFails(getDoc(doc(intruder(), 'users/amina'))) })
  test('crée son profil', async () => {
    const db = env.authenticatedContext('nouveau').firestore()
    await assertSucceeds(setDoc(doc(db, 'users/nouveau'), { ...aminaUser, id: 'nouveau', householdId: null }))
  })
  test('ne crée pas son profil avec un vendorId', async () => {
    const db = env.authenticatedContext('nouveau').firestore()
    await assertFails(setDoc(doc(db, 'users/nouveau'), { ...aminaUser, id: 'nouveau', vendorId: 'vendor-lafleur' }))
  })
  test('ne s’ajoute pas un vendorId plus tard', async () => {
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { vendorId: 'vendor-lafleur' }))
  })
  test('modifie son nom', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'users/amina'), { displayName: 'Amina B.' }))
  })
  test('refuse un champ inconnu', async () => {
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { isAdmin: true }))
  })
  test('n’écrit pas le profil d’un autre', async () => {
    await assertFails(updateDoc(doc(intruder(), 'users/amina'), { displayName: 'pirate' }))
  })
})

describe('households', () => {
  test('membre lit son ménage et le privé', async () => {
    await assertSucceeds(getDoc(doc(amina(), 'households/household-amina')))
    await assertSucceeds(getDoc(doc(amina(), 'households/household-amina/private/profile')))
  })
  test('étranger ne lit ni le ménage ni le privé', async () => {
    await assertFails(getDoc(doc(intruder(), 'households/household-amina')))
    await assertFails(getDoc(doc(intruder(), 'households/household-amina/private/profile')))
  })
  test('étranger ne s’ajoute pas au ménage', async () => {
    await assertFails(updateDoc(doc(intruder(), 'households/household-amina'), { userIds: ['amina', 'intrus'] }))
  })
  test('crée un ménage dont il est membre', async () => {
    await assertSucceeds(setDoc(doc(intruder(), 'households/h-intrus'), { id: 'h-intrus', name: 'Moi', size: 2, geohash: 'f25', userIds: ['intrus'] }))
  })
  test('ne crée pas un ménage sans y être', async () => {
    await assertFails(setDoc(doc(intruder(), 'households/h-x'), { id: 'h-x', name: 'X', size: 2, geohash: 'f25', userIds: ['amina'] }))
  })
})

describe('groups/members', () => {
  test('le ménage rejoint un groupe', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'groups/group-parc-extension/members/household-amina'), { householdId: 'household-amina', role: 'member', joinedAt: serverTimestamp() }))
  })
  test('pas comme coordinateur', async () => {
    await assertFails(setDoc(doc(amina(), 'groups/group-parc-extension/members/household-amina'), { householdId: 'household-amina', role: 'coordinator', joinedAt: serverTimestamp() }))
  })
  test('pas pour le ménage d’un autre', async () => {
    await assertFails(setDoc(doc(intruder(), 'groups/group-parc-extension/members/household-amina'), { householdId: 'household-amina', role: 'member', joinedAt: serverTimestamp() }))
  })
})

describe('vendeur : products et offers', () => {
  test('le vendeur crée un produit', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), 'products/product-oeufs'), { ...product, id: 'product-oeufs', name: 'Œufs', category: 'eggs' }))
  })
  test('le vendeur crée un lot sur son produit', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), 'offers/offer-2'), { ...offer, id: 'offer-2' }))
  })
  test('pas de produit pour un autre vendeur', async () => {
    await assertFails(setDoc(doc(lafleur(), 'products/p-x'), { ...product, id: 'p-x', vendorId: 'vendor-autre' }))
  })
  test('une famille ne crée pas de produit', async () => {
    await assertFails(setDoc(doc(amina(), 'products/p-x'), { ...product, id: 'p-x' }))
  })
  test('une famille ne baisse pas un prix', async () => {
    await assertFails(updateDoc(doc(amina(), 'offers/offer-carottes'), { tiers: [{ minShares: 1, priceCents: 1 }] }))
  })
  test('le vendeur ne transfère pas son lot', async () => {
    await assertFails(updateDoc(doc(lafleur(), 'offers/offer-carottes'), { vendorId: 'vendor-autre' }))
  })
  test('lot invalide refusé (minimum > total)', async () => {
    await assertFails(updateDoc(doc(lafleur(), 'offers/offer-carottes'), { minimumSharesToLaunch: 100 }))
  })
  test('le vendeur modifie sa vitrine, pas sa vérification', async () => {
    await assertSucceeds(updateDoc(doc(lafleur(), 'vendors/vendor-lafleur'), { description: 'Nouveau' }))
    await assertFails(updateDoc(doc(lafleur(), 'vendors/vendor-lafleur'), { isVerified: false, description: 'y' }))
    await assertFails(updateDoc(doc(lafleur(), 'vendors/vendor-autre'), { description: 'pirate' }))
  })
})

describe('groupOrders/shares', () => {
  const sharePath = 'groupOrders/order-1/shares/household-amina'
  test('le ménage réserve sa part', async () => { await assertSucceeds(setDoc(doc(amina(), sharePath), share)) })
  test('pas une part déjà payée', async () => { await assertFails(setDoc(doc(amina(), sharePath), { ...share, isPaid: true })) })
  test('pas de subvention auto-attribuée', async () => { await assertFails(setDoc(doc(amina(), sharePath), { ...share, subsidyCents: 500 })) })
  test('pas la part d’un autre ménage', async () => { await assertFails(setDoc(doc(intruder(), sharePath), share)) })
  test('pas sur une commande fermée', async () => {
    await assertFails(setDoc(doc(amina(), 'groupOrders/order-closed/shares/household-amina'), share))
  })
  test('change la quantité, pas le paiement', async () => {
    await env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), sharePath), share) })
    await assertSucceeds(updateDoc(doc(amina(), sharePath), { quantity: 3 }))
    await assertFails(updateDoc(doc(amina(), sharePath), { isPaid: true }))
    await assertFails(getDoc(doc(intruder(), sharePath)))
    await assertSucceeds(deleteDoc(doc(amina(), sharePath)))
  })
})

describe('pickupPoints', () => {
  test('l’hôte gère sa capacité', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'pickupPoints/pickup-1'), { capacity: 30 }))
  })
  test('l’hôte ne change pas d’hôte', async () => {
    await assertFails(updateDoc(doc(amina(), 'pickupPoints/pickup-1'), { hostUserId: 'intrus' }))
  })
  test('un autre ne touche pas au point', async () => {
    await assertFails(updateDoc(doc(intruder(), 'pickupPoints/pickup-1'), { capacity: 0 }))
  })
})

describe('hôte et créneaux (T-077)', () => {
  const point = { id: 'pickup-intrus', hostUserId: 'intrus', name: 'Chez moi', address: '2 rue', capacity: 10, accessibility: ['stepFree'], slots: [] }
  const start = Timestamp.fromMillis(Date.now() + 3 * 86_400_000)
  const slot = { start, end: Timestamp.fromMillis(start.toMillis() + 3_600_000), capacity: 5 }
  const sharePath = 'groupOrders/order-1/shares/household-amina'

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, 'groups/group-parc-extension'), { id: 'group-parc-extension', name: 'Voisins de Parc-Ex', isPublic: true, inviteCode: 'PARC', coordinatorIds: ['amina'] })
      await setDoc(doc(db, 'groups/group-parc-extension/members/household-amina'), { householdId: 'household-amina', role: 'coordinator' })
      await setDoc(doc(db, sharePath), share)
    })
  })

  test('on devient hôte en créant son propre point', async () => {
    await assertSucceeds(setDoc(doc(intruder(), 'pickupPoints/pickup-intrus'), point))
  })
  test('pas de point au nom d’un autre hôte', async () => {
    await assertFails(setDoc(doc(intruder(), 'pickupPoints/pickup-x'), { ...point, id: 'pickup-x', hostUserId: 'amina' }))
  })
  test('pas de point sans adresse ni capacité', async () => {
    await assertFails(setDoc(doc(intruder(), 'pickupPoints/pickup-intrus'), { ...point, address: '' }))
    await assertFails(setDoc(doc(intruder(), 'pickupPoints/pickup-intrus'), { ...point, capacity: 0 }))
  })
  test('l’hôte change son adresse et sa photo', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'pickupPoints/pickup-1'), { address: '3 rue', photoURL: 'https://example.com/a.jpg' }))
  })
  test('le coordonnateur choisit le point et les créneaux', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'groupOrders/order-1'), { pickupPointId: 'pickup-1', pickupSlots: [slot] }))
  })
  test('un non-coordonnateur ne choisit pas le point', async () => {
    await assertFails(updateDoc(doc(intruder(), 'groupOrders/order-1'), { pickupPointId: 'pickup-1' }))
  })
  test('le choix du point ne change pas les compteurs', async () => {
    await assertFails(updateDoc(doc(amina(), 'groupOrders/order-1'), { pickupPointId: 'pickup-1', committedShares: 5 }))
  })
  test('le ménage réserve et annule son créneau', async () => {
    await assertSucceeds(updateDoc(doc(amina(), sharePath), { pickupSlotStart: start }))
    await assertSucceeds(updateDoc(doc(amina(), sharePath), { pickupSlotStart: null }))
  })
  test('pas le créneau d’un autre ménage', async () => {
    await assertFails(updateDoc(doc(intruder(), sharePath), { pickupSlotStart: start }))
  })
  test('la réservation ne touche pas au paiement', async () => {
    await assertFails(updateDoc(doc(amina(), sharePath), { pickupSlotStart: start, isPaid: true }))
  })
})

describe('reste refusé', () => {
  test('collection inconnue', async () => {
    await assertFails(setDoc(doc(amina(), 'admin/config'), { open: true }))
    await assertFails(getDoc(doc(amina(), 'admin/config')))
  })
})

describe('envies des familles et disponibilités des vendeurs (S-07, S-08)', () => {
  const voisin = () => env.authenticatedContext('voisin').firestore()
  const wishPath = 'groups/group-parc-extension/wishes/wish-1'
  const voisinWishPath = 'groups/group-parc-extension/wishes/wish-voisin'
  const supplyPath = 'vendors/vendor-lafleur/supplies/supply-1'
  const now = () => Timestamp.fromMillis(Date.now())
  const wish = (overrides: Record<string, unknown> = {}) => ({
    id: 'wish-1', groupId: 'group-parc-extension', householdId: 'household-amina', category: 'grains',
    quantity: 10, unit: 'kg', frequency: 'monthly', createdAt: now(), updatedAt: now(), ...overrides
  })
  const supply = (overrides: Record<string, unknown> = {}) => ({
    id: 'supply-1', vendorId: 'vendor-lafleur', category: 'produce', productId: 'product-carottes', quantity: 200,
    unit: 'kg', availableFrom: now(), availableTo: Timestamp.fromMillis(Date.now() + 7 * 86_400_000),
    servedZones: ['f25d'], createdAt: now(), updatedAt: now(), ...overrides
  })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore()
      await setDoc(doc(db, 'users/voisin'), { ...aminaUser, id: 'voisin', displayName: 'Voisin', householdId: 'household-voisin' })
      await setDoc(doc(db, 'households/household-voisin'), { id: 'household-voisin', name: 'Voisins', size: 2, geohash: 'f25du', userIds: ['voisin'] })
      await setDoc(doc(db, 'groups/group-parc-extension/members/household-amina'), { householdId: 'household-amina', role: 'member', joinedAt: now() })
      await setDoc(doc(db, 'groups/group-parc-extension/members/household-voisin'), { householdId: 'household-voisin', role: 'member', joinedAt: now() })
      await setDoc(doc(db, voisinWishPath), wish({ id: 'wish-voisin', householdId: 'household-voisin' }))
      await setDoc(doc(db, 'vendors/vendor-autre/supplies/supply-autre'), supply({ id: 'supply-autre', vendorId: 'vendor-autre', productId: null }))
    })
  })

  test('un membre crée l’envie de son ménage', async () => {
    await assertSucceeds(setDoc(doc(amina(), wishPath), wish()))
  })
  test('un membre ne crée pas l’envie d’un autre ménage', async () => {
    await assertFails(setDoc(doc(amina(), wishPath), wish({ householdId: 'household-voisin' })))
  })
  test('un non-membre ne crée pas d’envie', async () => {
    await assertFails(setDoc(doc(intruder(), wishPath), wish({ householdId: 'household-intrus' })))
  })
  test('envie invalide refusée', async () => {
    await assertFails(setDoc(doc(amina(), wishPath), wish({ quantity: 0 })))
    await assertFails(setDoc(doc(amina(), wishPath), wish({ unit: 'tonne' })))
    await assertFails(setDoc(doc(amina(), wishPath), wish({ groupId: 'group-autre' })))
    await assertFails(setDoc(doc(amina(), wishPath), wish({ isAdmin: true })))
  })
  test('un membre change et retire seulement ses envies', async () => {
    await assertSucceeds(updateDoc(doc(voisin(), voisinWishPath), { quantity: 4, updatedAt: now() }))
    await assertFails(updateDoc(doc(voisin(), voisinWishPath), { householdId: 'household-amina' }))
    await assertFails(updateDoc(doc(amina(), voisinWishPath), { quantity: 99 }))
    await assertFails(deleteDoc(doc(amina(), voisinWishPath)))
    await assertSucceeds(deleteDoc(doc(voisin(), voisinWishPath)))
  })
  test('membres et vendeurs lisent les envies, pas les autres', async () => {
    await assertSucceeds(getDocs(collection(amina(), 'groups/group-parc-extension/wishes')))
    await assertSucceeds(getDocs(collection(lafleur(), 'groups/group-parc-extension/wishes')))
    await assertFails(getDocs(collection(intruder(), 'groups/group-parc-extension/wishes')))
    await assertFails(getDocs(collection(anonymous(), 'groups/group-parc-extension/wishes')))
  })
  test('collectionGroup des envies : vendeurs seulement', async () => {
    await assertSucceeds(getDocs(collectionGroup(lafleur(), 'wishes')))
    await assertFails(getDocs(collectionGroup(amina(), 'wishes')))
  })

  test('le vendeur crée, change et retire ses disponibilités', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), supplyPath), supply()))
    await assertSucceeds(updateDoc(doc(lafleur(), supplyPath), { quantity: 150, updatedAt: now() }))
    await assertFails(updateDoc(doc(lafleur(), supplyPath), { vendorId: 'vendor-autre' }))
    await assertSucceeds(deleteDoc(doc(lafleur(), supplyPath)))
  })
  test('disponibilité invalide refusée', async () => {
    await assertFails(setDoc(doc(lafleur(), supplyPath), supply({ servedZones: [] })))
    await assertFails(setDoc(doc(lafleur(), supplyPath), supply({ quantity: -1 })))
    await assertFails(setDoc(doc(lafleur(), supplyPath), supply({ availableTo: Timestamp.fromMillis(0) })))
    await assertFails(setDoc(doc(lafleur(), 'vendors/vendor-lafleur/supplies/supply-2'), supply({ id: 'supply-2', productId: 'product-inconnu' })))
  })
  test('personne d’autre n’écrit les disponibilités d’un vendeur', async () => {
    await assertFails(setDoc(doc(amina(), supplyPath), supply()))
    await assertFails(setDoc(doc(lafleur(), 'vendors/vendor-autre/supplies/supply-1'), supply({ vendorId: 'vendor-autre', productId: null })))
    await assertFails(deleteDoc(doc(lafleur(), 'vendors/vendor-autre/supplies/supply-autre')))
  })
  test('tout connecté lit les disponibilités, pas l’anonyme', async () => {
    await assertSucceeds(getDocs(collection(amina(), 'vendors/vendor-autre/supplies')))
    await assertSucceeds(getDocs(collectionGroup(amina(), 'supplies')))
    await assertFails(getDocs(collectionGroup(anonymous(), 'supplies')))
  })
})
