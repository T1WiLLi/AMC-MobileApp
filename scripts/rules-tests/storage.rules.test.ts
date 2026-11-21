// Tests des règles Storage (storage.rules) sur l'émulateur (avec Firestore pour le lien vendeur).
import { after, before, describe, test } from 'node:test'
import { readFile } from 'node:fs/promises'
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment
} from '@firebase/rules-unit-testing'
import { doc, setDoc } from 'firebase/firestore'
import { ref, uploadBytes, getMetadata } from 'firebase/storage'

let env: RulesTestEnvironment
const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47])

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-grenier-rules',
    firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') }
  })
  await env.clearFirestore()
  await env.clearStorage()
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users/lafleur'), { id: 'lafleur', vendorId: 'vendor-lafleur' })
    await setDoc(doc(context.firestore(), 'users/amina'), { id: 'amina' })
    await uploadBytes(ref(context.storage(), 'vendors/vendor-lafleur/existante.png'), png, { contentType: 'image/png' })
  })
})

after(async () => { await env.cleanup() })

describe('storage', () => {
  const storageOf = (uid: string) => env.authenticatedContext(uid).storage()

  test('le vendeur téléverse une photo de produit', async () => {
    await assertSucceeds(uploadBytes(ref(storageOf('lafleur'), 'vendors/vendor-lafleur/carottes.png'), png, { contentType: 'image/png' }))
  })
  test('pas dans le dossier d’un autre vendeur', async () => {
    await assertFails(uploadBytes(ref(storageOf('lafleur'), 'vendors/vendor-autre/x.png'), png, { contentType: 'image/png' }))
  })
  test('une famille ne téléverse pas chez un vendeur', async () => {
    await assertFails(uploadBytes(ref(storageOf('amina'), 'vendors/vendor-lafleur/x.png'), png, { contentType: 'image/png' }))
  })
  test('pas de fichier non image', async () => {
    await assertFails(uploadBytes(ref(storageOf('lafleur'), 'vendors/vendor-lafleur/x.html'), png, { contentType: 'text/html' }))
  })
  test('photo de profil : propriétaire seulement', async () => {
    await assertSucceeds(uploadBytes(ref(storageOf('amina'), 'users/amina/avatar.png'), png, { contentType: 'image/png' }))
    await assertFails(uploadBytes(ref(storageOf('amina'), 'users/lafleur/avatar.png'), png, { contentType: 'image/png' }))
  })
  test('lecture connectée seulement', async () => {
    await assertSucceeds(getMetadata(ref(storageOf('amina'), 'vendors/vendor-lafleur/existante.png')))
    await assertFails(getMetadata(ref(env.unauthenticatedContext().storage(), 'vendors/vendor-lafleur/existante.png')))
  })
  test('chemin inconnu refusé', async () => {
    await assertFails(uploadBytes(ref(storageOf('amina'), 'public/x.png'), png, { contentType: 'image/png' }))
  })
})
