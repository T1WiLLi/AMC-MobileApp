// Données de démo enrichies (T-130) : ajoutées aux fixtures de `fixtures/` au moment du seed.
//
// Les fichiers JSON restent la base vérifiée par les tests Swift (comptes fixes : 6 vendeurs, 40 produits,
// 25 lots, 60 ménages…). Ce module y ajoute, de façon déterministe (ids fixes, pseudo-hasard à graine fixe),
// ce qui rend la démo vivante :
//   - 5 vendeurs de plus (boulangerie, moulin, ferme halal, coopérative, savonnerie) et la position
//     (`storefrontGeohash`) de chaque vendeur ;
//   - 29 produits et 25 lots de plus, des échéances étalées sur deux semaines ;
//   - des lots terminés (`closed`) et leurs commandes livrées, clôturées ou annulées : historique,
//     économies et revenus ;
//   - 70 ménages de plus (12 à 22 par groupe), de nouvelles commandes à toutes les étapes des paliers ;
//   - 3 points de cueillette de plus et des créneaux en plus pour Jean ;
//   - des envies (`groups/{id}/wishes`) et des disponibilités (`vendors/{id}/supplies`) qui se rencontrent
//     dans le Matcher.
// Le résultat a exactement le format des fichiers JSON (deadlineInDays, slotTemplates, pickupSlotsInDays,
// shares…) : `readDemoSeed` le valide et le convertit comme le reste.

export type Raw = Record<string, any> & { id: string }

export type RawFixtures = {
  vendors: Raw[]
  products: Raw[]
  offers: Raw[]
  groups: Raw[]
  pickupPoints: Raw[]
  users: Raw[]
  households: Raw[]
  groupOrders: Raw[]
  wishes: Raw[]
  supplies: Raw[]
}

// ---------------------------------------------------------------------------------------------
// Outils
// ---------------------------------------------------------------------------------------------

const geohashAlphabet = '0123456789bcdefghjkmnpqrstuvwxyz'

/** Geohash standard (base 32) d'une position. */
export function encodeGeohash(latitude: number, longitude: number, precision: number): string {
  let [latMin, latMax, lonMin, lonMax] = [-90, 90, -180, 180]
  let hash = ''
  let bits = 0
  let value = 0
  let even = true
  while (hash.length < precision) {
    if (even) {
      const middle = (lonMin + lonMax) / 2
      if (longitude >= middle) { value = value * 2 + 1; lonMin = middle } else { value *= 2; lonMax = middle }
    } else {
      const middle = (latMin + latMax) / 2
      if (latitude >= middle) { value = value * 2 + 1; latMin = middle } else { value *= 2; latMax = middle }
    }
    even = !even
    if (++bits === 5) {
      hash += geohashAlphabet[value]
      bits = 0
      value = 0
    }
  }
  return hash
}

/** Même code QR que `ShareAllocator.qrCode` (FNV-1a 32 bits sur « orderId|householdId »). */
export function pickupQRCode(orderId: string, householdId: string): string {
  let hash = 2_166_136_261
  for (const byte of new TextEncoder().encode(`${orderId}|${householdId}`)) {
    hash ^= byte
    hash = Math.imul(hash, 16_777_619) >>> 0
  }
  return `GRENIER:${orderId}:${householdId}:${hash.toString(16).padStart(8, '0')}`
}

/** Code d'organisme valide (`ReferralCode` : ORG-XX-NNNNC, contrôle modulo 11 pondéré). */
export function referralCode(organisation: string, serial: number): string {
  const body = organisation + String(serial).padStart(4, '0')
  const value = (character: string) => /[0-9]/.test(character) ? Number(character) : character.charCodeAt(0) - 55
  const sum = [...body].reduce((total, character, index) => total + (index + 1) * value(character), 0)
  const check = sum % 11
  return `ORG-${organisation}-${String(serial).padStart(4, '0')}${check === 10 ? 'X' : check}`
}

/** Pseudo-hasard à graine fixe (mulberry32) : deux exécutions donnent les mêmes données. */
function random(seed: number) {
  let state = seed >>> 0
  const next = () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296
  }
  const int = (min: number, max: number) => min + Math.floor(next() * (max - min + 1))
  const pick = <T>(values: readonly T[]): T => values[Math.floor(next() * values.length)]!
  const shuffle = <T>(values: readonly T[]): T[] => {
    const copy = [...values]
    for (let index = copy.length - 1; index > 0; index -= 1) {
      const other = Math.floor(next() * (index + 1))
      ;[copy[index], copy[other]] = [copy[other]!, copy[index]!]
    }
    return copy
  }
  return { next, int, pick, shuffle }
}

// ---------------------------------------------------------------------------------------------
// Quartiers et vendeurs
// ---------------------------------------------------------------------------------------------

const all = ['parc-extension', 'rosemont', 'hochelaga', 'saint-michel', 'verdun', 'cote-des-neiges', 'montreal-nord', 'villeray']

/** Nombre de ménages visé par groupe (8 à 25, B-027 en avait 7 à 10). */
const targetHouseholds: Record<string, number> = {
  'parc-extension': 22, 'saint-michel': 18, 'cote-des-neiges': 20, rosemont: 16,
  villeray: 15, hochelaga: 14, 'montreal-nord': 13, verdun: 12
}

/** Préfixe des codes d'organisme par quartier. */
const organisationOf: Record<string, string> = {
  'parc-extension': 'PE', 'saint-michel': 'SM', 'cote-des-neiges': 'CN', rosemont: 'RO',
  villeray: 'VI', hochelaga: 'HO', 'montreal-nord': 'MN', verdun: 'VE'
}

/** Position de la vitrine de chaque vendeur (ville réelle du Québec). */
const storefronts: Record<string, [number, number]> = {
  'vendor-ferme-lafleur': [45.2636, -73.6185], // Saint-Rémi
  'vendor-ferme-bio-rive': [45.6497, -74.0834], // Mirabel
  'vendor-moulins-du-nord': [45.5880, -73.7280], // Laval
  'vendor-coop-lanaudiere': [46.0230, -73.4410], // Joliette
  'vendor-marche-central': [45.5355, -73.6550], // Marché Central, Montréal
  'vendor-boucherie-cantons': [45.2340, -71.8260], // Compton
  'vendor-fournil-terrebonne': [45.6990, -73.6470], // Terrebonne
  'vendor-moulin-chaudiere': [46.1180, -70.6690], // Saint-Georges
  'vendor-ferme-trois-collines': [45.6300, -72.9570], // Saint-Hyacinthe
  'vendor-coop-ile-orleans': [46.8840, -71.0640], // Saint-Pierre-de-l'Île-d'Orléans
  'vendor-savonnerie-laurentides': [46.0510, -74.2830] // Sainte-Agathe-des-Monts
}

const newVendors: Raw[] = [
  {
    id: 'vendor-fournil-terrebonne', legalName: 'Fournil du Vieux-Terrebonne', kind: 'bakery',
    description: 'Boulangerie artisanale de Terrebonne : pains au levain, pains de blé entier et bagels cuits au four à bois, farine du Québec.',
    photoURLs: [], servedZones: ['parc-extension', 'villeray', 'rosemont', 'saint-michel', 'montreal-nord'],
    averageRating: 4.9, isVerified: true
  },
  {
    id: 'vendor-moulin-chaudiere', legalName: 'Moulin de la Chaudière', kind: 'other',
    description: 'Meunerie familiale de Saint-Georges, en Beauce : farines moulues sur pierre et flocons de grains biologiques.',
    photoURLs: [], servedZones: all, averageRating: 4.6, isVerified: true
  },
  {
    id: 'vendor-ferme-trois-collines', legalName: 'Ferme des Trois Collines', kind: 'farm',
    description: 'Élevage de Saint-Hyacinthe certifié halal : poulet, agneau et bœuf, abattage local et traçabilité complète.',
    photoURLs: [], servedZones: ['saint-michel', 'parc-extension', 'cote-des-neiges', 'montreal-nord', 'villeray', 'hochelaga'],
    averageRating: 4.7, isVerified: true
  },
  {
    id: 'vendor-coop-ile-orleans', legalName: "Coopérative maraîchère de l'Île", kind: 'cooperative',
    description: "Douze producteurs de l'île d'Orléans : pommes, pommes de terre, oignons et sirop d'érable de la cabane voisine.",
    photoURLs: [], servedZones: ['rosemont', 'hochelaga', 'villeray', 'saint-michel', 'verdun'],
    averageRating: 4.5, isVerified: true
  },
  {
    id: 'vendor-savonnerie-laurentides', legalName: 'Savonnerie des Laurentides', kind: 'other',
    description: 'Savonnerie de Sainte-Agathe-des-Monts : savons, nettoyants et lessive biodégradables en grands formats à remplir.',
    photoURLs: [], servedZones: all, averageRating: null, isVerified: false
  }
]

// ---------------------------------------------------------------------------------------------
// Produits
// ---------------------------------------------------------------------------------------------

const priceSource = "Estimation d'après les circulaires d'épiceries de Montréal (novembre 2026) ; valeur approximative, à vérifier"

type ProductDefinition = [id: string, vendor: string, name: string, category: string, unit: string,
  origin: string, tags: string[], referenceCents: number]

const productDefinitions: ProductDefinition[] = [
  ['ail-lafleur', 'ferme-lafleur', 'Ail du Québec', 'produce', 'tresse de 1 kg', 'Saint-Rémi, QC', ['local'], 2499],
  ['panais', 'ferme-lafleur', 'Panais', 'produce', 'sac de 3 kg', 'Saint-Rémi, QC', ['local'], 1199],
  ['celeri-rave', 'ferme-lafleur', 'Céleris-raves', 'produce', 'caisse de 6', 'Saint-Rémi, QC', ['local'], 1499],
  ['courge-spaghetti', 'ferme-bio-rive', 'Courges spaghetti bio', 'produce', 'caisse de 6', 'Mirabel, QC', ['organic', 'local'], 1899],
  ['jus-pomme-bio', 'ferme-bio-rive', 'Jus de pomme bio', 'canned', 'caisse de 6 × 1,89 L', 'Mirabel, QC', ['organic', 'local', 'vegan'], 2399],
  ['quinoa', 'moulins-du-nord', 'Quinoa blanc', 'grains', 'sac de 5 kg', 'Bolivie (importé)', ['vegan', 'halal', 'glutenFree'], 3299],
  ['orge-perle', 'moulins-du-nord', 'Orge perlé', 'grains', 'sac de 5 kg', 'Québec, CA', ['vegan', 'local'], 1299],
  ['poitrines-poulet', 'coop-lanaudiere', 'Poitrines de poulet', 'meat', 'boîte de 4 kg', 'Lanaudière, QC', ['local'], 5199],
  ['dindon-hache', 'coop-lanaudiere', 'Dindon haché', 'meat', 'boîte de 3 kg', 'Lanaudière, QC', ['local'], 2899],
  ['huile-tournesol', 'marche-central', 'Huile de tournesol', 'oils', 'bidon de 4 L', 'Manitoba, CA', ['vegan', 'halal', 'kosher'], 2199],
  ['haricots-rouges-conserve', 'marche-central', 'Haricots rouges en conserve', 'canned', 'caisse de 12 × 540 mL', 'Canada', ['vegan', 'halal'], 1908],
  ['saucisses-porc', 'boucherie-cantons', 'Saucisses de porc fermières', 'meat', 'boîte de 2 kg', 'Compton, QC', ['local'], 2799],
  ['boeuf-ragout', 'boucherie-cantons', 'Cubes de bœuf à ragoût', 'meat', 'boîte de 2,5 kg', 'Compton, QC', ['local'], 4499],
  ['pain-campagne', 'fournil-terrebonne', 'Pains de campagne au levain', 'grains', 'caisse de 6 pains', 'Terrebonne, QC', ['vegan', 'local'], 3294],
  ['pain-ble-entier', 'fournil-terrebonne', 'Pains de blé entier', 'grains', 'caisse de 6 pains', 'Terrebonne, QC', ['vegan', 'local'], 2994],
  ['bagels', 'fournil-terrebonne', 'Bagels au sésame', 'grains', 'sac de 24', 'Terrebonne, QC', ['vegan', 'local'], 1999],
  ['farine-epeautre', 'moulin-chaudiere', "Farine d'épeautre bio", 'flour', 'sac de 5 kg', 'Saint-Georges, QC', ['organic', 'vegan', 'local'], 2499],
  ['farine-seigle', 'moulin-chaudiere', 'Farine de seigle', 'flour', 'sac de 5 kg', 'Saint-Georges, QC', ['vegan', 'local'], 1999],
  ['flocons-avoine-bio', 'moulin-chaudiere', "Flocons d'avoine bio", 'grains', 'sac de 5 kg', 'Saint-Georges, QC', ['organic', 'vegan', 'local'], 1899],
  ['poulet-halal', 'ferme-trois-collines', 'Poulets entiers halal', 'meat', 'boîte de 3 poulets (≈ 6 kg)', 'Saint-Hyacinthe, QC', ['halal', 'local'], 4797],
  ['agneau-halal', 'ferme-trois-collines', "Épaule d'agneau halal", 'meat', 'boîte de 3 kg', 'Saint-Hyacinthe, QC', ['halal', 'local'], 6297],
  ['boeuf-hache-halal', 'ferme-trois-collines', 'Bœuf haché halal', 'meat', 'boîte de 3 kg', 'Saint-Hyacinthe, QC', ['halal', 'local'], 4197],
  ['pommes-honeycrisp', 'coop-ile-orleans', 'Pommes Honeycrisp', 'produce', 'caisse de 5 kg', "Île d'Orléans, QC", ['local'], 1999],
  ['pommes-de-terre-rouges', 'coop-ile-orleans', 'Pommes de terre rouges', 'produce', 'sac de 10 kg', "Île d'Orléans, QC", ['local'], 1699],
  ['oignons-rouges', 'coop-ile-orleans', 'Oignons rouges', 'produce', 'sac de 5 kg', "Île d'Orléans, QC", ['local'], 1199],
  ['sirop-erable', 'coop-ile-orleans', "Sirop d'érable", 'canned', 'caisse de 4 × 540 mL', "Île d'Orléans, QC", ['vegan', 'glutenFree', 'local'], 4396],
  ['savon-mains', 'savonnerie-laurentides', 'Savon à mains (recharge)', 'household', 'bidon de 4 L', 'Sainte-Agathe-des-Monts, QC', ['vegan', 'local'], 2899],
  ['nettoyant-tout-usage', 'savonnerie-laurentides', 'Nettoyant tout usage écologique', 'household', 'bidon de 4 L', 'Sainte-Agathe-des-Monts, QC', ['vegan', 'local'], 2499],
  ['lessive-poudre', 'savonnerie-laurentides', 'Lessive en poudre', 'household', 'seau de 5 kg (80 brassées)', 'Sainte-Agathe-des-Monts, QC', ['local'], 3499]
]

const newProducts: Raw[] = productDefinitions.map(([id, vendor, name, category, unit, origin, tags, referenceCents]) => ({
  id: `product-${id}`, vendorId: `vendor-${vendor}`, name, category, unit, origin, tags, photoURL: null,
  referenceGroceryPriceCents: referenceCents, referencePriceSource: priceSource
}))

// ---------------------------------------------------------------------------------------------
// Lots
// ---------------------------------------------------------------------------------------------

/** Paliers : 12 %, 22 %, 32 %, 38 % sous le prix d'épicerie, prix arrondis en ,x9. */
function makeTiers(referenceCents: number, minimums: number[]) {
  const discounts = [0.12, 0.22, 0.32, 0.38]
  return minimums.map((minShares, index) => ({
    minShares,
    priceCents: Math.round((referenceCents * (1 - discounts[index]!)) / 10) * 10 - 1
  }))
}

type OfferDefinition = [product: string, deadlineInDays: number, totalShares: number, minimums: number[],
  zones: string[] | 'vendor', status?: string]

const activeOfferDefinitions: OfferDefinition[] = [
  ['ail-lafleur', 9, 30, [6, 12, 20], 'vendor'],
  ['panais', 12, 30, [8, 16, 24], 'vendor'],
  ['celeri-rave', 3, 25, [6, 12, 18], ['parc-extension', 'villeray', 'rosemont', 'saint-michel']],
  ['courge-spaghetti', 10, 25, [6, 12, 18], 'vendor'],
  ['jus-pomme-bio', 13, 40, [10, 20, 30], 'vendor'],
  ['quinoa', 11, 30, [8, 16, 24], 'vendor'],
  ['orge-perle', 14, 30, [8, 16, 24], 'vendor'],
  ['poitrines-poulet', 3, 30, [8, 15, 22], 'vendor'],
  ['dindon-hache', 9, 30, [8, 15, 22], 'vendor'],
  ['huile-tournesol', 12, 40, [10, 20, 30], 'vendor'],
  ['haricots-rouges-conserve', 7, 30, [8, 16, 24], 'vendor'],
  ['saucisses-porc', 6, 30, [8, 15, 22], 'vendor'],
  ['boeuf-ragout', 14, 25, [6, 12, 18], 'vendor', 'draft'],
  ['pain-campagne', 1, 30, [8, 16, 24], 'vendor'],
  ['bagels', 4, 40, [10, 20, 30], 'vendor'],
  ['farine-epeautre', 8, 30, [8, 16, 24], 'vendor'],
  ['flocons-avoine-bio', 13, 30, [8, 16, 24], 'vendor'],
  ['poulet-halal', 2, 30, [6, 12, 20, 26], 'vendor'],
  ['agneau-halal', 10, 20, [5, 10, 15], 'vendor'],
  ['boeuf-hache-halal', 5, 30, [8, 15, 22, 28], 'vendor'],
  ['pommes-honeycrisp', 3, 40, [10, 20, 30], 'vendor'],
  ['pommes-de-terre-rouges', 8, 40, [10, 20, 30], 'vendor'],
  ['sirop-erable', 14, 30, [6, 12, 20], 'vendor'],
  ['savon-mains', 11, 30, [8, 16, 24], 'vendor'],
  ['nettoyant-tout-usage', 14, 30, [8, 16, 24], 'vendor', 'draft']
]

/** Lots terminés : [produit, échéance (jours, négative), groupes servis]. */
const pastOfferDefinitions: [product: string, deadlineInDays: number, groups: string[]][] = [
  ['carottes', -12, ['parc-extension', 'rosemont', 'villeray', 'saint-michel', 'verdun']],
  ['pommes-de-terre-jaunes', -5, ['parc-extension', 'saint-michel', 'hochelaga', 'cote-des-neiges']],
  ['oeufs-lafleur', -19, ['parc-extension', 'villeray', 'montreal-nord', 'rosemont']],
  ['courges-butternut', -26, ['parc-extension', 'hochelaga', 'verdun']],
  ['oignons-jaunes', -40, ['parc-extension', 'saint-michel', 'cote-des-neiges', 'villeray']],
  ['choux-verts', -54, ['parc-extension', 'rosemont', 'montreal-nord']],
  ['betteraves', -1, ['parc-extension', 'villeray', 'saint-michel']],
  ['riz-basmati', -8, ['parc-extension', 'saint-michel', 'cote-des-neiges', 'montreal-nord']],
  ['lentilles-rouges', -15, ['parc-extension', 'cote-des-neiges', 'hochelaga', 'verdun']],
  ['huile-canola', -22, ['parc-extension', 'saint-michel', 'rosemont', 'villeray', 'montreal-nord']],
  ['poulet-halal', -9, ['parc-extension', 'saint-michel', 'cote-des-neiges']],
  ['oeufs-gros', -33, ['rosemont', 'hochelaga', 'saint-michel', 'montreal-nord']],
  ['farine-tout-usage', -47, ['parc-extension', 'cote-des-neiges', 'verdun']],
  ['pommes-cortland', -29, ['rosemont', 'verdun', 'hochelaga']],
  ['pois-chiches', -2, ['parc-extension', 'cote-des-neiges', 'montreal-nord']],
  ['thon-pale', -18, ['verdun', 'cote-des-neiges', 'saint-michel']]
]

/** Commande annulée (minimum pas atteint) : [lot terminé, groupe]. */
const cancelledPastOrders = new Set(['thon-pale|verdun', 'choux-verts|montreal-nord'])

// ---------------------------------------------------------------------------------------------
// Points de cueillette
// ---------------------------------------------------------------------------------------------

const newPickupPoints: (Raw & { latitude: number, longitude: number })[] = [
  {
    id: 'pickup-saint-michel-2', groupId: 'group-saint-michel', neighborhood: 'saint-michel',
    hostUserId: 'user-hote-saint-michel', name: 'Épicerie solidaire de la 25e Avenue',
    address: '8950, 25e Avenue, Montréal, QC H1Z 4B5', latitude: 45.5642, longitude: -73.6088,
    capacity: 25, accessibility: ['wheelchair', 'stepFree'],
    slotTemplates: [{ inDays: 3, start: '16:00', end: '18:30' }, { inDays: 8, start: '10:00', end: '12:00' }]
  },
  {
    id: 'pickup-cote-des-neiges-2', groupId: 'group-cote-des-neiges', neighborhood: 'cote-des-neiges',
    hostUserId: 'user-hote-cote-des-neiges', name: 'Salle communautaire de l’avenue Barclay',
    address: '5150, avenue Barclay, Montréal, QC H3W 1C9', latitude: 45.4978, longitude: -73.6301,
    capacity: 30, accessibility: ['stepFree', 'nearMetro'],
    slotTemplates: [{ inDays: 4, start: '17:00', end: '19:00' }, { inDays: 11, start: '10:00', end: '12:00' }]
  },
  {
    id: 'pickup-rosemont-2', groupId: 'group-rosemont', neighborhood: 'rosemont',
    hostUserId: 'user-hote-rosemont', name: 'Café coopératif de la 1re Avenue',
    address: '5600, 1re Avenue, Montréal, QC H1Y 2Z9', latitude: 45.5452, longitude: -73.5801,
    capacity: 20, accessibility: ['stepFree'],
    slotTemplates: [{ inDays: 5, start: '16:30', end: '18:30' }, { inDays: 12, start: '09:30', end: '11:30' }]
  }
]

/** Créneaux de plus pour le point de Jean (deux semaines de cueillettes). */
const jeanExtraSlots = [
  { inDays: 7, start: '17:00', end: '19:30', capacity: 15 },
  { inDays: 9, start: '10:00', end: '12:00', capacity: 12 },
  { inDays: 12, start: '17:00', end: '19:30', capacity: 15 },
  { inDays: 14, start: '10:00', end: '12:00', capacity: 12 }
]

// ---------------------------------------------------------------------------------------------
// Ménages
// ---------------------------------------------------------------------------------------------

const surnames = [
  'Abdi', 'Alvarez', 'Arsenault', 'Asante', 'Baptiste', 'Barry', 'Beaulieu', 'Benjelloun', 'Boateng', 'Boucher',
  'Brisson', 'Camara', 'Caron', 'Celestin', 'Cissé', 'Constantin', 'Cruz', 'Daigle', 'Delgado', 'Demers',
  'Dion', 'Do', 'Duval', 'El Amrani', 'Estimé', 'Farah', 'Fontaine', 'Gagné', 'Garcia', 'Georges',
  'Ghosh', 'Girard', 'Guerrero', 'Hamel', 'Hébert', 'Hoang', 'Huynh', 'Jacques', 'Kamara', 'Karimi',
  'Labelle', 'Lachance', 'Laplante', 'Le', 'Leblanc', 'Lopez', 'Louis', 'Mahamat', 'Martel', 'Mercier',
  'Messaoudi', 'Michaud', 'Mukherjee', 'Nasser', 'Ndiaye', 'Ortiz', 'Pelletier', 'Petit-Frère', 'Poirier', 'Popescu',
  'Quintal', 'Ramos', 'Rezaei', 'Richard', 'Rivera', 'Sall', 'Sanchez', 'Sarr', 'Savard', 'Simard',
  'Sow', 'Tessier', 'Toussaint', 'Turcotte', 'Ulysse', 'Vo', 'Volkov', 'Wong', 'Yildiz', 'Zhang'
]

// ---------------------------------------------------------------------------------------------
// Envies et disponibilités (Matcher)
// ---------------------------------------------------------------------------------------------

type WishTemplate = [category: string, unit: string, productId: string | null, min: number, max: number]

const wishTemplates: WishTemplate[] = [
  ['meat', 'kg', null, 2, 6],
  ['legumes', 'kg', null, 2, 5],
  ['legumes', 'kg', 'product-lentilles-rouges', 2, 4],
  ['grains', 'kg', null, 4, 10],
  ['grains', 'kg', 'product-riz-basmati', 5, 10],
  ['eggs', 'dozen', null, 2, 5],
  ['produce', 'kg', null, 5, 15],
  ['flour', 'kg', null, 2, 10],
  ['oils', 'l', null, 2, 4],
  ['household', 'unit', null, 1, 3],
  ['canned', 'unit', null, 6, 12]
]
/** Quartiers où une bonne part des familles cherche de la viande halal. */
const halalTemplates: WishTemplate[] = [
  ['meat', 'kg', 'product-poulet-halal', 3, 6],
  ['meat', 'kg', null, 3, 8]
]
const halalNeighborhoods = new Set(['parc-extension', 'saint-michel', 'cote-des-neiges', 'montreal-nord'])

type SupplyDefinition = [vendor: string, category: string, unit: string, productId: string | null, quantity: number,
  fromDays: number, toDays: number, zones: string[] | 'vendor']

const supplyDefinitions: SupplyDefinition[] = [
  ['ferme-lafleur', 'produce', 'kg', null, 900, -3, 21, 'vendor'],
  ['ferme-lafleur', 'eggs', 'dozen', 'product-oeufs-lafleur', 240, 0, 14, 'vendor'],
  ['ferme-lafleur', 'produce', 'kg', 'product-courges-butternut', 150, 2, 28, ['parc-extension', 'villeray', 'rosemont']],
  ['ferme-bio-rive', 'produce', 'kg', null, 400, -1, 20, 'vendor'],
  ['moulins-du-nord', 'legumes', 'kg', null, 1200, -5, 30, 'vendor'],
  ['moulins-du-nord', 'grains', 'kg', 'product-riz-basmati', 600, 0, 30, 'vendor'],
  ['moulins-du-nord', 'legumes', 'kg', 'product-pois-casses', 200, -40, -10, 'vendor'],
  ['coop-lanaudiere', 'eggs', 'dozen', null, 400, -2, 14, 'vendor'],
  ['coop-lanaudiere', 'meat', 'kg', null, 250, 1, 21, 'vendor'],
  ['marche-central', 'oils', 'l', null, 300, -7, 30, 'vendor'],
  ['marche-central', 'canned', 'unit', null, 800, -7, 30, 'vendor'],
  ['marche-central', 'household', 'unit', null, 250, 0, 30, 'vendor'],
  ['boucherie-cantons', 'meat', 'kg', null, 8, 0, 10, 'vendor'],
  ['fournil-terrebonne', 'grains', 'unit', 'product-pain-campagne', 150, 0, 7, 'vendor'],
  ['moulin-chaudiere', 'flour', 'kg', null, 1500, -2, 45, 'vendor'],
  ['moulin-chaudiere', 'grains', 'kg', 'product-flocons-avoine-bio', 300, 0, 30, 'vendor'],
  ['ferme-trois-collines', 'meat', 'kg', 'product-poulet-halal', 20, 0, 14, 'vendor'],
  ['ferme-trois-collines', 'meat', 'kg', null, 160, 3, 25, 'vendor'],
  ['coop-ile-orleans', 'produce', 'kg', null, 1100, -4, 18, 'vendor'],
  ['coop-ile-orleans', 'canned', 'l', 'product-sirop-erable', 120, 0, 60, 'vendor'],
  ['savonnerie-laurentides', 'household', 'unit', null, 300, 0, 30, 'vendor'],
  ['savonnerie-laurentides', 'household', 'l', null, 200, 0, 30, 'vendor']
]

// ---------------------------------------------------------------------------------------------
// Assemblage
// ---------------------------------------------------------------------------------------------

type Tier = { minShares: number, priceCents: number }

const slugOf = (groupId: string) => groupId.replace(/^group-/, '')

/** Ajoute les données enrichies aux fixtures de base (qui ne sont pas modifiées). */
export function enrichFixtures(base: RawFixtures): RawFixtures {
  const rng = random(130)
  const clone = <T>(value: T): T => structuredClone(value)

  // Vendeurs : vitrine de chacun, puis les nouveaux.
  const vendors = [...clone(base.vendors), ...clone(newVendors)].map((vendor) => {
    const position = storefronts[vendor.id]
    return position ? { ...vendor, storefrontGeohash: encodeGeohash(position[0], position[1], 7) } : vendor
  })
  const vendorZones = new Map(vendors.map(({ id, servedZones }) => [id, servedZones as string[]]))
  const products = [...clone(base.products), ...clone(newProducts)]
  const productById = new Map(products.map((product) => [product.id, product]))

  const offerFor = (productId: string, id: string, deadlineInDays: number, totalShares: number,
    minimums: number[], zones: string[], status: string): Raw => {
    const product = productById.get(`product-${productId}`)
    if (!product) throw new Error(`richDemo : produit inconnu ${productId}`)
    return {
      id, vendorId: product.vendorId, productId: product.id, totalShares, shareUnit: product.unit,
      tiers: makeTiers(product.referenceGroceryPriceCents, minimums), minimumSharesToLaunch: minimums[0],
      deadlineInDays, zones, status
    }
  }
  const newOffers = activeOfferDefinitions.map(([productId, deadline, total, minimums, zones, status]) =>
    offerFor(productId, `offer-${productId}`, deadline, total, minimums,
      zones === 'vendor' ? vendorZones.get(productById.get(`product-${productId}`)!.vendorId)! : zones,
      status ?? 'active'))
  const pastOffers = pastOfferDefinitions.map(([productId, deadline, groups]) =>
    offerFor(productId, `offer-${productId}-h${-deadline}`, deadline, 40, [8, 16, 24], groups, 'closed'))
  const offers = [...clone(base.offers), ...newOffers, ...pastOffers]

  // Points de cueillette : créneaux en plus pour Jean, trois nouveaux points.
  const pickupPoints = clone(base.pickupPoints).map((point) => point.id === 'pickup-parc-extension-1'
    ? { ...point, slotTemplates: [...point.slotTemplates, ...jeanExtraSlots] }
    : point)
  for (const point of newPickupPoints) {
    pickupPoints.push({ ...clone(point), geohash: encodeGeohash(point.latitude, point.longitude, 6) })
  }

  // Ménages : on complète chaque groupe jusqu'à sa cible.
  const households = clone(base.households)
  const usedNames = new Set(households.map(({ name }) => name))
  const names = surnames.map((surname) => `Famille ${surname}`).filter((name) => !usedNames.has(name))
  let nextNumber = Math.max(...households.map(({ id }) => Number(/^household-(\d+)$/.exec(id)?.[1] ?? 0))) + 1
  let nameIndex = 0
  const serials: Record<string, number> = {}
  const groups = clone(base.groups)
  for (const group of groups) {
    const slug = slugOf(group.id)
    const target = targetHouseholds[slug] ?? 0
    const current = households.filter(({ groupId }) => groupId === group.id).length
    for (let count = current; count < target; count += 1) {
      const subsidized = rng.next() < 0.18
      const organisation = organisationOf[slug] ?? 'GR'
      serials[organisation] = (serials[organisation] ?? 100) + rng.int(3, 40)
      households.push({
        id: `household-${String(nextNumber++).padStart(3, '0')}`,
        name: names[nameIndex++ % names.length],
        size: rng.pick([1, 2, 2, 3, 3, 4, 4, 4, 5, 5, 6, 7]),
        geohash: String(group.centerGeohash).slice(0, 5),
        userIds: [],
        groupId: group.id,
        memberRole: 'member',
        private: subsidized
          ? { isSubsidized: true, referralCode: referralCode(organisation, serials[organisation]!) }
          : { isSubsidized: false }
      })
    }
    group.householdCount = households.filter(({ groupId }) => groupId === group.id).length
    const extraPoints = newPickupPoints.filter(({ groupId }) => groupId === group.id).map(({ id }) => id)
    group.pickupPointIds = [...group.pickupPointIds, ...extraPoints]
  }
  const membersOf = new Map<string, string[]>()
  for (const { id, groupId } of households) membersOf.set(groupId, [...(membersOf.get(groupId) ?? []), id])
  const subsidized = new Set(households.filter((household) => household.private.isSubsidized).map(({ id }) => id))

  // Répartit `total` parts entre des ménages du groupe (dont `required`), 1 à 6 parts chacun.
  const distribute = (groupId: string, total: number, required: string[]) => {
    const members = membersOf.get(groupId)!
    const wanted = Math.max(required.length, Math.round(total / (1.6 + rng.next() * 0.8)))
    const count = Math.min(members.length, total, Math.max(wanted, Math.ceil(total / 6)))
    const others = rng.shuffle(members.filter((id) => !required.includes(id)))
    const chosen = [...required, ...others].slice(0, count)
    const quantities = chosen.map(() => 1)
    for (let left = total - count; left > 0;) {
      const index = rng.int(0, count - 1)
      if (quantities[index]! < 6) { quantities[index]! += 1; left -= 1 }
    }
    return chosen.map((householdId, index) => ({ householdId, quantity: quantities[index]! }))
  }
  const tierIndexFor = (tiers: Tier[], committed: number) => {
    let index: number | null = null
    tiers.forEach((tier, position) => { if (committed >= tier.minShares) index = position })
    return index
  }
  const suspended = () => rng.next() < 0.2 ? rng.pick([500, 500, 750, 1000, 1500]) : 0

  const groupOrders = clone(base.groupOrders)
  const offerById = new Map(offers.map((offer) => [offer.id, offer]))
  const orderNumber: Record<string, number> = {}
  for (const order of groupOrders) {
    const slug = slugOf(order.groupId)
    orderNumber[slug] = Math.max(orderNumber[slug] ?? 0, Number(/-(\d+)$/.exec(order.id)?.[1] ?? 0))
  }

  // Commandes en cours : chaque groupe a des lots à toutes les étapes des paliers.
  const activeOrdersPerGroup: Record<string, number> = {
    'parc-extension': 5, 'saint-michel': 4, 'cote-des-neiges': 4, rosemont: 3,
    villeray: 3, hochelaga: 3, 'montreal-nord': 3, verdun: 2
  }
  const stages = ['justUnlocked', 'closeToNext', 'atRisk', 'best', 'fresh'] as const
  const activeOffers = offers.filter(({ status }) => status === 'active')
  for (const group of groups) {
    const slug = slugOf(group.id)
    const taken = new Set(groupOrders.filter(({ groupId }) => groupId === group.id).map(({ offerId }) => offerId))
    const candidates = rng.shuffle(activeOffers.filter(({ id, zones }) => zones.includes(slug) && !taken.has(id)))
    const required = slug === 'parc-extension' ? ['household-amina'] : []
    for (let index = 0; index < (activeOrdersPerGroup[slug] ?? 0); index += 1) {
      const stage = stages[index % stages.length]!
      // Un lot « à risque » se termine bientôt ; les autres, n'importe quand.
      const position = stage === 'atRisk'
        ? Math.max(0, candidates.findIndex(({ deadlineInDays }) => deadlineInDays <= 4))
        : 0
      const offer = candidates.splice(position, 1)[0]
      if (!offer) break
      const tiers = offer.tiers as Tier[]
      const last = tiers.length - 1
      let committed: number
      switch (stage) {
        case 'justUnlocked': committed = tiers[1]!.minShares + rng.int(0, 1); break
        case 'closeToNext': {
          const tier = rng.int(0, last - 1)
          committed = Math.max(tiers[tier]!.minShares, tiers[tier + 1]!.minShares - rng.int(1, 2))
          break
        }
        case 'atRisk': committed = Math.max(1, tiers[0]!.minShares - rng.int(2, 4)); break
        case 'best': committed = Math.min(offer.totalShares, tiers[last]!.minShares + rng.int(0, 3)); break
        default: committed = rng.int(2, Math.max(2, Math.min(4, tiers[0]!.minShares - 1)))
      }
      const orderId = `order-${slug}-${(orderNumber[slug] = (orderNumber[slug] ?? 0) + 1)}`
      const shares = distribute(group.id, committed, required).map(({ householdId, quantity }) => ({
        householdId, quantity, finalPriceCents: null, isPaid: false,
        suspendedAmountCents: householdId === 'household-amina' && index === 1 ? 500 : suspended(),
        subsidyCents: 0, qrCode: null, isPickedUp: false,
        ...(householdId === 'household-amina' && index < 3 ? { pickupSlotIndex: 0 } : {})
      }))
      const tierIndex = tierIndexFor(tiers, committed)
      groupOrders.push({
        id: orderId, groupId: group.id, offerId: offer.id,
        status: committed >= offer.minimumSharesToLaunch ? 'reached' : 'open',
        currentTierIndex: tierIndex, committedShares: committed, committedHouseholds: shares.length,
        pickupPointId: `pickup-${slug}-1`,
        pickupSlotsInDays: [
          { inDays: offer.deadlineInDays + 1, startHour: 16, endHour: 19 },
          { inDays: offer.deadlineInDays + 2, startHour: 10, endHour: 12 }
        ],
        shares
      })
    }
  }

  // Historique : commandes livrées (ou clôturées, en attente de cueillette) des lots terminés.
  let historyNumber = 0
  for (const offer of pastOffers) {
    const tiers = offer.tiers as Tier[]
    const productSlug = String(offer.productId).replace(/^product-/, '')
    for (const slug of offer.zones as string[]) {
      const groupId = `group-${slug}`
      const cancelled = cancelledPastOrders.has(`${productSlug}|${slug}`)
      const committed = cancelled ? rng.int(3, tiers[0]!.minShares - 2) : rng.int(tiers[0]!.minShares, 30)
      const tierIndex = cancelled ? null : tierIndexFor(tiers, committed)
      const unitPrice = tierIndex === null ? null : tiers[tierIndex]!.priceCents
      const delivered = offer.deadlineInDays <= -4
      const status = cancelled ? 'cancelled' : delivered ? 'delivered' : 'closed'
      const orderId = `order-${slug}-h${String(++historyNumber).padStart(2, '0')}`
      const required = slug === 'parc-extension'
        ? ['household-amina', ...(rng.next() < 0.6 ? ['household-jean'] : [])]
        : []
      const shares = distribute(groupId, committed, required).map(({ householdId, quantity }) => {
        const finalPriceCents = unitPrice === null ? null : unitPrice * quantity
        const subsidyCents = finalPriceCents !== null && subsidized.has(householdId)
          ? Math.min(finalPriceCents, Math.round(finalPriceCents / 2))
          : 0
        return {
          householdId, quantity, finalPriceCents,
          isPaid: status === 'delivered' || (status === 'closed' && rng.next() < 0.5),
          suspendedAmountCents: cancelled ? 0 : suspended(),
          subsidyCents,
          qrCode: cancelled ? null : pickupQRCode(orderId, householdId),
          isPickedUp: status === 'delivered'
        }
      })
      groupOrders.push({
        id: orderId, groupId, offerId: offer.id, status, currentTierIndex: tierIndex,
        committedShares: committed, committedHouseholds: shares.length,
        pickupPointId: `pickup-${slug}-1`,
        pickupSlotsInDays: [
          { inDays: offer.deadlineInDays + 2, startHour: 16, endHour: 19 },
          { inDays: offer.deadlineInDays + 3, startHour: 10, endHour: 12 }
        ],
        shares
      })
    }
  }

  // Envies des familles : quelques-unes par groupe, plus celles d'Amina.
  const wishes: Raw[] = [
    { id: 'wish-amina-1', groupId: 'group-parc-extension', householdId: 'household-amina', category: 'meat', unit: 'kg',
      productId: 'product-poulet-halal', quantity: 6, frequency: 'biweekly', wantedFromInDays: 0, wantedUntilInDays: 30, createdInDays: -6 },
    { id: 'wish-amina-2', groupId: 'group-parc-extension', householdId: 'household-amina', category: 'grains', unit: 'kg',
      productId: 'product-riz-basmati', quantity: 10, frequency: 'monthly', createdInDays: -12 },
    { id: 'wish-amina-3', groupId: 'group-parc-extension', householdId: 'household-amina', category: 'legumes', unit: 'kg',
      quantity: 4, frequency: 'monthly', createdInDays: -3 }
  ]
  for (const group of groups) {
    const slug = slugOf(group.id)
    const members = (membersOf.get(group.id) ?? []).filter((id) => id !== 'household-amina')
    const templates = halalNeighborhoods.has(slug) ? [...wishTemplates, ...halalTemplates, ...halalTemplates] : wishTemplates
    const count = Math.round((membersOf.get(group.id)?.length ?? 0) * 0.6)
    for (let index = 1; index <= count; index += 1) {
      const [category, unit, productId, min, max] = rng.pick(templates)
      const start = rng.next() < 0.5 ? rng.int(-3, 5) : null
      wishes.push({
        id: `wish-${slug}-${String(index).padStart(2, '0')}`, groupId: group.id, householdId: rng.pick(members),
        category, unit, ...(productId ? { productId } : {}), quantity: rng.int(min, max),
        frequency: rng.pick(['once', 'weekly', 'biweekly', 'biweekly', 'monthly', 'monthly']),
        ...(start === null ? {} : { wantedFromInDays: start, wantedUntilInDays: start + rng.int(14, 40) }),
        createdInDays: -rng.int(1, 25)
      })
    }
  }

  // Disponibilités des vendeurs.
  const supplyCount: Record<string, number> = {}
  const supplies = supplyDefinitions.map(([vendor, category, unit, productId, quantity, fromDays, toDays, zones]) => {
    const vendorId = `vendor-${vendor}`
    supplyCount[vendor] = (supplyCount[vendor] ?? 0) + 1
    return {
      id: `supply-${vendor}-${supplyCount[vendor]}`, vendorId, category, unit,
      ...(productId ? { productId } : {}), quantity,
      availableFromInDays: fromDays, availableToInDays: toDays,
      servedZones: zones === 'vendor' ? vendorZones.get(vendorId)! : zones,
      createdInDays: Math.min(fromDays, 0) - rng.int(1, 5)
    }
  })

  return {
    vendors, products, offers, groups, pickupPoints, users: clone(base.users), households, groupOrders, wishes, supplies
  }
}
