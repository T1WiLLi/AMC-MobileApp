import assert from 'node:assert/strict'
import { test } from 'node:test'
import { boroughOf, computeBoroughStats, normalizeName, summarize, type Input, type Share } from './aggregateBoroughStats.ts'

const now = new Date('2026-11-22T12:00:00Z')
const share = (orderId: string, householdId: string, extra: Partial<Share> = {}): Share =>
  ({ orderId, householdId, quantity: 1, finalPriceCents: 1_000, suspendedAmountCents: 0, subsidyCents: 0, ...extra })

function input(extra: Partial<Input> = {}): Input {
  return {
    groups: [
      { id: 'g-sm', neighborhood: 'saint-michel' },
      { id: 'g-pe', neighborhood: 'Parc-Extension' },
      { id: 'g-ver', neighborhood: 'Verdun' },
      { id: 'g-x', neighborhood: 'Atlantide' }
    ],
    members: [
      { groupId: 'g-sm', householdId: 'h1' }, { groupId: 'g-sm', householdId: 'h2' },
      { groupId: 'g-pe', householdId: 'h2' }, { groupId: 'g-pe', householdId: 'h3' },
      { groupId: 'g-ver', householdId: 'h4' }, { groupId: 'g-ver', householdId: 'h5' },
      { groupId: 'g-x', householdId: 'h6' }
    ],
    orders: [
      { id: 'o1', groupId: 'g-sm', offerId: 'offer', status: 'closed' },
      { id: 'o2', groupId: 'g-pe', offerId: 'offer', status: 'delivered' },
      { id: 'o3', groupId: 'g-sm', offerId: 'offer', status: 'open' }
    ],
    shares: [],
    referencePriceByOffer: new Map([['offer', 1_500]]),
    ...extra
  }
}

test('le quartier d’un groupe retrouve son arrondissement (casse, accents, slug)', () => {
  assert.equal(normalizeName('Côte-des-Neiges'), 'cote-des-neiges')
  assert.equal(boroughOf('saint-michel')?.id, 'villeray-saint-michel-parc-extension')
  assert.equal(boroughOf('PARC EXTENSION')?.id, 'villeray-saint-michel-parc-extension')
  assert.equal(boroughOf('Plateau-Mont-Royal')?.id, 'le-plateau-mont-royal')
  assert.equal(boroughOf('Atlantide'), null)
})

test('ménages distincts, groupes et seuil de k-anonymat', () => {
  const result = computeBoroughStats(input(), now)
  const [doc] = result.docs
  assert.equal(result.docs.length, 1)
  assert.equal(doc.id, 'villeray-saint-michel-parc-extension')
  assert.equal(doc.households, 3, 'h2 est dans deux groupes mais compte une fois')
  assert.equal(doc.groupCount, 2)
  // Verdun n'a que 2 ménages : non publié.
  assert.deepEqual(result.excluded.find(({ id }) => id === 'verdun'), { id: 'verdun', reason: 'sous-seuil', households: 2 })
  assert.deepEqual(result.unmatchedNeighborhoods, ['Atlantide'])
})

test('mesures : participation, économies, paniers suspendus, familles aidées', () => {
  const shares = [
    share('o1', 'h1', { quantity: 2, finalPriceCents: 2_000 }),
    share('o1', 'h2', { quantity: 1, finalPriceCents: 1_000, suspendedAmountCents: 1_000, subsidyCents: 300 }),
    share('o2', 'h3', { quantity: 1, finalPriceCents: 1_600, suspendedAmountCents: 500 }),
    share('o2', 'h2', { quantity: 3, finalPriceCents: 3_000, subsidyCents: 100 }),
    share('o3', 'h3'),
    share('o1', 'h1', { quantity: 0 }),
    share('o1', 'h3', { finalPriceCents: null })
  ]
  const [doc] = computeBoroughStats(input({ shares }), now).docs
  assert.equal(doc.activeHouseholds, 3)
  // (1500-1000)*2 + (1500-1000)*1 + 0 (prix > référence) + (1500-1000)*3
  assert.equal(doc.savingsCents, 1_000 + 500 + 0 + 1_500)
  // 1000/1000 + 500/1600 = 1,3125 → 1
  assert.equal(doc.basketsOffered, 1)
  assert.equal(doc.familiesHelped, 1, 'h2 reçoit deux subventions mais compte une seule famille')
  assert.deepEqual(doc.neighborhoods, ['Villeray', 'Saint-Michel', 'Parc-Extension'])
  assert.equal(doc.updatedAt, now)
})

test('paniers suspendus : les fractions s’additionnent avant l’arrondi', () => {
  const shares = [
    share('o1', 'h1', { finalPriceCents: 1_000, suspendedAmountCents: 600 }),
    share('o1', 'h2', { finalPriceCents: 1_000, suspendedAmountCents: 600 }),
    share('o2', 'h3', { finalPriceCents: 1_000, suspendedAmountCents: 800 })
  ]
  assert.equal(computeBoroughStats(input({ shares }), now).docs[0].basketsOffered, 2)
})

test('sans prix de référence, pas d’économie inventée', () => {
  const [doc] = computeBoroughStats(input({ shares: [share('o1', 'h1')], referencePriceByOffer: new Map() }), now).docs
  assert.equal(doc.savingsCents, 0)
  assert.equal(doc.activeHouseholds, 1)
})

test('aucune donnée personnelle dans la sortie', () => {
  const shares = [share('o1', 'h1', { subsidyCents: 500 })]
  const json = JSON.stringify(computeBoroughStats(input({ shares }), now).docs)
  for (const secret of ['h1', 'h2', 'g-sm', 'o1']) assert.ok(!json.includes(`"${secret}"`), secret)
})

test('idempotent : mêmes entrées, mêmes agrégats', () => {
  const data = input({ shares: [share('o1', 'h1', { subsidyCents: 200, suspendedAmountCents: 500 })] })
  assert.deepEqual(computeBoroughStats(data, now), computeBoroughStats(data, now))
})

test('résumé : une ligne par arrondissement et les exclus', () => {
  const text = summarize(computeBoroughStats(input(), now), false)
  assert.match(text, /\[dry-run\] À écrire : 1 arrondissement/)
  assert.match(text, /villeray-saint-michel-parc-extension : 3 ménages/)
  assert.match(text, /verdun : 2 ménage/)
  assert.match(text, /Atlantide/)
})
