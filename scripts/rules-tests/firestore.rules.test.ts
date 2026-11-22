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
  writeBatch,
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
  test('pas avant la fermeture de la commande', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'groupOrders/order-pickup'), { status: 'open' })
    })
    await assertFails(updateDoc(doc(amina(), sharePath), pickedUp('karim')))
  })
  test('rien d’autre ne bouge avec la remise', async () => {
    await assertFails(updateDoc(doc(amina(), sharePath), { ...pickedUp('karim'), quantity: 9 }))
  })
})

describe('groups/members', () => {
  const groupPath = 'groups/group-parc-extension'
  const memberPath = `${groupPath}/members/household-amina`
  const membership = { householdId: 'household-amina', role: 'member', joinedAt: serverTimestamp() }

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
  const setShare = (db: Firestore, quantity: number, committedHouseholds: number) => {
    const batch = writeBatch(db)
    if (quantity > 0) {
      batch.set(doc(db, sharePath), { ...share, quantity, updatedAt: Timestamp.now() })
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
    const member: Record<string, unknown> = { householdId: 'household-intrus', role: 'member', joinedAt: serverTimestamp() }
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
    householdId: 'household-amina', role: 'coordinator', joinedAt: serverTimestamp(), ...overrides
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
