// markPublishedOffers.ts — migration (sécurité, prix figés) : pose `wasPublished: true` sur les lots en pause
// écrits avant ce correctif.
//
// Pourquoi : firestore.rules fige paliers, parts, minimum et part d'un lot publié (status != 'draft' ou
// wasPublished == true). Un lot mis en pause AVANT ce correctif est un brouillon sans la marque : les règles le
// prennent pour un brouillon jamais publié, et le vendeur pourrait changer ses prix puis le republier alors que
// des familles y ont déjà engagé des parts. Ce script marque les brouillons qui ont au moins une commande groupée
// (donc déjà vus par des familles). Les lots actifs, fermés ou retirés sont déjà figés par leur statut.
//
// Par défaut : lecture seule (liste ce qui serait changé). `--apply` écrit.
//   Émulateur (défaut) : FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/seed/markPublishedOffers.ts [--apply]
//   Projet réel        : GOOGLE_APPLICATION_CREDENTIALS=… node scripts/seed/markPublishedOffers.ts --target cloud --project <id> [--apply --yes]
// Ne jamais lancer sur le projet réel sans l'accord d'un humain (comme un déploiement de règles).
import { parseArgs } from 'node:util'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'

const { values } = parseArgs({
  options: {
    target: { type: 'string', default: 'emulator' },
    project: { type: 'string', default: 'demo-grenier' },
    apply: { type: 'boolean', default: false },
    yes: { type: 'boolean', default: false }
  }
})

if (values.target !== 'emulator' && values.target !== 'cloud') throw new Error('--target emulator|cloud')
if (values.target === 'emulator') {
  const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080'
  if (!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(host)) throw new Error('FIRESTORE_EMULATOR_HOST doit être local')
  process.env.FIRESTORE_EMULATOR_HOST = host
} else {
  delete process.env.FIRESTORE_EMULATOR_HOST
  if (values.apply && !values.yes) throw new Error('Projet réel : ajoute --yes pour confirmer l’écriture.')
}

const app = initializeApp({ projectId: values.project })
try {
  const db = getFirestore(app)
  const drafts = await db.collection('offers').where('status', '==', 'draft').get()
  const toMark: string[] = []
  for (const offer of drafts.docs) {
    if (offer.get('wasPublished') === true) continue
    const orders = await db.collection('groupOrders').where('offerId', '==', offer.id).limit(1).get()
    if (!orders.empty) toMark.push(offer.id)
  }
  console.log(`${drafts.size} brouillon(s), ${toMark.length} en pause à marquer : ${toMark.join(', ') || 'aucun'}`)
  if (values.apply) {
    for (const id of toMark) await db.collection('offers').doc(id).update({ wasPublished: true })
    console.log(`${toMark.length} lot(s) marqué(s) wasPublished: true.`)
  } else if (toMark.length > 0) {
    console.log('Lecture seule : relance avec --apply pour écrire.')
  }
} finally {
  await deleteApp(app)
}
