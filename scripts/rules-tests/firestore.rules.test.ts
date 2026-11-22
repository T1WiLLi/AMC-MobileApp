// Tests des règles Firestore (firestore.rules) sur l'émulateur.
// Lancer depuis la racine : npm --prefix scripts/rules-tests run test:emulators
import { after, before, beforeEach, describe, test } from 'node:test'
import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
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
  query,
  where,
  serverTimestamp,
  setDoc,
  Timestamp,
  Bytes,
  updateDoc,
  increment,
  arrayUnion,
  arrayRemove,
  writeBatch,
  runTransaction,
  type Firestore
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
    await setDoc(doc(db, 'groups/group-parc-extension'), { id: 'group-parc-extension', name: 'Voisins de Parc-Ex', isPublic: true, inviteCode: 'PARC', householdCount: 3 })
    await setDoc(doc(db, 'households/household-intrus'), { id: 'household-intrus', name: 'Intrus', size: 1, geohash: 'f25du', userIds: ['intrus'] })
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

describe('onboarding après l’inscription (T-156)', () => {
  const nouveau = () => env.authenticatedContext('nouveau').firestore()
  const nouveauUser = { ...aminaUser, id: 'nouveau', displayName: 'Nouvelle', neighborhood: '', dietaryPreferences: [], householdId: 'household-nouveau' }
  const nouveauHousehold = { id: 'household-nouveau', name: 'Ménage de Nouvelle', size: 1, geohash: '', userIds: ['nouveau'] }

  test('compte neuf : ménage puis profil avec onboardingCompleted false', async () => {
    const db = nouveau()
    await assertSucceeds(setDoc(doc(db, 'households/household-nouveau'), nouveauHousehold))
    await assertSucceeds(setDoc(doc(db, 'users/nouveau'), { ...nouveauUser, onboardingCompleted: false }))
  })
  test('fin de l’onboarding : ménage (nom, taille, geohash) puis profil (goûts, quartier, drapeau)', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore()
      await setDoc(doc(db, 'households/household-nouveau'), nouveauHousehold)
      await setDoc(doc(db, 'users/nouveau'), { ...nouveauUser, onboardingCompleted: false })
    })
    const db = nouveau()
    await assertSucceeds(setDoc(doc(db, 'households/household-nouveau'),
      { ...nouveauHousehold, name: 'Famille Benali', size: 4, geohash: 'f25dv' }, { merge: true }))
    await assertSucceeds(setDoc(doc(db, 'users/nouveau'), {
      ...nouveauUser, neighborhood: 'Saint-Michel', dietaryPreferences: ['halal', 'glutenFree'],
      favoriteCategories: ['grains', 'eggs', 'produce'], onboardingCompleted: true
    }, { merge: true }))
  })
  test('profil d’avant T-156 sans les nouveaux champs : toujours valide', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'users/amina'), { neighborhood: 'Villeray' }))
  })
  test('catégorie inconnue refusée', async () => {
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { favoriteCategories: ['grains', 'alcool'] }))
  })
  test('catégories en liste seulement, 9 au plus', async () => {
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { favoriteCategories: 'grains' }))
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { favoriteCategories: Array(10).fill('grains') }))
  })
  test('onboardingCompleted booléen seulement', async () => {
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { onboardingCompleted: 'oui' }))
    await assertSucceeds(updateDoc(doc(amina(), 'users/amina'), { onboardingCompleted: true }))
  })
  test('n’écrit pas l’onboarding d’un autre', async () => {
    await assertFails(updateDoc(doc(intruder(), 'users/amina'), { onboardingCompleted: true }))
  })
  test('étranger ne renomme pas le ménage d’un autre', async () => {
    await assertFails(updateDoc(doc(intruder(), 'households/household-amina'), { name: 'Pirates', size: 2 }))
  })
})

describe('ménage partagé (T-159)', () => {
  const karim = () => env.authenticatedContext('karim').firestore()
  const karimUser = { ...aminaUser, id: 'karim', displayName: 'Karim Benali', householdId: 'household-karim' }
  const lookupId = 'a'.repeat(64)
  const request = (status = 'pending') => ({
    householdId: 'household-amina', userId: 'karim', displayName: 'Karim Benali',
    createdAt: Timestamp.now(), status
  })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore()
      await setDoc(doc(db, 'users/karim'), karimUser)
      await setDoc(doc(db, 'households/household-karim'), { id: 'household-karim', name: 'Ménage de Karim', size: 1, geohash: '', userIds: ['karim'], ownerId: 'karim' })
      await setDoc(doc(db, 'households/household-amina'), {
        id: 'household-amina', name: 'Famille Benali', size: 5, geohash: 'f25du', userIds: ['amina'],
        ownerId: 'amina', addressKey: '1234jarryest-h2r1a1', memberNames: { amina: 'Amina' }
      })
    })
  })

  async function seedRequest(status = 'pending') {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'households/household-amina/joinRequests/karim'), request(status))
    })
  }

  async function acceptAsAmina() {
    const db = amina()
    const batch = writeBatch(db)
    batch.update(doc(db, 'households/household-amina'), { userIds: ['amina', 'karim'], 'memberNames.karim': 'Karim Benali' })
    batch.update(doc(db, 'households/household-amina/joinRequests/karim'), { status: 'accepted' })
    return batch.commit()
  }

  test('le propriétaire inscrit son adresse ; tout connecté la lit par son id exact', async () => {
    await assertSucceeds(setDoc(doc(amina(), `householdAddresses/${lookupId}`),
      { id: lookupId, householdId: 'household-amina', name: 'Famille Benali', ownerId: 'amina' }))
    await assertSucceeds(getDoc(doc(karim(), `householdAddresses/${lookupId}`)))
  })
  test('personne ne liste les adresses', async () => {
    await assertFails(getDocs(collection(karim(), 'householdAddresses')))
    await assertFails(getDocs(query(collection(karim(), 'householdAddresses'), where('name', '==', 'Famille Benali'))))
  })
  test('on n’inscrit pas l’adresse du ménage d’un autre, ni par-dessus la sienne', async () => {
    await assertFails(setDoc(doc(karim(), `householdAddresses/${lookupId}`),
      { id: lookupId, householdId: 'household-amina', name: 'Famille Benali', ownerId: 'karim' }))
    await assertSucceeds(setDoc(doc(amina(), `householdAddresses/${lookupId}`),
      { id: lookupId, householdId: 'household-amina', name: 'Famille Benali', ownerId: 'amina' }))
    await assertFails(setDoc(doc(karim(), `householdAddresses/${lookupId}`),
      { id: lookupId, householdId: 'household-karim', name: 'Ménage de Karim', ownerId: 'karim' }))
  })
  test('id d’adresse : empreinte SHA-256 seulement (pas d’adresse en clair)', async () => {
    await assertFails(setDoc(doc(amina(), 'householdAddresses/1234jarryest-h2r1a1'),
      { id: '1234jarryest-h2r1a1', householdId: 'household-amina', name: 'Famille Benali', ownerId: 'amina' }))
  })
  test('la personne crée sa demande, la relit et l’annule', async () => {
    const ref = doc(karim(), 'households/household-amina/joinRequests/karim')
    await assertSucceeds(setDoc(ref, request()))
    await assertSucceeds(getDoc(ref))
    await assertSucceeds(deleteDoc(ref))
  })
  test('pas de demande au nom d’un autre, ni déjà acceptée', async () => {
    await assertFails(setDoc(doc(intruder(), 'households/household-amina/joinRequests/karim'), request()))
    await assertFails(setDoc(doc(karim(), 'households/household-amina/joinRequests/karim'), request('accepted')))
  })
  test('le demandeur ne lit toujours pas le ménage ni les autres demandes', async () => {
    await seedRequest()
    await assertFails(getDoc(doc(karim(), 'households/household-amina')))
    await assertFails(getDocs(collection(karim(), 'households/household-amina/joinRequests')))
  })
  test('le propriétaire liste les demandes ; un étranger non', async () => {
    await seedRequest()
    await assertSucceeds(getDocs(collection(amina(), 'households/household-amina/joinRequests')))
    await assertFails(getDocs(collection(intruder(), 'households/household-amina/joinRequests')))
    await assertFails(getDoc(doc(intruder(), 'households/household-amina/joinRequests/karim')))
  })
  test('le propriétaire accepte : uid ajouté et demande acceptée dans un batch', async () => {
    await seedRequest()
    await assertSucceeds(acceptAsAmina())
  })
  test('pas d’ajout sans demande en attente', async () => {
    await assertFails(updateDoc(doc(amina(), 'households/household-amina'), { userIds: ['amina', 'karim'] }))
  })
  test('le demandeur ne s’accepte pas lui-même', async () => {
    await seedRequest()
    await assertFails(updateDoc(doc(karim(), 'households/household-amina/joinRequests/karim'), { status: 'accepted' }))
  })
  test('un membre qui n’est pas propriétaire n’accepte pas', async () => {
    await seedRequest()
    await env.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'households/household-amina'), { userIds: ['amina', 'intrus'] })
      await setDoc(doc(context.firestore(), 'households/household-amina/joinRequests/karim'), request())
    })
    const db = intruder()
    const batch = writeBatch(db)
    batch.update(doc(db, 'households/household-amina'), { userIds: ['amina', 'intrus', 'karim'] })
    batch.update(doc(db, 'households/household-amina/joinRequests/karim'), { status: 'accepted' })
    await assertFails(batch.commit())
  })
  test('le propriétaire refuse : il supprime la demande', async () => {
    await seedRequest()
    await assertSucceeds(deleteDoc(doc(amina(), 'households/household-amina/joinRequests/karim')))
  })
  test('accepté, le demandeur pointe son profil vers le ménage et le lit', async () => {
    await seedRequest()
    await acceptAsAmina()
    await assertSucceeds(updateDoc(doc(karim(), 'users/karim'), { householdId: 'household-amina', pendingHouseholdId: null }))
    await assertSucceeds(getDoc(doc(karim(), 'households/household-amina')))
    await assertSucceeds(deleteDoc(doc(karim(), 'households/household-amina/joinRequests/karim')))
  })
  test('householdId refusé vers un ménage dont on n’est pas membre', async () => {
    await assertFails(updateDoc(doc(karim(), 'users/karim'), { householdId: 'household-amina' }))
    await assertFails(updateDoc(doc(karim(), 'users/karim'), { householdId: 'household-inexistant' }))
    await assertSucceeds(updateDoc(doc(karim(), 'users/karim'), { pendingHouseholdId: 'household-amina' }))
  })
  test('le propriétaire retire un membre ; le membre se retire lui-même ; pas un autre', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'households/household-amina'), { userIds: ['amina', 'karim', 'intrus'] })
    })
    await assertFails(updateDoc(doc(intruder(), 'households/household-amina'), { userIds: ['amina', 'intrus'] }))
    await assertSucceeds(updateDoc(doc(intruder(), 'households/household-amina'), { userIds: ['amina', 'karim'] }))
    await assertSucceeds(updateDoc(doc(amina(), 'households/household-amina'), { userIds: ['amina'] }))
  })
  test('le propriétaire ne se retire pas et ne change pas de propriétaire', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'households/household-amina'), { userIds: ['amina', 'karim'] })
    })
    await assertFails(updateDoc(doc(amina(), 'households/household-amina'), { userIds: ['karim'] }))
    await assertFails(updateDoc(doc(karim(), 'households/household-amina'), { ownerId: 'karim' }))
  })
  test('un membre renomme le ménage sans toucher aux membres', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'households/household-amina'), { userIds: ['amina', 'karim'] })
    })
    await assertSucceeds(updateDoc(doc(karim(), 'households/household-amina'), { name: 'Famille Benali-Haddad' }))
  })
  test('un ménage neuf ne contient que son créateur, propriétaire', async () => {
    await assertSucceeds(setDoc(doc(karim(), 'households/h-k2'), { id: 'h-k2', name: 'K', size: 2, geohash: '', userIds: ['karim'], ownerId: 'karim' }))
    await assertFails(setDoc(doc(karim(), 'households/h-k3'), { id: 'h-k3', name: 'K', size: 2, geohash: '', userIds: ['karim', 'amina'] }))
    await assertFails(setDoc(doc(karim(), 'households/h-k4'), { id: 'h-k4', name: 'K', size: 2, geohash: '', userIds: ['karim'], ownerId: 'amina' }))
  })
  test('ménage d’avant T-159 : le premier compte pose ownerId sur lui-même', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'households/household-amina'), { id: 'household-amina', name: 'Famille Benali', size: 5, geohash: 'f25du', userIds: ['amina'] })
    })
    await assertSucceeds(updateDoc(doc(amina(), 'households/household-amina'), { ownerId: 'amina' }))
  })

  // FB-22 : le propriétaire cède son rôle, puis peut partir.
  async function shareWithKarim() {
    await env.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'households/household-amina'), { userIds: ['amina', 'karim'] })
    })
  }
  test('le propriétaire nomme un autre membre propriétaire, puis quitte le ménage', async () => {
    await shareWithKarim()
    await assertSucceeds(updateDoc(doc(amina(), 'households/household-amina'), { ownerId: 'karim' }))
    await assertSucceeds(updateDoc(doc(amina(), 'households/household-amina'), { userIds: ['karim'] }))
  })
  test('le nouveau propriétaire gère les demandes ; l’ancien ne les liste plus', async () => {
    await shareWithKarim()
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'households/household-amina/joinRequests/nadia'),
        { householdId: 'household-amina', userId: 'nadia', displayName: 'Nadia', createdAt: Timestamp.now(), status: 'pending' })
    })
    await assertSucceeds(updateDoc(doc(amina(), 'households/household-amina'), { ownerId: 'karim' }))
    await assertSucceeds(getDocs(collection(karim(), 'households/household-amina/joinRequests')))
    await assertFails(getDocs(collection(amina(), 'households/household-amina/joinRequests')))
  })
  test('pas de transfert vers quelqu’un hors du ménage, ni par un simple membre', async () => {
    await shareWithKarim()
    await assertFails(updateDoc(doc(amina(), 'households/household-amina'), { ownerId: 'intrus' }))
    await assertFails(updateDoc(doc(karim(), 'households/household-amina'), { ownerId: 'karim' }))
  })
  test('le transfert ne change rien d’autre dans la même écriture', async () => {
    await shareWithKarim()
    await assertFails(updateDoc(doc(amina(), 'households/household-amina'), { ownerId: 'karim', userIds: ['karim'] }))
    await assertFails(updateDoc(doc(amina(), 'households/household-amina'), { ownerId: 'karim', name: 'Autre nom' }))
  })
})

describe('cueillette unique par ménage (T-159)', () => {
  const karim = () => env.authenticatedContext('karim').firestore()
  const sharePath = 'groupOrders/order-pickup/shares/household-voisins'
  const pickedUp = (by = 'karim') => ({ isPickedUp: true, pickedUpBy: by, pickedUpAt: Timestamp.now(), updatedAt: Timestamp.now() })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, 'users/karim'), { ...aminaUser, id: 'karim', displayName: 'Karim', householdId: 'household-voisins' })
      await setDoc(doc(db, 'households/household-voisins'), { id: 'household-voisins', name: 'Voisins', size: 3, geohash: '', userIds: ['karim', 'nadia'], ownerId: 'karim' })
      await setDoc(doc(db, 'groupOrders/order-pickup'), { id: 'order-pickup', groupId: 'group-parc-extension', offerId: 'offer-carottes', status: 'delivered', committedShares: 2, committedHouseholds: 1, pickupPointId: 'pickup-1', pickupSlots: [] })
      await setDoc(doc(db, sharePath), { ...share, householdId: 'household-voisins', qrCode: 'GRENIER:order-pickup:household-voisins:0a1b2c3d' })
    })
  })

  test('l’hôte remet la part à un membre et note qui la prend', async () => {
    await assertSucceeds(getDoc(doc(amina(), sharePath)))
    await assertSucceeds(updateDoc(doc(amina(), sharePath), pickedUp('nadia')))
  })
  test('une part déjà récupérée ne se remet pas une deuxième fois', async () => {
    await updateDoc(doc(amina(), sharePath), pickedUp('karim'))
    await assertFails(updateDoc(doc(amina(), sharePath), pickedUp('nadia')))
  })
  test('le ménage ne se marque pas récupéré lui-même', async () => {
    await assertFails(updateDoc(doc(karim(), sharePath), pickedUp('karim')))
  })
  test('pickedUpBy doit être un membre du ménage', async () => {
    await assertFails(updateDoc(doc(amina(), sharePath), pickedUp('intrus')))
  })
  test('pickedUpBy obligatoire : null ou absent refusé', async () => {
    await assertFails(updateDoc(doc(amina(), sharePath), { ...pickedUp(), pickedUpBy: null }))
    await assertFails(updateDoc(doc(amina(), sharePath), { isPickedUp: true, pickedUpAt: Timestamp.now(), updatedAt: Timestamp.now() }))
  })
  test('« Récupéré » à la main : l’hôte se note lui-même', async () => {
    await assertSucceeds(updateDoc(doc(amina(), sharePath), pickedUp('amina')))
  })
  test('jeton privé du code : le ménage le crée une fois et le relit, l’hôte le lit, l’intrus non', async () => {
    const tokenPath = `${sharePath}/private/pickup`
    const nadia = () => env.authenticatedContext('nadia').firestore()
    await assertSucceeds(getDoc(doc(karim(), tokenPath)))
    await assertSucceeds(setDoc(doc(karim(), tokenPath), { code: 'a'.repeat(32), createdAt: Timestamp.now() }))
    await assertSucceeds(getDoc(doc(nadia(), tokenPath)))
    await assertSucceeds(getDoc(doc(amina(), tokenPath)))
    await assertFails(getDoc(doc(intruder(), tokenPath)))
    await assertFails(setDoc(doc(nadia(), tokenPath), { code: 'b'.repeat(32) }))
  })
  test('pas avant la fermeture de la commande', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'groupOrders/order-pickup'), { status: 'open' })
    })
    await assertFails(updateDoc(doc(amina(), sharePath), pickedUp('karim')))
  })
  test('pas avant l’arrivée de la livraison : commande fermée mais pas encore livrée', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'groupOrders/order-pickup'), { status: 'closed' })
    })
    await assertFails(updateDoc(doc(amina(), sharePath), pickedUp('karim')))
  })
  test('l’hôte ne change pas le nom du ménage sur la part', async () => {
    await assertFails(updateDoc(doc(amina(), sharePath), { householdName: 'Autre nom' }))
    await assertFails(updateDoc(doc(amina(), sharePath), { ...pickedUp('karim'), householdName: 'Autre nom' }))
  })
  test('rien d’autre ne bouge avec la remise', async () => {
    await assertFails(updateDoc(doc(amina(), sharePath), { ...pickedUp('karim'), quantity: 9 }))
  })
})

describe('groups/members', () => {
  const groupPath = 'groups/group-parc-extension'
  const memberPath = `${groupPath}/members/household-amina`
  const membership = { householdId: 'household-amina', role: 'member', joinedAt: serverTimestamp(), userId: 'amina' }

  // Ce que fait FirestoreGroupRepository.join / leave (T-099) : adhésion + compteur, dans un batch.
  function joinBatch(db: Firestore, member: object = membership, householdId = 'household-amina', delta = 1) {
    const batch = writeBatch(db)
    batch.set(doc(db, `${groupPath}/members/household-amina`), member)
    batch.update(doc(db, groupPath), { householdCount: increment(delta), lastMembershipChange: householdId })
    return batch.commit()
  }
  function leaveBatch(db: Firestore, householdId = 'household-amina', delta = -1) {
    const batch = writeBatch(db)
    batch.delete(doc(db, memberPath))
    batch.update(doc(db, groupPath), { householdCount: increment(delta), lastMembershipChange: householdId })
    return batch.commit()
  }
  async function seedMembership() {
    await env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), memberPath), { ...membership, joinedAt: Timestamp.now() }) })
  }
  async function householdCount() {
    let count: unknown
    await env.withSecurityRulesDisabled(async (c) => { count = (await getDoc(doc(c.firestore(), groupPath))).data()?.householdCount })
    return count
  }

  test('adhésion sans userId, ou avec l’uid d’un autre : refusée (T-193)', async () => {
    const { userId: _userId, ...withoutUserId } = membership
    await assertFails(joinBatch(amina(), withoutUserId))
    await assertFails(joinBatch(amina(), { ...membership, userId: 'lafleur' }))
    await assertFails(joinBatch(amina(), { ...membership, userId: '' }))
    await assertSucceeds(joinBatch(amina()))
  })
  test('le ménage rejoint un groupe : adhésion + householdCount +1 (T-099)', async () => {
    await assertSucceeds(joinBatch(amina()))
    assert.equal(await householdCount(), 4)
  })
  test('le ménage quitte un groupe : suppression + householdCount −1 (T-099)', async () => {
    await seedMembership()
    await assertSucceeds(leaveBatch(amina()))
    assert.equal(await householdCount(), 2)
  })
  test('pas d’adhésion sans le compteur', async () => {
    await assertFails(setDoc(doc(amina(), memberPath), membership))
  })
  test('pas de départ sans le compteur', async () => {
    await seedMembership()
    await assertFails(deleteDoc(doc(amina(), memberPath)))
  })
  test('pas de compteur sans l’adhésion', async () => {
    await assertFails(updateDoc(doc(amina(), groupPath), { householdCount: increment(1), lastMembershipChange: 'household-amina' }))
    await seedMembership()
    await assertFails(updateDoc(doc(amina(), groupPath), { householdCount: increment(-1), lastMembershipChange: 'household-amina' }))
  })
  test('pas de saut de plus d’un', async () => {
    await assertFails(joinBatch(amina(), membership, 'household-amina', 2))
    await seedMembership()
    await assertFails(leaveBatch(amina(), 'household-amina', -2))
  })
  test('pas de +1 pour un membre déjà présent, ni de −1 au mauvais sens', async () => {
    await seedMembership()
    // Le set écraserait l’adhésion existante (update interdit) et le ménage était déjà membre.
    await assertFails(joinBatch(amina()))
    await env.withSecurityRulesDisabled(async (c) => { await deleteDoc(doc(c.firestore(), memberPath)) })
    await assertFails(joinBatch(amina(), membership, 'household-amina', -1))
  })
  test('pas au nom du ménage d’un autre', async () => {
    // L’intrus nomme son propre ménage dans lastMembershipChange mais écrit l’adhésion d’Amina.
    await assertFails(joinBatch(intruder(), membership, 'household-intrus'))
    await assertFails(joinBatch(intruder()))
  })
  test('le groupe ne change que householdCount et lastMembershipChange', async () => {
    const db = amina()
    const batch = writeBatch(db)
    batch.set(doc(db, memberPath), membership)
    batch.update(doc(db, groupPath), { householdCount: increment(1), lastMembershipChange: 'household-amina', name: 'Pirate' })
    await assertFails(batch.commit())
  })
  test('pas comme coordinateur', async () => {
    await assertFails(joinBatch(amina(), { ...membership, role: 'coordinator' }))
  })
  test('pas pour le ménage d’un autre', async () => {
    await assertFails(setDoc(doc(intruder(), memberPath), membership))
  })
  test('groupes d’un ménage : requête de groupe de collections (B-017)', async () => {
    await assertSucceeds(getDocs(query(collectionGroup(amina(), 'members'), where('householdId', '==', 'household-amina'))))
  })
  test('pas de requête de groupe de collections sans session', async () => {
    await assertFails(getDocs(query(collectionGroup(anonymous(), 'members'), where('householdId', '==', 'household-amina'))))
  })
  test('groupes d’un ménage : requête de groupe de collections (B-017)', async () => {
    await assertSucceeds(getDocs(query(collectionGroup(amina(), 'members'), where('householdId', '==', 'household-amina'))))
  })
  test('pas de requête de groupe de collections sans session', async () => {
    await assertFails(getDocs(query(collectionGroup(anonymous(), 'members'), where('householdId', '==', 'household-amina'))))
  })
})

describe('vendeur : products et offers', () => {
  test('le vendeur crée un produit', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), 'products/product-oeufs'), { ...product, id: 'product-oeufs', name: 'Œufs', category: 'eggs' }))
  })
  test('le vendeur crée un lot sur son produit', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), 'offers/offer-2'), { ...offer, id: 'offer-2' }))
  })
  test('le vendeur crée un lot avec une part structurée (B-050)', async () => {
    const structured = { container: 'sac', count: 1, weight: { value: 5, unit: 'kg' }, valueCents: 899 }
    await assertSucceeds(setDoc(doc(lafleur(), 'offers/offer-3'), { ...offer, id: 'offer-3', share: structured }))
    await assertSucceeds(updateDoc(doc(lafleur(), 'offers/offer-carottes'), { share: { container: 'vrac', count: 1, weight: { value: 2.5, unit: 'kg' } } }))
  })
  test('part structurée invalide refusée (B-050)', async () => {
    const bad = [
      { container: 'camion', count: 1, weight: { value: 5, unit: 'kg' } },
      { container: 'sac', count: 0, weight: { value: 5, unit: 'kg' } },
      { container: 'sac', count: 1, weight: { value: 0, unit: 'kg' } },
      { container: 'sac', count: 1, weight: { value: 5, unit: 'tonne' } },
      { container: 'sac', count: 1, weight: { value: 5, unit: 'kg' }, valueCents: -1 },
      { container: 'sac', count: 1, weight: { value: 5, unit: 'kg' }, extra: true },
      'sac de 5 kg'
    ]
    for (const share of bad) {
      await assertFails(updateDoc(doc(lafleur(), 'offers/offer-carottes'), { share }))
    }
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
  const orderPath = 'groupOrders/order-1'
  const order = { id: 'order-1', groupId: 'group-parc-extension', offerId: 'offer-carottes', currentTierIndex: null, pickupSlots: [] }

  // Comme FirestoreGroupOrderRepository.setShare (B-019) : la part et les compteurs de la commande
  // sont écrits dans la même transaction. Un lot (batch) est évalué pareil par les règles.
  const setShare = (db: Firestore, quantity: number, committedHouseholds: number, extra: Record<string, unknown> = {}) => {
    const batch = writeBatch(db)
    if (quantity > 0) {
      batch.set(doc(db, sharePath), { ...share, quantity, updatedAt: Timestamp.now(), ...extra })
    } else {
      batch.delete(doc(db, sharePath))
    }
    batch.set(doc(db, orderPath), { ...order, status: 'open', committedShares: quantity, committedHouseholds })
    return batch.commit()
  }

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'groups/group-parc-extension/members/household-amina'), { householdId: 'household-amina', role: 'member', joinedAt: serverTimestamp() })
    })
  })

  test('le ménage réserve sa part', async () => {
    // Seule, sans mettre à jour la commande : refusée.
    await assertFails(setDoc(doc(amina(), sharePath), share))
    await assertSucceeds(setShare(amina(), 2, 1))
  })
  test('pas une part déjà payée', async () => { await assertFails(setDoc(doc(amina(), sharePath), { ...share, isPaid: true })) })
  test('pas de subvention auto-attribuée', async () => { await assertFails(setDoc(doc(amina(), sharePath), { ...share, subsidyCents: 500 })) })
  test('pas la part d’un autre ménage', async () => { await assertFails(setShare(intruder(), 2, 1)) })
  test('pas sur une commande fermée', async () => {
    await assertFails(setDoc(doc(amina(), 'groupOrders/order-closed/shares/household-amina'), share))
  })
  test('change la quantité, pas le paiement', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), sharePath), share)
      await setDoc(doc(c.firestore(), orderPath), { ...order, status: 'open', committedShares: 2, committedHouseholds: 1 })
    })
    await assertSucceeds(setShare(amina(), 3, 1))
    await assertFails(updateDoc(doc(amina(), sharePath), { isPaid: true }))
    await assertFails(getDoc(doc(intruder(), sharePath)))
    await assertSucceeds(setShare(amina(), 0, 0))
  })
  test('le ménage copie son nom dans sa part (pour l’hôte), 80 caractères au plus', async () => {
    await assertFails(setShare(amina(), 2, 1, { householdName: 'x'.repeat(81) }))
    await assertFails(setShare(amina(), 2, 1, { householdName: '' }))
    await assertFails(setShare(amina(), 2, 1, { householdName: 42 }))
    await assertSucceeds(setShare(amina(), 2, 1, { householdName: 'Famille Benali' }))
  })
  test('une ancienne part reçoit le nom au prochain changement de quantité', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), sharePath), share)
      await setDoc(doc(c.firestore(), orderPath), { ...order, status: 'open', committedShares: 2, committedHouseholds: 1 })
    })
    const db = amina()
    const batch = writeBatch(db)
    batch.update(doc(db, sharePath), { quantity: 3, updatedAt: Timestamp.now(), householdName: 'Famille Benali' })
    batch.update(doc(db, orderPath), { committedShares: 3 })
    await assertSucceeds(batch.commit())
    // Un autre ménage ne renomme pas la part.
    await assertFails(updateDoc(doc(intruder(), sharePath), { householdName: 'Intrus' }))
  })
})

describe('arrivée de la livraison (closed → delivered)', () => {
  const orderPath = 'groupOrders/order-arrivee'
  const arrivedOrder = {
    id: 'order-arrivee', groupId: 'group-arrivee', offerId: 'offer-carottes', status: 'closed', currentTierIndex: 0,
    committedShares: 12, committedHouseholds: 3, pickupPointId: 'pickup-arrivee', pickupSlots: []
  }
  const as = (uid: string) => env.authenticatedContext(uid).firestore()
  const arrived = (extra: Record<string, unknown> = {}) => ({ status: 'delivered', deliveredAt: serverTimestamp(), ...extra })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, 'users/coordo'), { ...aminaUser, id: 'coordo', displayName: 'Coordo', householdId: 'household-coordo' })
      await setDoc(doc(db, 'users/hote'), { ...aminaUser, id: 'hote', displayName: 'Hôte', householdId: null })
      await setDoc(doc(db, 'users/membre'), { ...aminaUser, id: 'membre', displayName: 'Membre', householdId: 'household-membre' })
      await setDoc(doc(db, 'users/vendeur-autre'), { ...aminaUser, id: 'vendeur-autre', displayName: 'Autre', roles: ['vendor'], householdId: null, vendorId: 'vendor-autre' })
      await setDoc(doc(db, 'households/household-coordo'), { id: 'household-coordo', name: 'Famille Coordo', size: 2, geohash: '', userIds: ['coordo'] })
      await setDoc(doc(db, 'households/household-membre'), { id: 'household-membre', name: 'Famille Membre', size: 2, geohash: '', userIds: ['membre'] })
      await setDoc(doc(db, 'groups/group-arrivee'), { id: 'group-arrivee', name: 'Arrivée', isPublic: true, inviteCode: 'ARRI', householdCount: 2, coordinatorIds: ['coordo'] })
      await setDoc(doc(db, 'groups/group-arrivee/members/household-coordo'), { householdId: 'household-coordo', role: 'coordinator', joinedAt: serverTimestamp() })
      await setDoc(doc(db, 'groups/group-arrivee/members/household-membre'), { householdId: 'household-membre', role: 'member', joinedAt: serverTimestamp() })
      await setDoc(doc(db, 'pickupPoints/pickup-arrivee'), { id: 'pickup-arrivee', hostUserId: 'hote', name: 'Chez l’hôte', address: '2 rue', capacity: 20, accessibility: [], slots: [] })
      await setDoc(doc(db, orderPath), arrivedOrder)
    })
  })

  const withStatus = async (status: string) => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), orderPath), { status })
    })
  }

  test('le coordonnateur du groupe marque la livraison arrivée (heure du serveur)', async () => {
    await assertSucceeds(updateDoc(doc(as('coordo'), orderPath), arrived()))
  })
  test('l’hôte du point de la commande la marque arrivée, avec ou sans deliveredAt', async () => {
    await assertSucceeds(updateDoc(doc(as('hote'), orderPath), { status: 'delivered' }))
  })
  test('un simple membre du groupe ne la marque pas arrivée', async () => {
    await assertFails(updateDoc(doc(as('membre'), orderPath), arrived()))
  })
  test('le vendeur d’un autre lot, ni un inconnu, ne la marquent pas arrivée', async () => {
    await assertFails(updateDoc(doc(as('vendeur-autre'), orderPath), arrived()))
    await assertFails(updateDoc(doc(intruder(), orderPath), arrived()))
    await assertFails(updateDoc(doc(anonymous(), orderPath), arrived()))
  })
  test('l’hôte d’un autre point ne la marque pas arrivée', async () => {
    // amina est l’hôte de pickup-1, pas du point de cette commande.
    await assertFails(updateDoc(doc(amina(), orderPath), arrived()))
  })
  test('seulement depuis une commande fermée (pas ouverte, palier atteint ou annulée)', async () => {
    for (const status of ['open', 'reached', 'cancelled']) {
      await withStatus(status)
      await assertFails(updateDoc(doc(as('coordo'), orderPath), arrived()))
      await assertFails(updateDoc(doc(as('hote'), orderPath), arrived()))
    }
  })
  test('pas de retour en arrière ni de deuxième arrivée', async () => {
    await withStatus('delivered')
    await assertFails(updateDoc(doc(as('coordo'), orderPath), { status: 'closed' }))
    await assertFails(updateDoc(doc(as('coordo'), orderPath), arrived()))
  })
  test('rien d’autre ne bouge avec l’arrivée', async () => {
    await assertFails(updateDoc(doc(as('coordo'), orderPath), arrived({ committedShares: 40 })))
    await assertFails(updateDoc(doc(as('hote'), orderPath), arrived({ pickupPointId: 'pickup-1' })))
    await assertFails(updateDoc(doc(as('coordo'), orderPath), arrived({ currentTierIndex: null })))
    await assertFails(updateDoc(doc(as('coordo'), orderPath), { status: 'cancelled' }))
  })
  test('deliveredAt est l’heure du serveur, pas une date choisie', async () => {
    await assertFails(updateDoc(doc(as('coordo'), orderPath), arrived({ deliveredAt: Timestamp.fromMillis(Date.now() - 86_400_000) })))
    await assertFails(updateDoc(doc(as('coordo'), orderPath), arrived({ deliveredAt: 'hier' })))
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

describe('images en bytes (T-132, Q-033)', () => {
  const jpeg = (size: number) => Bytes.fromUint8Array(new Uint8Array(size).fill(0xff))
  const media = (size = 2048) => ({ data: jpeg(size), contentType: 'image/jpeg', width: 256, height: 256, updatedAt: serverTimestamp() })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'groups/group-media'), {
        id: 'group-media', name: 'Groupe photo', isPublic: true, inviteCode: 'PHOTO', householdCount: 1, coordinatorIds: ['amina']
      })
    })
  })

  test('écrit son avatar', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'users/amina/media/avatar'), media()))
  })
  test('pose photoUpdatedAt sur son profil', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'users/amina'), { photoUpdatedAt: serverTimestamp() }))
  })
  test('n’écrit pas l’avatar d’un autre', async () => {
    await assertFails(setDoc(doc(intruder(), 'users/amina/media/avatar'), media()))
  })
  test('refuse un autre id que avatar', async () => {
    await assertFails(setDoc(doc(amina(), 'users/amina/media/galerie'), media()))
  })
  test('refuse une image de plus de 300 Kio', async () => {
    await assertFails(setDoc(doc(amina(), 'users/amina/media/avatar'), media(300 * 1024 + 1)))
  })
  test('refuse un autre format que JPEG', async () => {
    await assertFails(setDoc(doc(amina(), 'users/amina/media/avatar'), { ...media(), contentType: 'image/png' }))
  })
  test('refuse un champ en trop', async () => {
    await assertFails(setDoc(doc(amina(), 'users/amina/media/avatar'), { ...media(), owner: 'amina' }))
  })
  test('refuse une date choisie par le client', async () => {
    await assertFails(setDoc(doc(amina(), 'users/amina/media/avatar'), { ...media(), updatedAt: Timestamp.fromMillis(0) }))
  })
  test('l’hôte écrit la photo de son point de cueillette', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'pickupPoints/pickup-1/media/photo'), media()))
  })
  test('personne d’autre n’écrit la photo du point', async () => {
    await assertFails(setDoc(doc(intruder(), 'pickupPoints/pickup-1/media/photo'), media()))
    await assertFails(setDoc(doc(amina(), 'pickupPoints/pickup-1/media/galerie'), media()))
    await assertFails(setDoc(doc(amina(), 'pickupPoints/pickup-inconnu/media/photo'), media()))
  })
  test('un connecté lit un avatar, un anonyme non', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users/amina/media/avatar'), { ...media(), updatedAt: Timestamp.now() })
    })
    await assertSucceeds(getDoc(doc(intruder(), 'users/amina/media/avatar')))
    await assertFails(getDoc(doc(anonymous(), 'users/amina/media/avatar')))
  })
  for (const path of ['households/household-amina/media/photo', 'organizations/org-cdn/media/logo']) {
    test(`T-205 : un connecté lit ${path}, un anonyme non, personne ne l’écrit`, async () => {
      await env.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), path), { ...media(), updatedAt: Timestamp.now() })
      })
      await assertSucceeds(getDoc(doc(intruder(), path)))
      await assertFails(getDoc(doc(anonymous(), path)))
      await assertFails(setDoc(doc(amina(), path), media()))
      await assertFails(deleteDoc(doc(amina(), path)))
    })
  }
  test('supprime son avatar, pas celui d’un autre', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users/amina/media/avatar'), { ...media(), updatedAt: Timestamp.now() })
    })
    await assertFails(deleteDoc(doc(intruder(), 'users/amina/media/avatar')))
    await assertSucceeds(deleteDoc(doc(amina(), 'users/amina/media/avatar')))
  })
  test('le coordonnateur écrit la photo et la bannière du groupe', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'groups/group-media/media/photo'), media()))
    await assertSucceeds(setDoc(doc(amina(), 'groups/group-media/media/banner'), { ...media(), width: 1200, height: 400 }))
  })
  test('un non-coordonnateur n’écrit pas la photo du groupe', async () => {
    await assertFails(setDoc(doc(intruder(), 'groups/group-media/media/photo'), media()))
  })
  test('refuse un autre id que photo ou banner', async () => {
    await assertFails(setDoc(doc(amina(), 'groups/group-media/media/logo'), media()))
  })
  test('le coordonnateur pose photoUpdatedAt et bannerUpdatedAt', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'groups/group-media'), { photoUpdatedAt: serverTimestamp(), bannerUpdatedAt: serverTimestamp() }))
  })
  test('le coordonnateur ne change rien d’autre sur le groupe', async () => {
    await assertFails(updateDoc(doc(amina(), 'groups/group-media'), { photoUpdatedAt: serverTimestamp(), name: 'Renommé' }))
  })
  test('un non-coordonnateur ne pose pas photoUpdatedAt', async () => {
    await assertFails(updateDoc(doc(intruder(), 'groups/group-media'), { photoUpdatedAt: serverTimestamp() }))
  })
})

describe('marque du groupe (B-036, T-152)', () => {
  const branding = {
    displayName: 'Les Voisins de Parc-Ex', emblem: 'leaf.fill',
    accentLight: '#1E6B52', accentDark: '#7FD1AE', welcomeMessage: 'Bienvenue, voisin !'
  }

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'groups/group-brand'), {
        id: 'group-brand', name: 'Groupe marque', isPublic: true, inviteCode: 'BRAND', householdCount: 1, coordinatorIds: ['amina']
      })
    })
  })

  test('le coordonnateur change la marque', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'groups/group-brand'), { branding }))
  })
  test('le coordonnateur revient à la marque par défaut (objet vide)', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'groups/group-brand'), { branding: {} }))
  })
  test('un non-coordonnateur ne change pas la marque', async () => {
    await assertFails(updateDoc(doc(intruder(), 'groups/group-brand'), { branding }))
  })
  test('la marque ne passe pas avec un autre champ', async () => {
    await assertFails(updateDoc(doc(amina(), 'groups/group-brand'), { branding, name: 'Renommé' }))
  })
  test('refuse un champ inconnu dans la marque', async () => {
    await assertFails(updateDoc(doc(amina(), 'groups/group-brand'), { branding: { ...branding, logoURL: 'https://x' } }))
  })
  test('refuse un accent qui n’est pas #RRGGBB', async () => {
    await assertFails(updateDoc(doc(amina(), 'groups/group-brand'), { branding: { accentLight: 'vert' } }))
  })
  test('refuse un nom trop long', async () => {
    await assertFails(updateDoc(doc(amina(), 'groups/group-brand'), { branding: { displayName: 'x'.repeat(41) } }))
  })
})

describe('point de cueillette seedé (T-144)', () => {
  const seeded = {
    id: 'pickup-seed', groupId: 'group-parc-extension', neighborhood: 'parc-extension', hostUserId: 'amina',
    name: 'Sous-sol de l’église', address: '7495, rue Saint-Roch', latitude: 45.5302, longitude: -73.6305,
    geohash: 'f25eh2', capacity: 40, accessibility: ['stepFree'], slots: []
  }
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), 'pickupPoints/pickup-seed'), seeded) })
  })

  test('l’hôte modifie un point seedé (capacité, créneaux)', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'pickupPoints/pickup-seed'), { capacity: 30, slots: [] }))
  })
  test('l’hôte réenregistre le point entier (merge de l’app)', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'pickupPoints/pickup-seed'), { ...seeded, name: 'Église Saint-Roch' }, { merge: true }))
  })
  test('l’hôte ajuste la position', async () => {
    await assertSucceeds(updateDoc(doc(amina(), 'pickupPoints/pickup-seed'), { latitude: 45.531, longitude: -73.63, geohash: 'f25eh3' }))
  })
  test('pas de latitude hors bornes', async () => {
    await assertFails(updateDoc(doc(amina(), 'pickupPoints/pickup-seed'), { latitude: 120 }))
  })
  test('le groupe et le quartier ne changent pas', async () => {
    await assertFails(updateDoc(doc(amina(), 'pickupPoints/pickup-seed'), { groupId: 'group-autre' }))
    await assertFails(updateDoc(doc(amina(), 'pickupPoints/pickup-seed'), { neighborhood: 'verdun' }))
  })
  test('un autre utilisateur ne modifie pas le point', async () => {
    await assertFails(updateDoc(doc(intruder(), 'pickupPoints/pickup-seed'), { capacity: 1 }))
  })
  test('refuse toujours un champ inconnu', async () => {
    await assertFails(updateDoc(doc(amina(), 'pickupPoints/pickup-seed'), { secret: 'x' }))
  })
})

// B-056 : groupes publics ou privés, invitations à usage unique (groupInvitations/{code}).
describe('groupes privés et invitations (B-056)', () => {
  const privatePath = 'groups/group-prive'
  const invitation = (code: string, extra: object = {}) => ({
    code, groupId: 'group-prive', createdBy: 'amina', createdAt: Timestamp.now(), ...extra
  })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, privatePath), {
        id: 'group-prive', name: 'Cuisine collective', isPublic: false, inviteCode: '',
        coordinatorIds: ['amina'], createdBy: 'amina', householdCount: 1
      })
      // Ancien document sans `isPublic` : public.
      await setDoc(doc(db, 'groups/group-ancien'), { id: 'group-ancien', name: 'Ancien', householdCount: 0 })
      await setDoc(doc(db, 'groupInvitations/ABC234'), invitation('ABC234'))
      await setDoc(doc(db, 'groupInvitations/USED22'), invitation('USED22', { usedBy: 'household-amina', usedAt: Timestamp.now() }))
      await setDoc(doc(db, 'groupInvitations/REVOK2'), invitation('REVOK2', { revokedAt: Timestamp.now() }))
      await setDoc(doc(db, 'groupInvitations/OTHER2'), { ...invitation('OTHER2'), groupId: 'group-parc-extension' })
    })
  })

  // Ce que fait FirestoreGroupRepository.consume : adhésion qui nomme l'invitation, compteur, invitation utilisée.
  function joinWithInvitation(db: Firestore, code: string | null, groupPath = privatePath, consume = true) {
    const batch = writeBatch(db)
    const member: Record<string, unknown> = { householdId: 'household-intrus', role: 'member', joinedAt: serverTimestamp(), userId: 'intrus' }
    if (code) member.invitationCode = code
    batch.set(doc(db, `${groupPath}/members/household-intrus`), member)
    batch.update(doc(db, groupPath), { householdCount: increment(1), lastMembershipChange: 'household-intrus' })
    if (code && consume) batch.update(doc(db, `groupInvitations/${code}`), { usedBy: 'household-intrus', usedAt: serverTimestamp() })
    return batch.commit()
  }
  async function invitationData(code: string) {
    let data: Record<string, unknown> | undefined
    await env.withSecurityRulesDisabled(async (c) => { data = (await getDoc(doc(c.firestore(), `groupInvitations/${code}`))).data() })
    return data
  }

  test('un groupe privé se lit par son id, mais n’est jamais listé', async () => {
    await assertSucceeds(getDoc(doc(intruder(), privatePath)))
    await assertSucceeds(getDocs(query(collection(intruder(), 'groups'), where('isPublic', '==', true))))
    await assertFails(getDocs(collection(intruder(), 'groups')))
  })

  test('le créateur change la visibilité, et rien d’autre', async () => {
    await assertSucceeds(updateDoc(doc(amina(), privatePath), { isPublic: true }))
    await assertSucceeds(updateDoc(doc(amina(), privatePath), { isPublic: false }))
    await assertFails(updateDoc(doc(amina(), privatePath), { isPublic: 'oui' }))
    await assertFails(updateDoc(doc(amina(), privatePath), { isPublic: true, name: 'Renommé' }))
    await assertFails(updateDoc(doc(intruder(), privatePath), { isPublic: true }))
    // Sans `createdBy` ni coordonnateur : personne.
    await assertFails(updateDoc(doc(amina(), 'groups/group-parc-extension'), { isPublic: false }))
  })

  test('sans `createdBy`, le premier coordonnateur est le créateur', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'groups/group-coord'), { id: 'group-coord', name: 'x', isPublic: true, coordinatorIds: ['amina', 'intrus'] })
    })
    await assertSucceeds(updateDoc(doc(amina(), 'groups/group-coord'), { isPublic: false }))
    await assertFails(updateDoc(doc(intruder(), 'groups/group-coord'), { isPublic: true }))
  })

  test('seul le créateur crée une invitation, au bon format', async () => {
    const fresh = { code: 'NEW234', groupId: 'group-prive', createdBy: 'amina', createdAt: serverTimestamp() }
    await assertSucceeds(setDoc(doc(amina(), 'groupInvitations/NEW234'), fresh))
    await assertFails(setDoc(doc(intruder(), 'groupInvitations/NEW235'), { ...fresh, code: 'NEW235', createdBy: 'intrus' }))
    await assertFails(setDoc(doc(amina(), 'groupInvitations/NEW236'), { ...fresh }))
    await assertFails(setDoc(doc(amina(), 'groupInvitations/new237'), { ...fresh, code: 'new237' }))
    await assertFails(setDoc(doc(amina(), 'groupInvitations/NEW238'), { ...fresh, code: 'NEW238', createdAt: Timestamp.fromMillis(0) }))
    await assertFails(setDoc(doc(amina(), 'groupInvitations/NEW239'), { ...fresh, code: 'NEW239', usedBy: 'household-amina' }))
    // Une invitation existante ne s'écrase pas.
    await assertFails(setDoc(doc(amina(), 'groupInvitations/USED22'), { ...fresh, code: 'USED22' }))
  })

  test('le créateur liste ses invitations ; personne d’autre', async () => {
    await assertSucceeds(getDocs(query(collection(amina(), 'groupInvitations'),
      where('groupId', '==', 'group-prive'), where('createdBy', '==', 'amina'))))
    await assertFails(getDocs(query(collection(intruder(), 'groupInvitations'), where('createdBy', '==', 'amina'))))
    await assertFails(getDocs(collection(amina(), 'groupInvitations')))
    // Qui a reçu un code le lit.
    await assertSucceeds(getDoc(doc(intruder(), 'groupInvitations/ABC234')))
    await assertFails(getDoc(doc(anonymous(), 'groupInvitations/ABC234')))
  })

  test('le créateur révoque une invitation pas encore utilisée', async () => {
    await assertFails(updateDoc(doc(intruder(), 'groupInvitations/ABC234'), { revokedAt: serverTimestamp() }))
    await assertFails(updateDoc(doc(amina(), 'groupInvitations/ABC234'), { revokedAt: Timestamp.fromMillis(0) }))
    await assertFails(updateDoc(doc(amina(), 'groupInvitations/USED22'), { revokedAt: serverTimestamp() }))
    await assertSucceeds(updateDoc(doc(amina(), 'groupInvitations/ABC234'), { revokedAt: serverTimestamp() }))
    await assertFails(deleteDoc(doc(amina(), 'groupInvitations/ABC234')))
  })

  test('une invitation valide fait entrer dans le groupe privé et sert une seule fois', async () => {
    await assertSucceeds(joinWithInvitation(intruder(), 'ABC234'))
    const used = await invitationData('ABC234')
    assert.equal(used?.usedBy, 'household-intrus')
    // Le ménage repart, puis essaie de revenir avec la même invitation.
    // Une seule instance Firestore pour tout le lot (sinon « different Firestore instance »).
    const db = intruder()
    const leave = writeBatch(db)
    leave.delete(doc(db, `${privatePath}/members/household-intrus`))
    leave.update(doc(db, privatePath), { householdCount: increment(-1), lastMembershipChange: 'household-intrus' })
    await assertSucceeds(leave.commit())
    await assertFails(joinWithInvitation(intruder(), 'ABC234'))
  })

  test('pas d’entrée dans un groupe privé sans invitation valide', async () => {
    await assertFails(joinWithInvitation(intruder(), null))
    await assertFails(joinWithInvitation(intruder(), 'USED22'))
    await assertFails(joinWithInvitation(intruder(), 'REVOK2'))
    await assertFails(joinWithInvitation(intruder(), 'OTHER2'))
    await assertFails(joinWithInvitation(intruder(), 'NOPE22'))
    // L'adhésion nomme l'invitation mais ne la consomme pas : refusé.
    await assertFails(joinWithInvitation(intruder(), 'ABC234', privatePath, false))
  })

  test('une invitation ne se consomme pas sans l’adhésion qui la nomme', async () => {
    await assertFails(updateDoc(doc(intruder(), 'groupInvitations/ABC234'), { usedBy: 'household-intrus', usedAt: serverTimestamp() }))
    // Au nom d'un autre ménage : refusé.
    await assertFails(updateDoc(doc(intruder(), 'groupInvitations/ABC234'), { usedBy: 'household-amina', usedAt: serverTimestamp() }))
  })

  test('un groupe sans `isPublic` reste public : on y entre sans invitation', async () => {
    await assertSucceeds(joinWithInvitation(intruder(), null, 'groups/group-ancien'))
  })
})

describe('créer un groupe depuis l’app (B-059)', () => {
  const groupPath = 'groups/group-jarry'
  const group = (overrides: Record<string, unknown> = {}) => ({
    name: 'Voisins de la rue Jarry', neighborhood: 'villeray', centerGeohash: 'f25dvk7', radiusMeters: 1500,
    coordinatorIds: ['amina'], householdCount: 1, isPublic: true, inviteCode: 'JRY234', createdBy: 'amina',
    createdAt: serverTimestamp(), lastMembershipChange: 'household-amina', ...overrides
  })
  const coordinator = (overrides: Record<string, unknown> = {}) => ({
    householdId: 'household-amina', role: 'coordinator', joinedAt: serverTimestamp(), userId: 'amina', ...overrides
  })

  // Ce que fait FirestoreGroupRepository.createGroup : groupe et adhésion du ménage créateur dans un seul batch.
  function createBatch(db: Firestore, groupData: object = group(), memberData: object | null = coordinator(),
                       householdId = 'household-amina') {
    const batch = writeBatch(db)
    batch.set(doc(db, groupPath), groupData)
    if (memberData) batch.set(doc(db, `${groupPath}/members/${householdId}`), memberData)
    return batch.commit()
  }

  test('le groupe et son premier membre coordonnateur se créent ensemble', async () => {
    await assertSucceeds(createBatch(amina()))
    let data: Record<string, unknown> | undefined
    await env.withSecurityRulesDisabled(async (c) => { data = (await getDoc(doc(c.firestore(), groupPath))).data() })
    assert.equal(data?.householdCount, 1)
    assert.equal(data?.createdBy, 'amina')
  })

  test('le premier membre sans userId, ou avec l’uid d’un autre : refusé (T-193)', async () => {
    const { userId: _userId, ...withoutUserId } = coordinator()
    await assertFails(createBatch(amina(), group(), withoutUserId))
    await assertFails(createBatch(amina(), group(), coordinator({ userId: 'intrus' })))
  })

  test('un groupe privé se crée aussi', async () => {
    await assertSucceeds(createBatch(amina(), group({ isPublic: false })))
  })

  test('sans l’adhésion du créateur, le groupe est refusé', async () => {
    await assertFails(createBatch(amina(), group(), null))
    await assertFails(createBatch(amina(), group(), coordinator({ role: 'member' })))
  })

  test('on ne crée pas un groupe au nom de quelqu’un d’autre', async () => {
    await assertFails(createBatch(amina(), group({ createdBy: 'intrus' })))
    await assertFails(createBatch(amina(), group({ coordinatorIds: ['amina', 'intrus'] })))
    // Ménage dont la personne ne fait pas partie.
    const db = intruder()
    await assertFails(createBatch(db, group({ createdBy: 'intrus', coordinatorIds: ['intrus'] }), coordinator()))
  })

  test('les champs sont validés', async () => {
    const db = amina()
    await assertFails(createBatch(db, group({ householdCount: 5 })))
    await assertFails(createBatch(db, group({ radiusMeters: 500 })))
    await assertFails(createBatch(db, group({ radiusMeters: 2500 })))
    await assertFails(createBatch(db, group({ name: 'A' })))
    await assertFails(createBatch(db, group({ centerGeohash: 'pas un geohash!' })))
    await assertFails(createBatch(db, group({ inviteCode: 'abc' })))
    await assertFails(createBatch(db, group({ isPublic: 'oui' })))
    await assertFails(createBatch(db, group({ createdAt: Timestamp.fromMillis(0) })))
    await assertFails(createBatch(db, group({ branding: { displayName: 'x' } })))
  })

  test('l’adhésion coordonnateur ne sert qu’à la création', async () => {
    await assertSucceeds(createBatch(amina()))
    // Le groupe existe : un nouveau membre ne peut pas s’écrire coordonnateur.
    const db = intruder()
    const batch = writeBatch(db)
    batch.set(doc(db, `${groupPath}/members/household-intrus`), coordinator({ householdId: 'household-intrus' }))
    batch.update(doc(db, groupPath), { householdCount: increment(1), lastMembershipChange: 'household-intrus' })
    await assertFails(batch.commit())
    // Ni écraser un groupe existant.
    await assertFails(createBatch(amina()))
  })
})

describe('vendorReviews (T-157)', () => {
  const reviewId = 'vendor-lafleur_household-amina'
  const review = (overrides: Record<string, unknown> = {}) => ({
    id: reviewId, vendorId: 'vendor-lafleur', householdId: 'household-amina', authorName: 'Amina B.', rating: 5,
    comment: 'Carottes très fraîches', groupOrderId: 'order-livree',
    createdAt: Timestamp.fromMillis(Date.now()), updatedAt: Timestamp.fromMillis(Date.now()), ...overrides
  })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore()
      await setDoc(doc(db, 'offers/offer-autre'), { ...offer, id: 'offer-autre', vendorId: 'vendor-autre' })
      const order = { groupId: 'group-parc-extension', offerId: 'offer-carottes', committedShares: 2, committedHouseholds: 1, pickupSlots: [] }
      await setDoc(doc(db, 'groupOrders/order-livree'), { ...order, id: 'order-livree', status: 'delivered' })
      await setDoc(doc(db, 'groupOrders/order-livree/shares/household-amina'), share)
      await setDoc(doc(db, 'groupOrders/order-cueillie'), { ...order, id: 'order-cueillie', status: 'closed' })
      await setDoc(doc(db, 'groupOrders/order-cueillie/shares/household-amina'), { ...share, isPickedUp: true })
      await setDoc(doc(db, 'groupOrders/order-attente'), { ...order, id: 'order-attente', status: 'closed' })
      await setDoc(doc(db, 'groupOrders/order-attente/shares/household-amina'), share)
      await setDoc(doc(db, 'groupOrders/order-sans-moi'), { ...order, id: 'order-sans-moi', status: 'delivered' })
      await setDoc(doc(db, 'groupOrders/order-autre-vendeur'), { ...order, id: 'order-autre-vendeur', offerId: 'offer-autre', status: 'delivered' })
      await setDoc(doc(db, 'groupOrders/order-autre-vendeur/shares/household-amina'), share)
      await setDoc(doc(db, 'vendorReviews/vendor-lafleur_household-tremblay'), {
        ...review(), id: 'vendor-lafleur_household-tremblay', householdId: 'household-tremblay', authorName: 'Julie T.'
      })
    })
  })

  test('connecté lit les avis d’un producteur', async () => {
    await assertSucceeds(getDocs(query(collection(intruder(), 'vendorReviews'), where('vendorId', '==', 'vendor-lafleur'))))
  })
  test('anonyme ne lit pas les avis', async () => {
    await assertFails(getDoc(doc(anonymous(), 'vendorReviews/vendor-lafleur_household-tremblay')))
  })
  test('le ménage qui a reçu le lot laisse un avis', async () => {
    await assertSucceeds(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review()))
  })
  test('sans commentaire, c’est permis', async () => {
    const { comment: _comment, ...withoutComment } = review()
    await assertSucceeds(setDoc(doc(amina(), `vendorReviews/${reviewId}`), withoutComment))
  })
  test('part cueillie d’une commande close : éligible', async () => {
    await assertSucceeds(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ groupOrderId: 'order-cueillie' })))
  })
  test('lot pas encore reçu : refusé', async () => {
    await assertFails(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ groupOrderId: 'order-attente' })))
  })
  test('commande livrée sans part du ménage : refusé', async () => {
    await assertFails(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ groupOrderId: 'order-sans-moi' })))
  })
  test('lot d’un autre producteur : refusé', async () => {
    await assertFails(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ groupOrderId: 'order-autre-vendeur' })))
  })
  test('commande inconnue : refusé', async () => {
    await assertFails(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ groupOrderId: 'order-fantome' })))
  })
  for (const rating of [0, 6, 4.5, '5']) {
    test(`note ${JSON.stringify(rating)} refusée`, async () => {
      await assertFails(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ rating })))
    })
  }
  test('commentaire de plus de 500 caractères refusé', async () => {
    await assertFails(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ comment: 'x'.repeat(501) })))
  })
  test('champ inconnu refusé', async () => {
    await assertFails(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review({ isVerified: true })))
  })
  test('un seul avis par ménage : id libre refusé', async () => {
    await assertFails(setDoc(doc(amina(), 'vendorReviews/avis-2'), review({ id: 'avis-2' })))
  })
  test('un autre ne signe pas au nom du ménage', async () => {
    await assertFails(setDoc(doc(intruder(), `vendorReviews/${reviewId}`), review()))
  })
  test('le vendeur ne s’écrit pas d’avis', async () => {
    await assertFails(setDoc(doc(lafleur(), `vendorReviews/${reviewId}`), review()))
  })
  test('le ménage modifie sa note et son commentaire', async () => {
    await assertSucceeds(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review()))
    await assertSucceeds(updateDoc(doc(amina(), `vendorReviews/${reviewId}`), {
      rating: 3, comment: 'Finalement moyen', updatedAt: Timestamp.fromMillis(Date.now())
    }))
  })
  test('modification : note hors limites refusée', async () => {
    await assertSucceeds(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review()))
    await assertFails(updateDoc(doc(amina(), `vendorReviews/${reviewId}`), { rating: 9 }))
  })
  test('modification : commande ou date de création figées', async () => {
    await assertSucceeds(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review()))
    await assertFails(updateDoc(doc(amina(), `vendorReviews/${reviewId}`), { groupOrderId: 'order-cueillie' }))
    await assertFails(updateDoc(doc(amina(), `vendorReviews/${reviewId}`), { createdAt: Timestamp.fromMillis(0) }))
  })
  test('on ne modifie pas l’avis d’un autre ménage', async () => {
    await assertFails(updateDoc(doc(amina(), 'vendorReviews/vendor-lafleur_household-tremblay'), { rating: 1 }))
    await assertFails(deleteDoc(doc(amina(), 'vendorReviews/vendor-lafleur_household-tremblay')))
  })
  test('le ménage retire son avis', async () => {
    await assertSucceeds(setDoc(doc(amina(), `vendorReviews/${reviewId}`), review()))
    await assertSucceeds(deleteDoc(doc(amina(), `vendorReviews/${reviewId}`)))
  })
})

describe('onboarding producteur : créer son vendeur (T-158)', () => {
  const newVendor = (uid: string, overrides: Record<string, unknown> = {}) => ({
    id: `vendor-${uid}`, legalName: 'Ferme des Voisins', kind: 'farm',
    description: 'Légumes bio cultivés à Mirabel, paniers chaque semaine.', photoURLs: [],
    servedZones: ['f25d'], isVerified: false, ownerId: uid, productCategories: ['produce', 'eggs'],
    ...overrides
  })

  test('crée son vendeur non vérifié', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina')))
  })
  test('ne crée pas un vendeur sous un autre id', async () => {
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-x'), newVendor('amina', { id: 'vendor-x' })))
  })
  test('ne crée pas un vendeur pour un autre compte', async () => {
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-intrus'), newVendor('intrus')))
  })
  test('ne se pose pas propriétaire d’un vendeur au nom d’un autre', async () => {
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina', { ownerId: 'intrus' })))
  })
  test('ne se déclare pas vérifié', async () => {
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina', { isVerified: true })))
  })
  test('ne se donne pas de note', async () => {
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina', { averageRating: 5 })))
  })
  test('refuse un type inconnu ou un champ en trop', async () => {
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina', { kind: 'empire' })))
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina', { city: 'Mirabel' })))
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina', { productCategories: ['armes'] })))
  })
  test('anonyme ne crée pas de vendeur', async () => {
    await assertFails(setDoc(doc(anonymous(), 'vendors/vendor-amina'), newVendor('amina')))
  })
  test('un seul vendeur : recréer le sien est refusé', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina')))
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina', { legalName: 'Autre nom' })))
  })
  test('se rattache son vendeur, puis publie un produit', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina')))
    await assertSucceeds(updateDoc(doc(amina(), 'users/amina'), { vendorId: 'vendor-amina', roles: ['family', 'vendor'] }))
    await assertSucceeds(setDoc(doc(amina(), 'products/product-panier'),
      { ...product, id: 'product-panier', vendorId: 'vendor-amina' }))
  })
  test('vendeur et rattachement dans un même batch', async () => {
    const db = amina()
    const batch = writeBatch(db)
    batch.set(doc(db, 'vendors/vendor-amina'), newVendor('amina'))
    batch.update(doc(db, 'users/amina'), { vendorId: 'vendor-amina' })
    await assertSucceeds(batch.commit())
  })
  test('ne se rattache pas un vendeur qui n’existe pas', async () => {
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { vendorId: 'vendor-amina' }))
  })
  test('ne se rattache pas le vendeur d’un autre', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'vendors/vendor-intrus'), newVendor('intrus'))
    })
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { vendorId: 'vendor-intrus' }))
    await assertFails(updateDoc(doc(amina(), 'users/amina'), { vendorId: 'vendor-lafleur' }))
  })
  test('un vendeur déjà rattaché ne change pas de vendeur', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'vendors/vendor-lafleur2'), newVendor('lafleur', { id: 'vendor-lafleur2' }))
    })
    await assertFails(updateDoc(doc(lafleur(), 'users/lafleur'), { vendorId: 'vendor-lafleur2' }))
  })
  test('après la création, ne se rend pas vérifié ni ne se note', async () => {
    await assertSucceeds(setDoc(doc(amina(), 'vendors/vendor-amina'), newVendor('amina')))
    await assertSucceeds(updateDoc(doc(amina(), 'users/amina'), { vendorId: 'vendor-amina' }))
    await assertFails(updateDoc(doc(amina(), 'vendors/vendor-amina'), { isVerified: true }))
    await assertFails(updateDoc(doc(amina(), 'vendors/vendor-amina'), { averageRating: 5 }))
    await assertFails(updateDoc(doc(amina(), 'vendors/vendor-amina'), { ownerId: 'intrus' }))
    await assertSucceeds(updateDoc(doc(amina(), 'vendors/vendor-amina'), { description: 'Nouvelle description de la ferme.' }))
  })
})

describe('vitrine du vendeur (T-157)', () => {
  const photo = (size = 4096) => ({
    data: Bytes.fromUint8Array(new Uint8Array(size).fill(0xff)), contentType: 'image/jpeg', width: 1000, height: 750,
    updatedAt: serverTimestamp()
  })

  test('le vendeur choisit ses produits mis en avant', async () => {
    await assertSucceeds(updateDoc(doc(lafleur(), 'vendors/vendor-lafleur'), { featuredProductIds: ['product-carottes'] }))
  })
  test('au plus 6 produits mis en avant', async () => {
    await assertFails(updateDoc(doc(lafleur(), 'vendors/vendor-lafleur'), {
      featuredProductIds: ['a', 'b', 'c', 'd', 'e', 'f', 'g']
    }))
  })
  test('une famille ne change pas la vitrine d’un vendeur', async () => {
    await assertFails(updateDoc(doc(amina(), 'vendors/vendor-lafleur'), { featuredProductIds: [] }))
  })
  test('un autre vendeur ne change pas cette vitrine', async () => {
    await assertFails(updateDoc(doc(lafleur(), 'vendors/vendor-autre'), { featuredProductIds: [] }))
  })
  test('la note et la ville restent hors de portée du vendeur', async () => {
    await assertFails(updateDoc(doc(lafleur(), 'vendors/vendor-lafleur'), { averageRating: 5 }))
    await assertFails(updateDoc(doc(lafleur(), 'vendors/vendor-lafleur'), { city: 'Paris' }))
  })
  test('le vendeur ajoute une photo de vitrine', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), 'vendors/vendor-lafleur/media/photo-abc-123'), photo()))
  })
  test('connecté lit une photo de vitrine', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), 'vendors/vendor-lafleur/media/photo-abc'), photo()))
    await assertSucceeds(getDoc(doc(amina(), 'vendors/vendor-lafleur/media/photo-abc')))
  })
  test('nom de photo libre refusé', async () => {
    await assertFails(setDoc(doc(lafleur(), 'vendors/vendor-lafleur/media/avatar'), photo()))
  })
  test('photo trop lourde refusée', async () => {
    await assertFails(setDoc(doc(lafleur(), 'vendors/vendor-lafleur/media/photo-lourde'), photo(301 * 1024)))
  })
  test('une famille n’ajoute pas de photo à une vitrine', async () => {
    await assertFails(setDoc(doc(amina(), 'vendors/vendor-lafleur/media/photo-x'), photo()))
  })
  test('le vendeur retire sa photo, pas celle d’un autre', async () => {
    await assertSucceeds(setDoc(doc(lafleur(), 'vendors/vendor-lafleur/media/photo-x'), photo()))
    await assertSucceeds(deleteDoc(doc(lafleur(), 'vendors/vendor-lafleur/media/photo-x')))
    await assertFails(deleteDoc(doc(lafleur(), 'vendors/vendor-autre/media/photo-x')))
  })
})

describe('avis des familles sur un groupe (T-174)', () => {
  const groupPath = 'groups/group-parc-extension'
  const ratingPath = `${groupPath}/ratings/household-amina`
  const rating = (overrides: Record<string, unknown> = {}) => ({
    id: 'household-amina', groupId: 'group-parc-extension', householdId: 'household-amina', authorName: 'Amina B.',
    rating: 4, comment: 'Coordination au top', createdAt: Timestamp.fromMillis(Date.now()),
    updatedAt: Timestamp.fromMillis(Date.now()), ...overrides
  })

  // Ce que fait FirestoreGroupRepository.saveRating : avis + agrégats du groupe, ensemble.
  function rateBatch(db: Firestore, data: Record<string, unknown>, sumDelta: number, countDelta: number,
                     householdId = 'household-amina', path = ratingPath, isUpdate = false) {
    const batch = writeBatch(db)
    if (isUpdate) batch.update(doc(db, path), data)
    else batch.set(doc(db, path), data)
    batch.update(doc(db, groupPath), {
      ratingSum: increment(sumDelta), ratingCount: increment(countDelta), lastRatingChange: householdId
    })
    return batch.commit()
  }

  async function seedMember() {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `${groupPath}/members/household-amina`),
                   { householdId: 'household-amina', role: 'member', joinedAt: Timestamp.fromMillis(Date.now()) })
    })
  }

  async function seedExistingRating() {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore()
      await setDoc(doc(db, ratingPath), rating())
      await updateDoc(doc(db, groupPath), { ratingSum: 9, ratingCount: 2, lastRatingChange: 'household-tremblay' })
    })
  }

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore()
      const order = { groupId: 'group-parc-extension', offerId: 'offer-carottes', committedShares: 2, committedHouseholds: 1, pickupSlots: [] }
      await setDoc(doc(db, 'groupOrders/order-passee'), { ...order, id: 'order-passee', status: 'delivered' })
      await setDoc(doc(db, 'groupOrders/order-passee/shares/household-amina'), share)
      await setDoc(doc(db, 'groupOrders/order-ouverte-moi'), { ...order, id: 'order-ouverte-moi', status: 'open' })
      await setDoc(doc(db, 'groupOrders/order-ouverte-moi/shares/household-amina'), share)
      await setDoc(doc(db, 'groupOrders/order-sans-moi'), { ...order, id: 'order-sans-moi', status: 'delivered' })
      await setDoc(doc(db, 'groupOrders/order-autre-groupe'), { ...order, id: 'order-autre-groupe', groupId: 'group-ailleurs', status: 'delivered' })
      await setDoc(doc(db, 'groupOrders/order-autre-groupe/shares/household-amina'), share)
      await setDoc(doc(db, `${groupPath}/ratings/household-tremblay`), {
        ...rating(), id: 'household-tremblay', householdId: 'household-tremblay', authorName: 'Julie T.'
      })
    })
  })

  test('connecté lit les avis du groupe', async () => {
    await assertSucceeds(getDocs(collection(intruder(), `${groupPath}/ratings`)))
  })
  test('anonyme ne lit pas les avis', async () => {
    await assertFails(getDoc(doc(anonymous(), `${groupPath}/ratings/household-tremblay`)))
  })
  test('un membre note le groupe, agrégats tenus', async () => {
    await seedMember()
    await assertSucceeds(rateBatch(amina(), rating(), 4, 1))
  })
  test('le créateur du groupe ne note pas son propre groupe', async () => {
    await seedMember()
    await env.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), groupPath), { createdBy: 'amina' })
    })
    await assertFails(rateBatch(amina(), rating(), 4, 1))
  })
  test('sans commentaire, c’est permis', async () => {
    await seedMember()
    const { comment: _comment, ...withoutComment } = rating()
    await assertSucceeds(rateBatch(amina(), withoutComment, 4, 1))
  })
  test('ancien membre avec une part dans une commande livrée du groupe : permis', async () => {
    await assertSucceeds(rateBatch(amina(), rating({ groupOrderId: 'order-passee' }), 4, 1))
  })
  test('jamais membre, sans preuve : refusé', async () => {
    await assertFails(rateBatch(amina(), rating(), 4, 1))
  })
  test('preuve : commande encore ouverte : refusé', async () => {
    await assertFails(rateBatch(amina(), rating({ groupOrderId: 'order-ouverte-moi' }), 4, 1))
  })
  test('preuve : commande sans part du ménage : refusé', async () => {
    await assertFails(rateBatch(amina(), rating({ groupOrderId: 'order-sans-moi' }), 4, 1))
  })
  test('preuve : commande d’un autre groupe : refusé', async () => {
    await assertFails(rateBatch(amina(), rating({ groupOrderId: 'order-autre-groupe' }), 4, 1))
  })
  test('avis sans agrégats : refusé', async () => {
    await seedMember()
    await assertFails(setDoc(doc(amina(), ratingPath), rating()))
  })
  test('agrégats faussés (somme gonflée) : refusé', async () => {
    await seedMember()
    await assertFails(rateBatch(amina(), rating(), 50, 1))
  })
  test('agrégats faussés (compte gonflé) : refusé', async () => {
    await seedMember()
    await assertFails(rateBatch(amina(), rating(), 4, 3))
  })
  test('agrégats seuls, sans avis : refusé', async () => {
    await seedMember()
    await assertFails(updateDoc(doc(amina(), groupPath), {
      ratingSum: increment(5), ratingCount: increment(1), lastRatingChange: 'household-amina'
    }))
  })
  test('note hors 1…5 : refusé', async () => {
    await seedMember()
    await assertFails(rateBatch(amina(), rating({ rating: 6 }), 6, 1))
    await assertFails(rateBatch(amina(), rating({ rating: 0 }), 0, 1))
  })
  test('commentaire de plus de 280 caractères : refusé', async () => {
    await seedMember()
    await assertFails(rateBatch(amina(), rating({ comment: 'x'.repeat(281) }), 4, 1))
  })
  test('champ inconnu : refusé', async () => {
    await seedMember()
    await assertFails(rateBatch(amina(), rating({ isFeatured: true }), 4, 1))
  })
  test('noter au nom d’un autre ménage : refusé', async () => {
    await seedMember()
    const other = rating({ id: 'household-intrus', householdId: 'household-intrus' })
    await assertFails(rateBatch(amina(), other, 4, 1, 'household-intrus', `${groupPath}/ratings/household-intrus`))
  })
  test('un intrus ne note pas pour Amina', async () => {
    await seedMember()
    await assertFails(rateBatch(intruder(), rating(), 4, 1))
  })
  test('modifier sa note : écart exact sur la somme, compte inchangé', async () => {
    await seedMember()
    await seedExistingRating()
    const change = { rating: 2, comment: 'Plus pareil', updatedAt: Timestamp.fromMillis(Date.now()) }
    await assertSucceeds(rateBatch(amina(), change, -2, 0, 'household-amina', ratingPath, true))
  })
  test('modifier sa note après avoir quitté le groupe : permis', async () => {
    await seedExistingRating()
    const change = { rating: 5, updatedAt: Timestamp.fromMillis(Date.now()) }
    await assertSucceeds(rateBatch(amina(), change, 1, 0, 'household-amina', ratingPath, true))
  })
  test('modifier en recomptant un avis : refusé', async () => {
    await seedMember()
    await seedExistingRating()
    const change = { rating: 5, updatedAt: Timestamp.fromMillis(Date.now()) }
    await assertFails(rateBatch(amina(), change, 1, 1, 'household-amina', ratingPath, true))
  })
  test('modifier la date de création : refusé', async () => {
    await seedMember()
    await seedExistingRating()
    await assertFails(rateBatch(amina(), { createdAt: Timestamp.fromMillis(0) }, 0, 0, 'household-amina', ratingPath, true))
  })
  test('supprimer son avis : refusé (les agrégats ne dériveraient plus)', async () => {
    await seedExistingRating()
    await assertFails(deleteDoc(doc(amina(), ratingPath)))
  })
  test('le ménage lit sa propre part après avoir quitté le groupe, pas un intrus', async () => {
    await assertSucceeds(getDoc(doc(amina(), 'groupOrders/order-passee/shares/household-amina')))
    await assertFails(getDoc(doc(intruder(), 'groupOrders/order-passee/shares/household-amina')))
  })
})

// T-191 : le créateur du groupe (et lui seul) retire une famille ; jamais la sienne.
describe('groups/members : retrait d’une famille par le créateur (T-191)', () => {
  const groupPath = 'groups/group-retrait'
  const memberOf = (householdId: string) => `${groupPath}/members/${householdId}`
  const creator = () => env.authenticatedContext('createur').firestore()
  const coordinator = () => env.authenticatedContext('coord').firestore()
  const member = () => env.authenticatedContext('membre').firestore()

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      for (const [uid, household] of [['createur', 'household-createur'], ['coord', 'household-coord'], ['membre', 'household-membre'], ['lea', 'household-lea']]) {
        await setDoc(doc(db, `users/${uid}`), { ...aminaUser, id: uid, householdId: household })
        await setDoc(doc(db, `households/${household}`), { id: household, name: `Famille ${uid}`, size: 2, geohash: 'f25du', userIds: [uid] })
        await setDoc(doc(db, memberOf(household)), { householdId: household, role: uid === 'lea' || uid === 'membre' ? 'member' : 'coordinator', joinedAt: Timestamp.now() })
      }
      await setDoc(doc(db, groupPath), {
        id: 'group-retrait', name: 'Groupe retrait', isPublic: true, inviteCode: 'ABCDEF',
        createdBy: 'createur', coordinatorIds: ['createur', 'coord'], householdCount: 4
      })
    })
  })

  // Ce que fait FirestoreGroupRepository.removeHousehold : suppression de l'adhésion + compteur −1.
  function removeBatch(db: Firestore, householdId: string, delta = -1) {
    const batch = writeBatch(db)
    batch.delete(doc(db, memberOf(householdId)))
    batch.update(doc(db, groupPath), { householdCount: increment(delta), lastMembershipChange: householdId })
    return batch.commit()
  }
  async function memberExists(householdId: string) {
    let exists = false
    await env.withSecurityRulesDisabled(async (c) => { exists = (await getDoc(doc(c.firestore(), memberOf(householdId)))).exists() })
    return exists
  }

  test('le créateur retire une autre famille : adhésion supprimée et compteur −1', async () => {
    await assertSucceeds(removeBatch(creator(), 'household-lea'))
    assert.equal(await memberExists('household-lea'), false)
    await env.withSecurityRulesDisabled(async (c) => {
      assert.equal((await getDoc(doc(c.firestore(), groupPath))).data()?.householdCount, 3)
    })
  })
  test('un autre coordonnateur ne retire pas une famille', async () => {
    await assertFails(removeBatch(coordinator(), 'household-lea'))
    assert.equal(await memberExists('household-lea'), true)
  })
  test('un simple membre ne retire pas une famille', async () => {
    await assertFails(removeBatch(member(), 'household-lea'))
    assert.equal(await memberExists('household-lea'), true)
  })
  test('un étranger au groupe ne retire pas une famille', async () => {
    await assertFails(removeBatch(intruder(), 'household-lea'))
  })
  // Sa propre famille : ce n'est pas un « retrait » mais la sortie volontaire, déjà permise avant T-191
  // (inchangée). L'interdiction « jamais sa propre famille » du menu Retirer est portée par l'app
  // (GroupRules.canRemoveHousehold, testée côté Swift).
  test('le créateur qui sort sa propre famille passe par la sortie volontaire (inchangée)', async () => {
    await assertSucceeds(removeBatch(creator(), 'household-createur'))
    assert.equal(await memberExists('household-createur'), false)
  })
  test('pas de retrait sans le compteur, ni avec un compteur faussé', async () => {
    await assertFails(deleteDoc(doc(creator(), memberOf('household-lea'))))
    await assertFails(removeBatch(creator(), 'household-lea', -2))
    await assertFails(removeBatch(creator(), 'household-lea', 1))
  })
  test('la sortie volontaire d’un membre de son propre groupe reste permise', async () => {
    await assertSucceeds(removeBatch(member(), 'household-membre'))
    assert.equal(await memberExists('household-membre'), false)
  })
  test('un membre ne quitte pas au nom d’un autre ménage', async () => {
    await assertFails(removeBatch(member(), 'household-coord'))
  })
})

// T-193 : le créateur quitte son groupe et le confie à une famille encore membre.
describe('groups : passation du créateur qui quitte (T-193)', () => {
  const groupPath = 'groups/group-passation'
  const memberOf = (householdId: string) => `${groupPath}/members/${householdId}`
  const creator = () => env.authenticatedContext('createur').firestore()
  const coordinator = () => env.authenticatedContext('coord').firestore()
  const member = () => env.authenticatedContext('membre').firestore()

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      for (const [uid, household, role] of [['createur', 'household-createur', 'coordinator'], ['coord', 'household-coord', 'coordinator'],
                                            ['membre', 'household-membre', 'member'], ['etranger', 'household-etranger', 'member']]) {
        await setDoc(doc(db, `users/${uid}`), { ...aminaUser, id: uid, householdId: household })
        await setDoc(doc(db, `households/${household}`), { id: household, name: `Famille ${uid}`, size: 2, geohash: 'f25du', userIds: [uid] })
        // `etranger` a un ménage mais n'est PAS membre du groupe.
        if (uid !== 'etranger') {
          await setDoc(doc(db, memberOf(household)), { householdId: household, role, joinedAt: Timestamp.now(), userId: uid })
        }
      }
      await setDoc(doc(db, groupPath), {
        id: 'group-passation', name: 'Groupe passation', isPublic: true, inviteCode: 'ABCDEF',
        createdBy: 'createur', coordinatorIds: ['createur', 'coord'], householdCount: 3
      })
    })
  })

  // Ce que fait FirestoreGroupRepository.leave(…handingOverTo:) : adhésion du partant supprimée, héritier promu,
  // compteur −1, `createdBy` / `coordinatorIds` / `handoverHouseholdId` mis à jour, le tout en une écriture.
  function handoverBatch(db: Firestore, o: {
    leaver?: string, heirHousehold?: string, newOwner?: string, coordinatorIds?: string[], promote?: boolean, delta?: number,
    leave?: boolean
  } = {}) {
    const leaver = o.leaver ?? 'household-createur'
    const heirHousehold = o.heirHousehold ?? 'household-membre'
    const batch = writeBatch(db)
    if (o.leave !== false) batch.delete(doc(db, memberOf(leaver)))
    if (o.promote !== false) batch.update(doc(db, memberOf(heirHousehold)), { role: 'coordinator' })
    batch.update(doc(db, groupPath), {
      householdCount: increment(o.delta ?? -1), lastMembershipChange: leaver,
      createdBy: o.newOwner ?? 'membre', coordinatorIds: o.coordinatorIds ?? ['coord', 'membre'],
      handoverHouseholdId: heirHousehold
    })
    return batch.commit()
  }
  async function groupData() {
    let data: Record<string, unknown> | undefined
    await env.withSecurityRulesDisabled(async (c) => { data = (await getDoc(doc(c.firestore(), groupPath))).data() })
    return data
  }
  async function roleOf(householdId: string) {
    let role: unknown
    await env.withSecurityRulesDisabled(async (c) => { role = (await getDoc(doc(c.firestore(), memberOf(householdId)))).data()?.role })
    return role
  }

  test('passation valide : le créateur sort, l’héritier devient créateur et coordonnateur', async () => {
    await assertSucceeds(handoverBatch(creator()))
    const data = await groupData()
    assert.equal(data?.createdBy, 'membre')
    assert.deepEqual(data?.coordinatorIds, ['coord', 'membre'])
    assert.equal(data?.householdCount, 2)
    assert.equal(await roleOf('household-membre'), 'coordinator')
  })
  test('passation valide vers un coordonnateur déjà promu (sans toucher à son adhésion)', async () => {
    await assertSucceeds(handoverBatch(creator(), { heirHousehold: 'household-coord', newOwner: 'coord', promote: false, coordinatorIds: ['coord'] }))
    assert.equal((await groupData())?.createdBy, 'coord')
  })
  test('un non-créateur ne change pas createdBy, même en sortant', async () => {
    await assertFails(handoverBatch(coordinator(), { leaver: 'household-coord', heirHousehold: 'household-membre', newOwner: 'membre', coordinatorIds: ['createur', 'membre'] }))
    await assertFails(handoverBatch(member(), { leaver: 'household-membre', heirHousehold: 'household-coord', newOwner: 'coord', promote: false, coordinatorIds: ['createur', 'coord'] }))
    await assertFails(updateDoc(doc(member(), groupPath), { createdBy: 'membre' }))
    assert.equal((await groupData())?.createdBy, 'createur')
  })
  test('le créateur ne donne pas le groupe à un non-membre', async () => {
    // « etranger » n'a pas d'adhésion : ni promotion possible, ni héritier valide.
    await assertFails(handoverBatch(creator(), { heirHousehold: 'household-etranger', newOwner: 'etranger', promote: false, coordinatorIds: ['coord', 'etranger'] }))
    // Compte qui n'appartient pas au ménage héritier.
    await assertFails(handoverBatch(creator(), { newOwner: 'etranger', coordinatorIds: ['coord', 'etranger'] }))
    assert.equal((await groupData())?.createdBy, 'createur')
  })
  test('changer createdBy sans quitter le groupe est refusé', async () => {
    await assertFails(handoverBatch(creator(), { leave: false, delta: 0 }))
    await assertFails(updateDoc(doc(creator(), groupPath), { createdBy: 'membre', coordinatorIds: ['coord', 'membre'] }))
    await assertFails(updateDoc(doc(creator(), groupPath), { createdBy: 'createur', handoverHouseholdId: 'household-membre' }))
    assert.equal((await groupData())?.createdBy, 'createur')
  })
  test('promouvoir un membre au rôle de coordonnateur sans passation est refusé', async () => {
    await assertFails(updateDoc(doc(creator(), memberOf('household-membre')), { role: 'coordinator' }))
    await assertFails(updateDoc(doc(member(), memberOf('household-membre')), { role: 'coordinator' }))
    // Promotion + groupe qui annonce l'héritier sans changer createdBy : refusé aussi.
    const db = creator()
    const batch = writeBatch(db)
    batch.update(doc(db, memberOf('household-membre')), { role: 'coordinator' })
    batch.update(doc(db, groupPath), { handoverHouseholdId: 'household-membre' })
    await assertFails(batch.commit())
    assert.equal(await roleOf('household-membre'), 'member')
  })
  test('la passation ne passe pas avec un compteur, une liste de coordonnateurs ou un champ de trop faussés', async () => {
    await assertFails(handoverBatch(creator(), { delta: -2 }))
    await assertFails(handoverBatch(creator(), { delta: 0 }))
    await assertFails(handoverBatch(creator(), { coordinatorIds: ['createur', 'coord', 'membre'] }))
    await assertFails(handoverBatch(creator(), { coordinatorIds: ['coord', 'membre', 'etranger'] }))
    const db = creator()
    const batch = writeBatch(db)
    batch.delete(doc(db, memberOf('household-createur')))
    batch.update(doc(db, memberOf('household-membre')), { role: 'coordinator' })
    batch.update(doc(db, groupPath), {
      householdCount: increment(-1), lastMembershipChange: 'household-createur', createdBy: 'membre',
      coordinatorIds: ['coord', 'membre'], handoverHouseholdId: 'household-membre', isPublic: false
    })
    await assertFails(batch.commit())
  })
  test('un héritier sans promotion (reste simple membre) est refusé', async () => {
    await assertFails(handoverBatch(creator(), { promote: false }))
  })
  test('createdBy doit être le userId de l’adhésion de l’héritier', async () => {
    // Le compte nommé est bien dans le ménage héritier, mais l'adhésion ne le désigne pas.
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'households/household-membre'), { id: 'household-membre', name: 'Famille', size: 2, geohash: 'f25du', userIds: ['membre', 'autre'] })
    })
    await assertFails(handoverBatch(creator(), { newOwner: 'autre', coordinatorIds: ['coord', 'autre'] }))
    await assertSucceeds(handoverBatch(creator()))
  })
  test('adhésion ancienne sans userId : la passation est refusée', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), memberOf('household-membre')), { householdId: 'household-membre', role: 'member', joinedAt: Timestamp.now() })
    })
    await assertFails(handoverBatch(creator()))
  })
  test('userId d’une adhésion ne se modifie jamais', async () => {
    await assertFails(updateDoc(doc(member(), memberOf('household-membre')), { userId: 'createur' }))
    await assertFails(updateDoc(doc(creator(), memberOf('household-membre')), { userId: 'createur' }))
  })
  test('le créateur qui sort sans passation reste permis (sortie ordinaire inchangée)', async () => {
    const db = creator()
    const batch = writeBatch(db)
    batch.delete(doc(db, memberOf('household-createur')))
    batch.update(doc(db, groupPath), { householdCount: increment(-1), lastMembershipChange: 'household-createur' })
    await assertSucceeds(batch.commit())
    assert.equal((await groupData())?.createdBy, 'createur')
  })
})

describe('boroughStats : classement solidaire (T-197)', () => {
  const path = 'boroughStats/verdun'
  const stats = { id: 'verdun', name: 'Verdun', shortName: 'Verdun', neighborhoods: ['Verdun'], centerGeohash: 'f25dtf', households: 12,
    activeHouseholds: 8, groupCount: 2, basketsOffered: 3, familiesHelped: 2, savingsCents: 45_000, updatedAt: Timestamp.now() }
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), path), stats) })
  })

  test('un utilisateur connecté lit et liste les arrondissements', async () => {
    await assertSucceeds(getDoc(doc(intruder(), path)))
    await assertSucceeds(getDocs(collection(intruder(), 'boroughStats')))
  })
  test('un anonyme ne lit rien', async () => {
    await assertFails(getDoc(doc(anonymous(), path)))
    await assertFails(getDocs(collection(anonymous(), 'boroughStats')))
  })
  test('aucun client n’écrit : ni création, ni modification, ni suppression (même un vendeur ou un coordonnateur)', async () => {
    for (const db of [amina(), lafleur(), intruder(), anonymous()]) {
      await assertFails(setDoc(doc(db, 'boroughStats/nouveau'), stats))
      await assertFails(setDoc(doc(db, path), { ...stats, basketsOffered: 9_999 }))
      await assertFails(updateDoc(doc(db, path), { savingsCents: 99_999_999 }))
      await assertFails(deleteDoc(doc(db, path)))
    }
  })
})

// ---------------------------------------------------------------------------
// Portail Organismes (T-194) : rattachement, profil, dons, parrainages, fonds de solidarité
// ---------------------------------------------------------------------------
describe('portail Organismes (T-194)', () => {
  const orgId = 'org-banque'
  const groupId = 'group-parc-extension'
  const fund = `groups/${groupId}/solidarity/fund`
  const orgUser = () => env.authenticatedContext('orgmembre').firestore()
  const otherOrgUser = () => env.authenticatedContext('autreorg').firestore()
  const orgDoc = {
    id: orgId, name: 'Banque alimentaire CDN', kind: 'foodBank', neighborhood: 'cote-des-neiges',
    geohash: 'f25dv', memberUserIds: ['orgmembre'], mission: 'Nourrir le quartier', createdAt: Timestamp.now()
  }
  const donation = (over: Record<string, unknown> = {}) => ({
    id: 'don-1', organizationId: orgId, groupId, groupName: 'Voisins de Parc-Ex', kind: 'fund',
    amountCents: 5000, basketCount: 1, householdsReached: 1, date: Timestamp.now(), isSimulated: true, ...over
  })
  const entry = (over: Record<string, unknown> = {}) => ({
    kind: 'contribution', amountCents: 5000, basketCount: 0, date: Timestamp.now(),
    donationId: 'don-1', organizationId: orgId, ...over
  })
  const oldEntry = { kind: 'contribution', amountCents: 2600, basketCount: 0, date: Timestamp.fromMillis(1_700_000_000_000) }
  const fullFund = (over: Record<string, unknown> = {}) => ({
    entries: [oldEntry], subsidizedHouseholds: 4, basketPriceCents: 2600, sponsorOrganizationIds: [], ...over
  })
  const sponsorship = (over: Record<string, unknown> = {}) => ({
    id: groupId, organizationId: orgId, groupName: 'Voisins de Parc-Ex', neighborhood: 'parc-extension',
    monthlyBasketGoal: 10, startedAt: Timestamp.now(), ...over
  })

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, 'users/orgmembre'), { ...aminaUser, id: 'orgmembre', displayName: 'Marie', householdId: null, organizationId: orgId })
      await setDoc(doc(db, 'users/autreorg'), { ...aminaUser, id: 'autreorg', displayName: 'Paul', householdId: null, organizationId: 'org-autre' })
      await setDoc(doc(db, `organizations/${orgId}`), orgDoc)
      await setDoc(doc(db, 'organizations/org-autre'), { ...orgDoc, id: 'org-autre', memberUserIds: ['autreorg'] })
      await setDoc(doc(db, 'groups/group-parc-extension'), { id: groupId, name: 'Voisins de Parc-Ex', neighborhood: 'parc-extension', isPublic: true, inviteCode: 'PARC', householdCount: 3 })
      await setDoc(doc(db, 'groups/group-parc-extension/members/household-amina'), { householdId: 'household-amina', role: 'member', joinedAt: Timestamp.now() })
    })
  })

  const seedFund = (data: Record<string, unknown>) => env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), fund), data)
  })
  const fundDoc = async () => {
    let data: Record<string, any> | undefined
    await env.withSecurityRulesDisabled(async (c) => { data = (await getDoc(doc(c.firestore(), fund))).data() })
    return data
  }

  // Don + crédit du fonds dans un même batch (arrayUnion : l'historique existant n'est pas réécrit).
  const donateBatch = (db: Firestore, o: { donation?: Record<string, unknown>, entry?: Record<string, unknown> } = {}) => {
    const batch = writeBatch(db)
    batch.set(doc(db, `organizations/${orgId}/donations/don-1`), o.donation ?? donation())
    batch.set(doc(db, fund), { entries: arrayUnion(o.entry ?? entry()) }, { merge: true })
    return batch.commit()
  }

  describe('rattachement (users/{uid}.organizationId)', () => {
    test('le client ne peut pas se l’ajouter à la création de son profil', async () => {
      const db = env.authenticatedContext('nouveau').firestore()
      await assertFails(setDoc(doc(db, 'users/nouveau'), { ...aminaUser, id: 'nouveau', householdId: null, organizationId: orgId }))
      await assertSucceeds(setDoc(doc(db, 'users/nouveau'), { ...aminaUser, id: 'nouveau', householdId: null }))
    })
    test('le client ne peut pas se l’ajouter, le changer ni l’effacer à la mise à jour', async () => {
      await assertFails(updateDoc(doc(intruder(), 'users/intrus'), { organizationId: orgId }))
      await assertFails(setDoc(doc(intruder(), 'users/intrus'), { ...aminaUser, id: 'intrus', householdId: null, organizationId: orgId }))
      await assertFails(setDoc(doc(intruder(), 'users/intrus'), { organizationId: orgId }, { merge: true }))
      await assertFails(updateDoc(doc(otherOrgUser(), 'users/autreorg'), { organizationId: orgId }))
      await assertFails(updateDoc(doc(orgUser(), 'users/orgmembre'), { organizationId: null }))
      await assertFails(setDoc(doc(orgUser(), 'users/orgmembre'), { ...aminaUser, id: 'orgmembre', householdId: null }))
    })
    test('un compte rattaché lit son champ et modifie le reste de son profil (merge)', async () => {
      const snap = await assertSucceeds(getDoc(doc(orgUser(), 'users/orgmembre')))
      assert.equal(snap.data()?.organizationId, orgId)
      await assertSucceeds(setDoc(doc(orgUser(), 'users/orgmembre'), { ...aminaUser, id: 'orgmembre', householdId: null, organizationId: orgId, seniorMode: true }, { merge: true }))
      await assertSucceeds(updateDoc(doc(orgUser(), 'users/orgmembre'), { neighborhood: 'cote-des-neiges' }))
    })
    test('personne d’autre ne lit le profil d’un compte rattaché', async () => {
      await assertFails(getDoc(doc(otherOrgUser(), 'users/orgmembre')))
    })
  })

  describe('organizations/{id}', () => {
    test('lisible par ses membres seulement', async () => {
      await assertSucceeds(getDoc(doc(orgUser(), `organizations/${orgId}`)))
      await assertFails(getDoc(doc(otherOrgUser(), `organizations/${orgId}`)))
      await assertFails(getDoc(doc(amina(), `organizations/${orgId}`)))
      await assertFails(getDoc(doc(anonymous(), `organizations/${orgId}`)))
    })
    test('un membre modifie le profil, pas memberUserIds ni les champs figés', async () => {
      const ref = doc(orgUser(), `organizations/${orgId}`)
      await assertSucceeds(updateDoc(ref, { mission: 'Nouvelle mission', name: 'Banque CDN' }))
      await assertFails(updateDoc(ref, { memberUserIds: ['orgmembre', 'intrus'] }))
      await assertFails(updateDoc(ref, { createdAt: Timestamp.now() }))
      await assertFails(updateDoc(ref, { kind: 'casino' }))
      await assertFails(updateDoc(ref, { extra: 1 }))
    })
    test('un non-membre ne modifie rien, personne ne crée ni ne supprime', async () => {
      await assertFails(updateDoc(doc(otherOrgUser(), `organizations/${orgId}`), { mission: 'x' }))
      await assertFails(updateDoc(doc(amina(), `organizations/${orgId}`), { mission: 'x' }))
      await assertFails(setDoc(doc(orgUser(), 'organizations/org-neuf'), { ...orgDoc, id: 'org-neuf' }))
      await assertFails(deleteDoc(doc(orgUser(), `organizations/${orgId}`)))
    })
  })

  // T-208 : carte des organismes. La fiche publique ne porte aucun membre ; organizations/{id} reste privé.
  describe('organizationDirectory/{id}', () => {
    const entry = {
      id: 'org-autre', name: 'Centre communautaire Les Pommiers', kind: 'communityCenter', neighborhood: 'saint-michel',
      geohash: 'f25ehx1', photoUpdatedAt: Timestamp.now(), bannerUpdatedAt: Timestamp.now()
    }
    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (c) => {
        await setDoc(doc(c.firestore(), 'organizationDirectory/org-autre'), entry)
        await setDoc(doc(c.firestore(), `organizationDirectory/${orgId}`), { ...entry, id: orgId, name: orgDoc.name })
      })
    })
    test('un compte d’organisme lit et liste les fiches des autres organismes', async () => {
      await assertSucceeds(getDoc(doc(orgUser(), 'organizationDirectory/org-autre')))
      const snap = await assertSucceeds(getDocs(collection(orgUser(), 'organizationDirectory')))
      assert.equal(snap.size, 2)
      // Le document privé d'un autre organisme (memberUserIds) reste illisible.
      await assertFails(getDoc(doc(orgUser(), 'organizations/org-autre')))
      await assertFails(getDocs(collection(orgUser(), 'organizations')))
    })
    test('une famille, un vendeur ou un anonyme ne la lit pas', async () => {
      await assertFails(getDoc(doc(amina(), 'organizationDirectory/org-autre')))
      await assertFails(getDocs(collection(amina(), 'organizationDirectory')))
      await assertFails(getDoc(doc(anonymous(), 'organizationDirectory/org-autre')))
    })
    test('personne ne l’écrit depuis l’app, même un membre de l’organisme', async () => {
      await assertFails(setDoc(doc(otherOrgUser(), 'organizationDirectory/org-autre'), { ...entry, name: 'Autre nom' }))
      await assertFails(updateDoc(doc(orgUser(), `organizationDirectory/${orgId}`), { name: 'x' }))
      await assertFails(setDoc(doc(orgUser(), 'organizationDirectory/org-neuf'), { ...entry, id: 'org-neuf' }))
      await assertFails(deleteDoc(doc(orgUser(), 'organizationDirectory/org-autre')))
    })
    test('photo de profil et bannière d’un organisme : lues par tout compte connecté, écrites par personne', async () => {
      const media = { data: Bytes.fromUint8Array(new Uint8Array([0xff, 0xd8])), contentType: 'image/jpeg', width: 1200, height: 450, updatedAt: Timestamp.now() }
      await env.withSecurityRulesDisabled(async (c) => {
        await setDoc(doc(c.firestore(), 'organizations/org-autre/media/banner'), media)
      })
      await assertSucceeds(getDoc(doc(orgUser(), 'organizations/org-autre/media/banner')))
      await assertSucceeds(getDoc(doc(amina(), 'organizations/org-autre/media/banner')))
      await assertFails(setDoc(doc(otherOrgUser(), 'organizations/org-autre/media/banner'), { ...media, updatedAt: serverTimestamp() }))
    })
  })

  describe('dons et crédit du fonds', () => {
    test('un membre crée un don et crédite le fonds dans la même écriture (fonds absent)', async () => {
      await assertSucceeds(donateBatch(orgUser()))
      const data = await fundDoc()
      assert.equal(data?.entries.length, 1)
      assert.equal(data?.entries[0].amountCents, 5000)
    })
    test('crédit d’un fonds existant : une ligne ajoutée, l’historique et les autres champs intacts', async () => {
      await seedFund(fullFund({ sponsorOrganizationIds: ['org-autre'] }))
      await assertSucceeds(donateBatch(orgUser()))
      const data = await fundDoc()
      assert.equal(data?.entries.length, 2)
      assert.equal(data?.subsidizedHouseholds, 4)
      assert.deepEqual(data?.sponsorOrganizationIds, ['org-autre'])
    })
    test('réécrire tout le fonds avec un solde gonflé est refusé', async () => {
      await seedFund(fullFund())
      const db = orgUser()
      const batch = writeBatch(db)
      batch.set(doc(db, `organizations/${orgId}/donations/don-1`), donation())
      batch.set(doc(db, fund), fullFund({ entries: [{ ...oldEntry, amountCents: 999_999 }, entry()] }))
      await assertFails(batch.commit())
    })
    test('crédit qui ne correspond pas au don : montant, groupe ou organisme différents', async () => {
      await assertFails(donateBatch(orgUser(), { entry: entry({ amountCents: 9000 }) }))
      await assertFails(donateBatch(orgUser(), { donation: donation({ groupId: 'group-autre' }) }))
      await assertFails(donateBatch(orgUser(), { entry: entry({ organizationId: 'org-autre' }) }))
      await assertFails(donateBatch(orgUser(), { entry: entry({ donationId: 'don-2' }) }))
    })
    test('un crédit sans don, ou deux lignes d’un coup, sont refusés', async () => {
      await assertFails(setDoc(doc(orgUser(), fund), { entries: arrayUnion(entry()) }, { merge: true }))
      const db = orgUser()
      const batch = writeBatch(db)
      batch.set(doc(db, `organizations/${orgId}/donations/don-1`), donation())
      batch.set(doc(db, fund), { entries: [entry(), entry()] })
      await assertFails(batch.commit())
    })
    test('un don avec un montant négatif, nul, décimal ou énorme est refusé', async () => {
      for (const amountCents of [-5000, 0, 12.5, 500_001]) {
        await assertFails(donateBatch(orgUser(), { donation: donation({ amountCents }), entry: entry({ amountCents }) }))
      }
    })
    test('un don isSimulated faux, un champ en trop ou des paniers négatifs sont refusés', async () => {
      await assertFails(donateBatch(orgUser(), { donation: donation({ isSimulated: false }) }))
      await assertFails(donateBatch(orgUser(), { donation: donation({ extra: 1 }) }))
      await assertFails(donateBatch(orgUser(), { donation: donation({ basketCount: -1 }) }))
      await assertFails(donateBatch(orgUser(), { donation: donation({ householdsReached: 5 }) }))
    })
    test('un non-membre, ou un membre d’un autre organisme, ne peut pas donner', async () => {
      await assertFails(donateBatch(otherOrgUser()))
      await assertFails(donateBatch(amina()))
      await assertFails(donateBatch(anonymous()))
    })
    test('un don n’est jamais modifié ni supprimé, et se lit par ses membres seulement', async () => {
      await assertSucceeds(donateBatch(orgUser()))
      await assertFails(updateDoc(doc(orgUser(), `organizations/${orgId}/donations/don-1`), { amountCents: 1 }))
      await assertFails(deleteDoc(doc(orgUser(), `organizations/${orgId}/donations/don-1`)))
      await assertSucceeds(getDoc(doc(orgUser(), `organizations/${orgId}/donations/don-1`)))
      await assertSucceeds(getDocs(collection(orgUser(), `organizations/${orgId}/donations`)))
      await assertFails(getDoc(doc(otherOrgUser(), `organizations/${orgId}/donations/don-1`)))
      await assertFails(getDoc(doc(amina(), `organizations/${orgId}/donations/don-1`)))
    })
    test('un don ne se crée pas sans le crédit du fonds', async () => {
      await assertFails(setDoc(doc(orgUser(), `organizations/${orgId}/donations/don-1`), donation()))
    })
  })

  describe('fonds de solidarité : lecture et débit', () => {
    test('les membres du groupe et les comptes d’organisme lisent le fonds, pas les autres', async () => {
      await seedFund(fullFund())
      await assertSucceeds(getDoc(doc(amina(), fund)))
      await assertSucceeds(getDoc(doc(orgUser(), fund)))
      await assertFails(getDoc(doc(intruder(), fund)))
      await assertFails(getDoc(doc(anonymous(), fund)))
    })
    test('T-203 : un vendeur lit le document du fonds (clôture T-196), sans pouvoir lister ni écrire', async () => {
      await seedFund(fullFund())
      await assertSucceeds(getDoc(doc(lafleur(), fund)))
      await assertFails(getDocs(collection(lafleur(), `groups/${groupId}/solidarity`)))
      await assertFails(getDoc(doc(lafleur(), `groups/${groupId}/solidarity/autre`)))
      await assertFails(setDoc(doc(lafleur(), fund), { subsidizedHouseholds: 0 }, { merge: true }))
    })
    test('aucun débit : application, suppression d’une ligne ou baisse du solde refusés', async () => {
      await seedFund(fullFund())
      const application = { kind: 'application', orderId: 'order-1', amountCents: 2600, basketCount: 1, date: Timestamp.now() }
      await assertFails(setDoc(doc(orgUser(), fund), { entries: arrayUnion(application) }, { merge: true }))
      await assertFails(setDoc(doc(amina(), fund), { entries: arrayUnion(application) }, { merge: true }))
      await assertFails(setDoc(doc(orgUser(), fund), { entries: [] }, { merge: true }))
      await assertFails(updateDoc(doc(orgUser(), fund), { entries: [{ ...oldEntry, amountCents: 1 }] }))
      await assertFails(deleteDoc(doc(orgUser(), fund)))
      await assertFails(deleteDoc(doc(amina(), fund)))
      // Un débit déguisé en don (même écriture qu'un don) est refusé aussi.
      const db = orgUser()
      const batch = writeBatch(db)
      batch.set(doc(db, `organizations/${orgId}/donations/don-1`), donation())
      batch.set(doc(db, fund), { entries: arrayUnion({ ...entry(), kind: 'application' }) }, { merge: true })
      await assertFails(batch.commit())
      assert.equal((await fundDoc())?.entries.length, 1)
    })
    test('une famille ne peut ni créditer ni modifier le fonds', async () => {
      await assertFails(setDoc(doc(amina(), fund), { entries: arrayUnion(entry()) }, { merge: true }))
      await assertFails(setDoc(doc(amina(), fund), { subsidizedHouseholds: 99 }, { merge: true }))
    })
    test('un membre d’organisme ne change ni le prix du panier ni les ménages aidés', async () => {
      await seedFund(fullFund())
      await assertFails(setDoc(doc(orgUser(), fund), { basketPriceCents: 1 }, { merge: true }))
      await assertFails(setDoc(doc(orgUser(), fund), { subsidizedHouseholds: 0 }, { merge: true }))
    })
    test('un autre document sous solidarity est refusé', async () => {
      await assertFails(setDoc(doc(orgUser(), `groups/${groupId}/solidarity/autre`), { entries: [] }))
      await assertFails(getDoc(doc(amina(), `groups/${groupId}/solidarity/autre`)))
    })
  })

  describe('parrainages', () => {
    const sponsorBatch = (db: Firestore, o: { spons?: Record<string, unknown>, ids?: unknown } = {}) => {
      const batch = writeBatch(db)
      batch.set(doc(db, `organizations/${orgId}/sponsorships/${groupId}`), o.spons ?? sponsorship())
      batch.set(doc(db, fund), { sponsorOrganizationIds: o.ids ?? arrayUnion(orgId) }, { merge: true })
      return batch.commit()
    }
    test('un membre parraine un groupe : document + sponsorOrganizationIds (fonds absent)', async () => {
      await assertSucceeds(sponsorBatch(orgUser()))
      assert.deepEqual((await fundDoc())?.sponsorOrganizationIds, [orgId])
    })
    test('parrainage sur un fonds existant : historique et solde intacts', async () => {
      await seedFund(fullFund({ sponsorOrganizationIds: ['org-autre'] }))
      await assertSucceeds(sponsorBatch(orgUser()))
      const data = await fundDoc()
      assert.equal(data?.entries.length, 1)
      assert.deepEqual(data?.sponsorOrganizationIds.sort(), ['org-autre', orgId].sort())
    })
    test('l’objectif mensuel se change, rien d’autre ; nombre entier et positif', async () => {
      await assertSucceeds(sponsorBatch(orgUser()))
      const ref = doc(orgUser(), `organizations/${orgId}/sponsorships/${groupId}`)
      await assertSucceeds(updateDoc(ref, { monthlyBasketGoal: 20 }))
      await assertFails(updateDoc(ref, { monthlyBasketGoal: 0 }))
      await assertFails(updateDoc(ref, { monthlyBasketGoal: -3 }))
      await assertFails(updateDoc(ref, { monthlyBasketGoal: 2.5 }))
      await assertFails(updateDoc(ref, { startedAt: Timestamp.now() }))
      await assertFails(updateDoc(ref, { groupName: 'Autre nom' }))
    })
    test('un objectif négatif ou une identité falsifiée à la création sont refusés', async () => {
      await assertFails(sponsorBatch(orgUser(), { spons: sponsorship({ monthlyBasketGoal: -1 }) }))
      await assertFails(sponsorBatch(orgUser(), { spons: sponsorship({ groupName: 'Faux nom' }) }))
      await assertFails(sponsorBatch(orgUser(), { spons: sponsorship({ organizationId: 'org-autre' }) }))
    })
    test('on ne s’ajoute pas au fonds sans parrainage, ni un autre organisme', async () => {
      await assertFails(setDoc(doc(orgUser(), fund), { sponsorOrganizationIds: arrayUnion(orgId) }, { merge: true }))
      await assertFails(sponsorBatch(orgUser(), { ids: ['org-autre'] }))
      await assertFails(sponsorBatch(orgUser(), { ids: [orgId, 'org-autre'] }))
    })
    test('un membre met fin au parrainage : suppression + retrait de sponsorOrganizationIds', async () => {
      await assertSucceeds(sponsorBatch(orgUser()))
      const db = orgUser()
      const batch = writeBatch(db)
      batch.delete(doc(db, `organizations/${orgId}/sponsorships/${groupId}`))
      batch.set(doc(db, fund), { sponsorOrganizationIds: arrayRemove(orgId) }, { merge: true })
      await assertSucceeds(batch.commit())
      assert.deepEqual((await fundDoc())?.sponsorOrganizationIds, [])
    })
    test('on ne retire pas un autre organisme du fonds', async () => {
      await seedFund(fullFund({ entries: [], sponsorOrganizationIds: ['org-autre'] }))
      await assertFails(setDoc(doc(orgUser(), fund), { sponsorOrganizationIds: arrayRemove('org-autre') }, { merge: true }))
    })
    test('non-membres : aucune lecture ni écriture des parrainages', async () => {
      await assertFails(sponsorBatch(otherOrgUser()))
      await assertFails(sponsorBatch(amina()))
      await assertSucceeds(sponsorBatch(orgUser()))
      await assertSucceeds(getDocs(collection(orgUser(), `organizations/${orgId}/sponsorships`)))
      await assertFails(getDocs(collection(otherOrgUser(), `organizations/${orgId}/sponsorships`)))
      await assertFails(deleteDoc(doc(otherOrgUser(), `organizations/${orgId}/sponsorships/${groupId}`)))
    })
  })

  // T-202 : QA adverse. Chaque test reproduit à l'identique une écriture de FirestoreOrganizationRepository
  // (mêmes champs, mêmes types, même transaction ou même batch), pas une écriture « idéale ».
  describe('écritures exactes de l’app (T-202)', () => {
    // OrganizationLedger.record + SolidarityLedger.donating : ligne sans orderId (nil omis à l'encodage).
    const appEntry = (donationId: string, amountCents: number, date: Timestamp) => ({
      kind: 'contribution', amountCents, basketCount: 0, date, donationId, organizationId: orgId
    })
    type Plan = { kind: string, amountCents: number, basketCount: number, householdsReached: number }
    const appDonation = (donationId: string, o: Plan, date: Timestamp) => ({
      id: donationId, organizationId: orgId, groupId, groupName: 'Voisins de Parc-Ex', kind: o.kind,
      amountCents: o.amountCents, basketCount: o.basketCount, householdsReached: o.householdsReached, date, isSimulated: true
    })
    // FirestoreOrganizationRepository.donate : lit l'organisme, le groupe et le fonds, puis ajoute la ligne
    // (arrayUnion, merge) et crée le don, dans UNE transaction.
    const appDonate = (db: Firestore, donationId: string, o: Plan = { kind: 'fund', amountCents: 5000, basketCount: 1, householdsReached: 1 }) => {
      const date = Timestamp.now()
      return runTransaction(db, async (tx) => {
        assert.ok((await tx.get(doc(db, `organizations/${orgId}`))).exists())
        assert.ok((await tx.get(doc(db, `groups/${groupId}`))).exists())
        await tx.get(doc(db, fund))
        tx.set(doc(db, fund), { entries: arrayUnion(appEntry(donationId, o.amountCents, date)) }, { merge: true })
        tx.set(doc(db, `organizations/${orgId}/donations/${donationId}`), appDonation(donationId, o, date))
      })
    }

    test('don en transaction, fonds absent puis fonds existant : une ligne par don, aucun doublon', async () => {
      await assertSucceeds(appDonate(orgUser(), 'don-a'))
      await assertSucceeds(appDonate(orgUser(), 'don-b', { kind: 'suspendedBaskets', amountCents: 3 * 2600, basketCount: 3, householdsReached: 3 }))
      const data = await fundDoc()
      assert.deepEqual(data?.entries.map((e: { donationId: string }) => e.donationId), ['don-a', 'don-b'])
      assert.deepEqual(data?.entries.map((e: { amountCents: number }) => e.amountCents), [5000, 7800])
      assert.equal('orderId' in data!.entries[0], false)
    })
    test('rejouer la même transaction (même id de don) est refusé : pas de double crédit', async () => {
      await seedFund(fullFund())
      await assertSucceeds(appDonate(orgUser(), 'don-a'))
      await assertFails(appDonate(orgUser(), 'don-a'))
      assert.equal((await fundDoc())?.entries.length, 2)
    })
    test('montants limites de la feuille : 5 $ (minimum), 5 000 $ (maximum) acceptés, 5 000,01 $ refusé', async () => {
      await seedFund(fullFund())
      await assertSucceeds(appDonate(orgUser(), 'don-min', { kind: 'fund', amountCents: 500, basketCount: 0, householdsReached: 0 }))
      await assertSucceeds(appDonate(orgUser(), 'don-max', { kind: 'fund', amountCents: 500_000, basketCount: 192, householdsReached: 4 }))
      await assertFails(appDonate(orgUser(), 'don-trop', { kind: 'fund', amountCents: 500_001, basketCount: 192, householdsReached: 4 }))
      assert.equal((await fundDoc())?.entries.length, 3)
    })
    test('lectures du portail : groupes publics, fonds (même absent), dons et parrainages', async () => {
      const db = orgUser()
      await assertSucceeds(getDocs(query(collection(db, 'groups'), where('isPublic', '==', true))))
      await assertSucceeds(getDoc(doc(db, fund)))
      await assertSucceeds(getDoc(doc(db, `groups/${groupId}`)))
      await assertSucceeds(getDocs(collection(db, `organizations/${orgId}/donations`)))
      await assertSucceeds(getDocs(collection(db, `organizations/${orgId}/sponsorships`)))
      await assertSucceeds(getDoc(doc(db, `organizations/${orgId}/sponsorships/${groupId}`)))
    })
    test('changer l’objectif : updateData(monthlyBasketGoal) + arrayUnion dans le même batch, sans doublon', async () => {
      await seedFund(fullFund())
      const db = orgUser()
      const create = writeBatch(db)
      create.set(doc(db, `organizations/${orgId}/sponsorships/${groupId}`), sponsorship())
      create.set(doc(db, fund), { sponsorOrganizationIds: arrayUnion(orgId) }, { merge: true })
      await assertSucceeds(create.commit())
      const update = writeBatch(db)
      update.update(doc(db, `organizations/${orgId}/sponsorships/${groupId}`), { monthlyBasketGoal: 40 })
      update.set(doc(db, fund), { sponsorOrganizationIds: arrayUnion(orgId) }, { merge: true })
      await assertSucceeds(update.commit())
      const data = await fundDoc()
      assert.deepEqual(data?.sponsorOrganizationIds, [orgId])
      assert.equal(data?.entries.length, 1)
    })
    test('mettre fin à un parrainage sans fonds : le batch de l’app passe', async () => {
      const db = orgUser()
      const batch = writeBatch(db)
      batch.delete(doc(db, `organizations/${orgId}/sponsorships/${groupId}`))
      batch.set(doc(db, fund), { sponsorOrganizationIds: arrayRemove(orgId) }, { merge: true })
      await assertSucceeds(batch.commit())
    })
    test('quartier de groupe de 61 à 80 caractères : le parrainage passe avec le quartier tronqué à 60 (app)', async () => {
      const longNeighborhood = 'Quartier '.padEnd(80, 'x')
      await env.withSecurityRulesDisabled(async (c) => {
        await setDoc(doc(c.firestore(), `groups/${groupId}`), { id: groupId, name: 'Voisins de Parc-Ex', neighborhood: longNeighborhood, isPublic: true, inviteCode: 'PARC', householdCount: 3 })
      })
      const sponsorWith = (neighborhood: string) => {
        const db = orgUser()
        const batch = writeBatch(db)
        batch.set(doc(db, `organizations/${orgId}/sponsorships/${groupId}`), sponsorship({ neighborhood }))
        batch.set(doc(db, fund), { sponsorOrganizationIds: arrayUnion(orgId) }, { merge: true })
        return batch.commit()
      }
      // Les règles des groupes acceptent 80 caractères, celles du parrainage 60 : l'app tronque (T-202).
      await assertFails(sponsorWith(longNeighborhood))
      await assertSucceeds(sponsorWith(longNeighborhood.slice(0, 60)))
    })
  })
})

describe('clôture : paiements enregistrés, versement vendeur et débit du fonds (T-195)', () => {
  const GROUP = 'group-parc-extension'
  const ORDER = 'order-cloture'
  const orderPath = `groupOrders/${ORDER}`
  const sharePath = `${orderPath}/shares/household-amina`
  const paymentPath = `${orderPath}/payments/household-amina`
  const payoutPath = `${orderPath}/payouts/vendor`
  const fundPath = `groups/${GROUP}/solidarity/fund`
  const closed = { status: 'closed', currentTierIndex: 0 }

  // Swift : FNV-1a 32 bits de "orderId|householdId" (ShareAllocator.qrCode).
  const qr = (householdId: string) => {
    let hash = 2166136261
    for (const byte of new TextEncoder().encode(`${ORDER}|${householdId}`)) {
      hash ^= byte
      hash = Math.imul(hash, 16777619) >>> 0
    }
    return `GRENIER:${ORDER}:${householdId}:${hash.toString(16).padStart(8, '0')}`
  }

  // 10 parts à 7 $ : 70 $, dont 50 $ payés par le fonds. La famille paie 20 $.
  const payment = {
    id: `PAY-${ORDER}-household-amina-1`, householdId: 'household-amina', groupOrderId: ORDER,
    finalPriceCents: 7000, subsidyCents: 5000, donationCents: 0, amountDueCents: 2000,
    status: 'succeeded', date: Timestamp.now(), methodLabel: 'Apple Pay (démo)'
  }
  const payout = {
    id: 'vendor', groupOrderId: ORDER, vendorId: 'vendor-lafleur', mode: 'deposit', grossCents: 7000,
    commissionCents: 70, netCents: 6930, releasedCents: 3465, heldCents: 3465, subsidyTotalCents: 5000,
    solidarityContributedCents: 0, paidShareCount: 1, date: Timestamp.now()
  }
  const debit = { kind: 'application', orderId: ORDER, amountCents: 5000, basketCount: 0, date: Timestamp.now() }

  type Parts = { payment?: object | null; payout?: object | null; debit?: object | null; subsidy?: number }

  // Ce que fait `closeGroupOrder` : la part figée et payée, le paiement, le versement, le fonds, puis la commande.
  const closeBatch = (db: Firestore, parts: Parts = {}) => {
    const batch = writeBatch(db)
    batch.update(doc(db, sharePath), {
      finalPriceCents: 7000, subsidyCents: parts.subsidy ?? 5000, isPaid: true
    })
    if (parts.payment !== null) batch.set(doc(db, paymentPath), parts.payment ?? payment)
    if (parts.payout !== null) batch.set(doc(db, payoutPath), parts.payout ?? payout)
    if (parts.debit !== null) {
      batch.update(doc(db, fundPath), { entries: arrayUnion(parts.debit ?? debit) })
    }
    batch.update(doc(db, orderPath), closed)
    return batch.commit()
  }

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, 'households/household-amina/private/profile'), { isSubsidized: true, referralCode: 'ORG-PE-00035' })
      await setDoc(doc(db, `groups/${GROUP}/members/household-amina`), { householdId: 'household-amina', role: 'member', joinedAt: Timestamp.now() })
      await setDoc(doc(db, orderPath), {
        id: ORDER, groupId: GROUP, offerId: 'offer-carottes', status: 'open', committedShares: 10, committedHouseholds: 1, pickupSlots: []
      })
      await setDoc(doc(db, sharePath), { ...share, quantity: 10 })
      await setDoc(doc(db, fundPath), {
        entries: [{ kind: 'contribution', amountCents: 8000, basketCount: 0, date: Timestamp.now() }],
        subsidizedHouseholds: 1, basketPriceCents: 2600, sponsorOrganizationIds: []
      })
    })
  })

  const seedClosed = async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await updateDoc(doc(db, orderPath), closed)
      await updateDoc(doc(db, sharePath), { finalPriceCents: 7000, subsidyCents: 5000, isPaid: true })
      await setDoc(doc(db, paymentPath), payment)
      await setDoc(doc(db, payoutPath), payout)
    })
  }

  const makeCoordinator = () => env.withSecurityRulesDisabled(async (c) => {
    await updateDoc(doc(c.firestore(), `groups/${GROUP}`), { coordinatorIds: ['intrus'] })
  })

  test('le vendeur du lot clôture : parts, paiement, versement et débit du fonds dans la même écriture', async () => {
    await assertSucceeds(closeBatch(lafleur()))
  })
  // T-203 : la même clôture, rejouée comme `FirestoreGroupOrderRepository.closeGroupOrder` : une transaction qui relit
  // la commande, le lot, les parts, le fonds et le vendeur avant d'écrire. Avant le correctif, la lecture du fonds
  // était refusée au vendeur : « Fermer la commande » côté vendeur échouait toujours.
  const closeTransaction = (db: Firestore) => runTransaction(db, async (tx) => {
    await tx.get(doc(db, orderPath))
    await tx.get(doc(db, 'offers/offer-carottes'))
    await tx.get(doc(db, sharePath))
    await tx.get(doc(db, fundPath))
    await tx.get(doc(db, 'vendors/vendor-lafleur'))
    tx.update(doc(db, sharePath), { finalPriceCents: 7000, subsidyCents: 5000, isPaid: true })
    tx.set(doc(db, paymentPath), payment)
    tx.set(doc(db, payoutPath), payout)
    tx.update(doc(db, fundPath), { entries: arrayUnion(debit) })
    tx.update(doc(db, orderPath), { committedShares: 10, committedHouseholds: 1, currentTierIndex: 0, status: 'closed' })
  })
  test('T-203 : le vendeur du lot clôture dans une transaction qui relit le fonds', async () => {
    await assertSucceeds(closeTransaction(lafleur()))
    let entries: unknown[] = []
    await env.withSecurityRulesDisabled(async (c) => {
      entries = (await getDoc(doc(c.firestore(), fundPath))).data()?.entries ?? []
    })
    assert.equal(entries.length, 2)
  })
  test('T-203 : un autre vendeur ne clôture pas la commande, même s’il lit le fonds', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'users/intrus'), { ...aminaUser, id: 'intrus', householdId: null, vendorId: 'vendor-autre' })
    })
    await assertFails(closeTransaction(intruder()))
  })
  test('la coordination du groupe clôture aussi', async () => {
    await makeCoordinator()
    await assertSucceeds(closeBatch(intruder()))
  })
  test('un ménage ne crée ni paiement, ni versement, ni débit', async () => {
    await assertFails(closeBatch(amina()))
    await assertFails(setDoc(doc(amina(), paymentPath), payment))
    await assertFails(setDoc(doc(amina(), payoutPath), payout))
    await assertFails(updateDoc(doc(amina(), fundPath), { entries: arrayUnion(debit) }))
  })
  test('un paiement hors de l’écriture de clôture est refusé (commande ouverte ou déjà fermée)', async () => {
    await assertFails(setDoc(doc(lafleur(), paymentPath), payment))
    await assertFails(setDoc(doc(lafleur(), payoutPath), payout))
    await seedClosed()
    await assertFails(setDoc(doc(lafleur(), `${orderPath}/payments/household-autre`), { ...payment, householdId: 'household-autre' }))
    await assertFails(setDoc(doc(lafleur(), `${orderPath}/payouts/autre`), payout))
  })
  test('un paiement et un versement ne se modifient ni ne se suppriment jamais', async () => {
    await seedClosed()
    for (const db of [lafleur(), amina()]) {
      await assertFails(updateDoc(doc(db, paymentPath), { amountDueCents: 0 }))
      await assertFails(deleteDoc(doc(db, paymentPath)))
      await assertFails(updateDoc(doc(db, payoutPath), { heldCents: 0 }))
      await assertFails(deleteDoc(doc(db, payoutPath)))
    }
  })
  test('un paiement incohérent est refusé', async () => {
    await assertFails(closeBatch(lafleur(), { payment: { ...payment, amountDueCents: 100 } }))
    await assertFails(closeBatch(lafleur(), { payment: { ...payment, status: 'declined' } }))
    await assertFails(closeBatch(lafleur(), { payment: { ...payment, subsidyCents: 8000, amountDueCents: -1000 } }))
    await assertFails(closeBatch(lafleur(), { payment: { ...payment, householdId: 'household-autre' } }))
    await assertFails(closeBatch(lafleur(), { payment: { ...payment, extra: true } }))
  })
  test('un versement incohérent est refusé (net, retenu, commission, vendeur)', async () => {
    await assertFails(closeBatch(lafleur(), { payout: { ...payout, netCents: 7000 } }))
    await assertFails(closeBatch(lafleur(), { payout: { ...payout, heldCents: 0 } }))
    await assertFails(closeBatch(lafleur(), { payout: { ...payout, commissionCents: 0, netCents: 7000, releasedCents: 3500, heldCents: 3500 } }))
    // L'ancien taux de 6 % est refusé : la commission est d'au plus 1 %.
    await assertFails(closeBatch(lafleur(), { payout: { ...payout, commissionCents: 420, netCents: 6580, releasedCents: 3290, heldCents: 3290 } }))
    await assertFails(closeBatch(lafleur(), { payout: { ...payout, vendorId: 'vendor-autre' } }))
    await assertFails(closeBatch(lafleur(), { payout: { ...payout, mode: 'cash' } }))
  })
  test('lecture : la famille lit son paiement ; le vendeur et la coordination lisent ceux de la commande', async () => {
    await seedClosed()
    await assertSucceeds(getDoc(doc(amina(), paymentPath)))
    await assertSucceeds(getDoc(doc(lafleur(), paymentPath)))
    await assertSucceeds(getDocs(collection(lafleur(), `${orderPath}/payments`)))
    await assertSucceeds(getDoc(doc(lafleur(), payoutPath)))
    await assertFails(getDoc(doc(intruder(), paymentPath)))
    await assertFails(getDocs(collection(amina(), `${orderPath}/payments`)))
    await assertFails(getDoc(doc(amina(), payoutPath)))
    await assertFails(getDoc(doc(intruder(), payoutPath)))
    await makeCoordinator()
    await assertSucceeds(getDocs(collection(intruder(), `${orderPath}/payments`)))
    await assertSucceeds(getDoc(doc(intruder(), payoutPath)))
  })
  test('fonds : le débit est exactement celui des subventions déclarées (le solde non négatif est tenu par l’app)', async () => {
    // Le débit dépasse ce que le versement déclare : refusé. Les règles ne somment pas l'historique.
    await assertFails(closeBatch(lafleur(), { debit: { ...debit, amountCents: 9000 } }))
    await assertFails(closeBatch(lafleur(), { debit: { ...debit, amountCents: 1000 } }))
    await assertFails(closeBatch(lafleur(), { debit: { ...debit, kind: 'contribution' } }))
    await assertFails(closeBatch(lafleur(), { debit: { ...debit, orderId: 'order-1' } }))
    await assertFails(closeBatch(lafleur(), { debit: { ...debit, ménage: 'household-amina' } }))
  })
  test('fonds vide ou sans subvention : la clôture ne touche pas au fonds', async () => {
    await assertSucceeds(closeBatch(lafleur(), {
      subsidy: 0, debit: null,
      payment: { ...payment, subsidyCents: 0, amountDueCents: 7000 },
      payout: { ...payout, subsidyTotalCents: 0 }
    }))
  })
  test('fonds : pas de débit hors clôture, ni de crédit, ni de réécriture de l’historique', async () => {
    await assertFails(updateDoc(doc(lafleur(), fundPath), { entries: arrayUnion(debit) }))
    await seedClosed()
    await assertFails(updateDoc(doc(lafleur(), fundPath), { entries: arrayUnion(debit) }))
    await assertFails(updateDoc(doc(lafleur(), fundPath), { sponsorOrganizationIds: ['org-x'] }))
    await assertFails(updateDoc(doc(lafleur(), fundPath), { entries: [] }))
    await assertFails(deleteDoc(doc(lafleur(), fundPath)))
  })
  test('fonds : lisible par les membres du groupe seulement', async () => {
    await assertSucceeds(getDoc(doc(amina(), fundPath)))
    await assertFails(getDoc(doc(intruder(), fundPath)))
    await assertFails(getDoc(doc(anonymous(), fundPath)))
  })
  // Comme setShare : une nouvelle part avec son drapeau d'admissibilité, et la commande ouverte mise à jour.
  const reserve = (db: Firestore, householdId: string, value: boolean) => {
    const batch = writeBatch(db)
    batch.set(doc(db, `groupOrders/order-1/shares/${householdId}`), {
      ...share, householdId, quantity: 2, solidarityEligible: value, updatedAt: Timestamp.now()
    })
    batch.update(doc(db, 'groupOrders/order-1'), { committedShares: 2, committedHouseholds: 1 })
    return batch.commit()
  }
  test('admissibilité : un ménage subventionné se déclare admissible, puis change sa quantité', async () => {
    await assertSucceeds(reserve(amina(), 'household-amina', true))
    // Seuls les champs qui changent sont écrits (updateData).
    const db = amina()
    const change = writeBatch(db)
    change.update(doc(db, 'groupOrders/order-1/shares/household-amina'), { quantity: 3, solidarityEligible: false, updatedAt: Timestamp.now() })
    change.update(doc(db, 'groupOrders/order-1'), { committedShares: 3 })
    await assertSucceeds(change.commit())
  })
  test('admissibilité : un ménage sans statut subventionné ne peut pas se déclarer admissible', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore()
      await setDoc(doc(db, `groups/${GROUP}/members/household-intrus`), { householdId: 'household-intrus', role: 'member', joinedAt: Timestamp.now() })
      await setDoc(doc(db, 'users/intrus'), { ...aminaUser, id: 'intrus', householdId: 'household-intrus' })
    })
    await assertFails(reserve(intruder(), 'household-intrus', true))
    await assertSucceeds(reserve(intruder(), 'household-intrus', false))
  })
})
