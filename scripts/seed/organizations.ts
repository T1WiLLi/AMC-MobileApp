// Organismes de démo du portail Organismes (T-194, T-205) : la banque alimentaire de Côte-des-Neiges (le compte de
// démo) et quatre autres organismes montréalais fictifs, avec leurs dons, leurs parrainages, le fonds de solidarité
// des groupes qu'ils financent, une photo de profil et une bannière. Même schéma que l'app (`Organization.swift`,
// `FirestoreOrganizationRepository`) :
//   organizations/{orgId}                          profil + memberUserIds (lu par les membres seulement)
//   organizations/{orgId}/media/{logo|banner}      photo de profil et bannière (octets JPEG, 300 Kio au plus)
//   organizationDirectory/{orgId}                  fiche publique pour la carte des organismes : nom, type,
//                                                  quartier, position, dates des médias. Rien de privé.
//   organizations/{orgId}/donations/{donationId}   don simulé (montants entiers, en cents)
//   organizations/{orgId}/sponsorships/{groupId}   parrainage
//   groups/{groupId}/solidarity/fund               { entries, subsidizedHouseholds, basketPriceCents, sponsorOrganizationIds }
// Dates fixes (pas relatives à aujourd'hui) : relancer le seed est idempotent.
import { encodeGeohash } from './richDemo.ts'
import { toRestFields, type RestFields, type RestWrite } from './firestoreRest.ts'

/** Organisme du compte de démo (seed:org-member le rattache). */
export const organizationId = 'org-banque-alimentaire-cdn'
export const basketPriceCents = 2_600
export const directoryCollection = 'organizationDirectory'

export type GroupInfo = { id: string, name: string, neighborhood: string, centerGeohash: string }
export type OrganizationKind = 'foodBank' | 'communityCenter' | 'foundation' | 'localBusiness'

type DonationSeed = {
  id: string, groupId: string, kind: 'fund' | 'suspendedBaskets', amountCents: number
  householdsReached: number, date: Date
}
type SponsorshipSeed = { groupId: string, monthlyBasketGoal: number, startedAt: Date }
type FundSeed = { groupId: string, subsidizedHouseholds: number }

export type OrganizationDef = {
  id: string
  /** Préfixe des images dans media/organizations/ (`<slug>-logo.jpg`, `<slug>-banner.jpg`). */
  slug: string
  name: string
  kind: OrganizationKind
  neighborhood: string
  /** Siège (adresse publique d'un organisme, arrondie au geohash de 7 caractères, ≈ 150 m). */
  latitude: number
  longitude: number
  mission: string
  createdAt: Date
  donations: DonationSeed[]
  sponsorships: SponsorshipSeed[]
}

const date = (iso: string) => new Date(`${iso}T15:00:00Z`)
/** Date d'envoi des images du seed : fixe, pour que deux passages écrivent la même chose. */
export const mediaDate = date('2026-11-22')

export const logoImage = { width: 400, height: 400 }
export const bannerImage = { width: 1_200, height: 450 }

// Montants : un panier = 26 $. « fund » : le don libre paie floor(montant / 2600) paniers entiers.
export const demoOrganizations: OrganizationDef[] = [
  {
    id: organizationId, slug: 'banque-alimentaire-cdn', name: 'Banque alimentaire de Côte-des-Neiges', kind: 'foodBank',
    neighborhood: 'cote-des-neiges', latitude: 45.5005, longitude: -73.631,
    mission: 'Distribuer des paniers frais aux familles de Côte-des-Neiges et financer des paniers suspendus '
      + 'dans les groupes de quartier voisins.',
    createdAt: date('2026-03-01'),
    donations: [
      { id: 'don-cdn-2026-09', groupId: 'group-cote-des-neiges', kind: 'suspendedBaskets', amountCents: 26_000, householdsReached: 10, date: date('2026-09-05') },
      { id: 'don-cdn-2026-10', groupId: 'group-cote-des-neiges', kind: 'fund', amountCents: 15_600, householdsReached: 2, date: date('2026-10-03') },
      { id: 'don-parc-ex-2026-10', groupId: 'group-parc-extension', kind: 'fund', amountCents: 10_400, householdsReached: 4, date: date('2026-10-10') },
      { id: 'don-parc-ex-2026-11', groupId: 'group-parc-extension', kind: 'suspendedBaskets', amountCents: 13_000, householdsReached: 3, date: date('2026-11-02') },
      { id: 'don-rosemont-2026-11', groupId: 'group-rosemont', kind: 'fund', amountCents: 5_200, householdsReached: 2, date: date('2026-11-09') }
    ],
    sponsorships: [
      { groupId: 'group-cote-des-neiges', monthlyBasketGoal: 20, startedAt: date('2026-04-15') },
      { groupId: 'group-parc-extension', monthlyBasketGoal: 10, startedAt: date('2026-06-01') }
    ]
  },
  {
    id: 'org-epicerie-la-marmite', slug: 'epicerie-la-marmite', name: 'Épicerie solidaire La Marmite', kind: 'foodBank',
    neighborhood: 'hochelaga', latitude: 45.5512, longitude: -73.5355,
    mission: 'Une épicerie à prix solidaires sur la rue Ontario : fruits, légumes et produits secs pour les familles '
      + 'd\'Hochelaga, et des paniers suspendus pour celles qui en ont besoin.',
    createdAt: date('2026-02-10'),
    donations: [
      { id: 'don-marmite-2026-09', groupId: 'group-hochelaga', kind: 'suspendedBaskets', amountCents: 15_600, householdsReached: 6, date: date('2026-09-18') },
      { id: 'don-marmite-2026-11', groupId: 'group-hochelaga', kind: 'fund', amountCents: 7_800, householdsReached: 3, date: date('2026-11-06') }
    ],
    sponsorships: [{ groupId: 'group-hochelaga', monthlyBasketGoal: 12, startedAt: date('2026-05-04') }]
  },
  {
    id: 'org-centre-les-pommiers', slug: 'centre-les-pommiers', name: 'Centre communautaire Les Pommiers', kind: 'communityCenter',
    neighborhood: 'saint-michel', latitude: 45.5598, longitude: -73.6085,
    mission: 'Cuisines collectives, aide aux devoirs et dépannage alimentaire à Saint-Michel. Nous parrainons les '
      + 'groupes d\'achat du nord-est de l\'île.',
    createdAt: date('2026-01-20'),
    donations: [
      { id: 'don-pommiers-2026-08', groupId: 'group-saint-michel', kind: 'fund', amountCents: 20_800, householdsReached: 7, date: date('2026-08-22') },
      { id: 'don-pommiers-2026-10', groupId: 'group-saint-michel', kind: 'suspendedBaskets', amountCents: 10_400, householdsReached: 4, date: date('2026-10-14') },
      { id: 'don-pommiers-mtl-nord-2026-11', groupId: 'group-montreal-nord', kind: 'suspendedBaskets', amountCents: 7_800, householdsReached: 3, date: date('2026-11-12') }
    ],
    sponsorships: [{ groupId: 'group-saint-michel', monthlyBasketGoal: 8, startedAt: date('2026-03-15') }]
  },
  {
    id: 'org-fondation-rives-verdun', slug: 'fondation-rives-verdun', name: 'Fondation Rives de Verdun', kind: 'foundation',
    neighborhood: 'verdun', latitude: 45.4635, longitude: -73.5662,
    mission: 'Une fondation de quartier financée par des commerces et des résidents de Verdun : chaque dollar va à '
      + 'des paniers pour les familles du sud-ouest.',
    createdAt: date('2025-11-05'),
    donations: [
      { id: 'don-rives-verdun-2026-07', groupId: 'group-verdun', kind: 'fund', amountCents: 52_000, householdsReached: 5, date: date('2026-07-08') },
      { id: 'don-rives-verdun-2026-10', groupId: 'group-verdun', kind: 'suspendedBaskets', amountCents: 26_000, householdsReached: 5, date: date('2026-10-20') }
    ],
    sponsorships: [{ groupId: 'group-verdun', monthlyBasketGoal: 15, startedAt: date('2026-02-01') }]
  },
  {
    id: 'org-panier-de-villeray', slug: 'panier-de-villeray', name: 'Épicerie Le Panier de Villeray', kind: 'localBusiness',
    neighborhood: 'villeray', latitude: 45.5388, longitude: -73.6148,
    mission: 'Fruiterie de quartier près du marché Jarry. Nous arrondissons les achats de nos clients pour offrir '
      + 'des paniers aux familles de Villeray.',
    createdAt: date('2026-06-12'),
    donations: [
      { id: 'don-panier-villeray-2026-11', groupId: 'group-villeray', kind: 'suspendedBaskets', amountCents: 7_800, householdsReached: 3, date: date('2026-11-03') }
    ],
    sponsorships: []
  }
]

/** Tous les dons, avec leur organisme. */
export const demoDonations = demoOrganizations.flatMap((organization) =>
  organization.donations.map((donation) => ({ ...donation, organizationId: organization.id })))

export const demoFunds: FundSeed[] = [
  { groupId: 'group-cote-des-neiges', subsidizedHouseholds: 12 },
  { groupId: 'group-parc-extension', subsidizedHouseholds: 8 },
  { groupId: 'group-rosemont', subsidizedHouseholds: 4 },
  { groupId: 'group-hochelaga', subsidizedHouseholds: 9 },
  { groupId: 'group-saint-michel', subsidizedHouseholds: 10 },
  { groupId: 'group-montreal-nord', subsidizedHouseholds: 7 },
  { groupId: 'group-verdun', subsidizedHouseholds: 6 },
  { groupId: 'group-villeray', subsidizedHouseholds: 3 }
]

export function basketCount(donation: { kind: 'fund' | 'suspendedBaskets', amountCents: number }): number {
  return Math.floor(donation.amountCents / basketPriceCents)
}

export function geohashOf(organization: Pick<OrganizationDef, 'latitude' | 'longitude'>): string {
  return encodeGeohash(organization.latitude, organization.longitude, 7)
}

/** Documents des organismes de démo (valeurs JS : `Date` pour les timestamps). */
export function buildOrganizationSeed(groups: GroupInfo[]) {
  const byId = new Map(groups.map((group) => [group.id, group]))
  const group = (id: string) => {
    const found = byId.get(id)
    if (!found) throw new Error(`Groupe de démo introuvable : ${id}`)
    return found
  }
  const organizations = demoOrganizations.map((organization) => {
    const geohash = geohashOf(organization)
    const publicFields = {
      name: organization.name, kind: organization.kind, neighborhood: organization.neighborhood, geohash,
      photoUpdatedAt: mediaDate, bannerUpdatedAt: mediaDate
    }
    return {
      id: organization.id,
      profile: { id: organization.id, ...publicFields, mission: organization.mission, createdAt: organization.createdAt },
      directory: { id: organization.id, ...publicFields },
      media: [
        { path: `organizations/${organization.id}/media/logo`, file: `organizations/${organization.slug}-logo.jpg`, ...logoImage },
        { path: `organizations/${organization.id}/media/banner`, file: `organizations/${organization.slug}-banner.jpg`, ...bannerImage }
      ]
    }
  })
  const donations = demoDonations.map((donation) => {
    const baskets = basketCount(donation)
    return {
      path: `organizations/${donation.organizationId}/donations/${donation.id}`,
      data: {
        id: donation.id, organizationId: donation.organizationId, groupId: donation.groupId,
        groupName: group(donation.groupId).name, kind: donation.kind, amountCents: donation.amountCents,
        basketCount: baskets, householdsReached: Math.min(donation.householdsReached, baskets), date: donation.date,
        isSimulated: true
      }
    }
  })
  const sponsorships = demoOrganizations.flatMap((organization) => organization.sponsorships.map((sponsorship) => ({
    path: `organizations/${organization.id}/sponsorships/${sponsorship.groupId}`,
    data: {
      id: sponsorship.groupId, organizationId: organization.id, groupName: group(sponsorship.groupId).name,
      neighborhood: group(sponsorship.groupId).neighborhood,
      monthlyBasketGoal: sponsorship.monthlyBasketGoal, startedAt: sponsorship.startedAt
    }
  })))
  const funds = demoFunds.map((fund) => ({
    groupId: fund.groupId,
    path: `groups/${fund.groupId}/solidarity/fund`,
    data: {
      // Une ligne par don, comme `FirestoreOrganizationRepository.donate` : la ligne nomme le don et son organisme.
      entries: demoDonations.filter(({ groupId }) => groupId === fund.groupId).map((donation) => ({
        kind: 'contribution', amountCents: donation.amountCents, basketCount: 0, date: donation.date,
        donationId: donation.id, organizationId: donation.organizationId
      })),
      subsidizedHouseholds: fund.subsidizedHouseholds,
      basketPriceCents,
      sponsorOrganizationIds: demoOrganizations
        .filter((organization) => organization.sponsorships.some(({ groupId }) => groupId === fund.groupId))
        .map(({ id }) => id)
    }
  }))
  return { organizations, donations, sponsorships, funds }
}

export type OrganizationSeed = ReturnType<typeof buildOrganizationSeed>
export type Existing = { organizations: Set<string>, funds: Set<string> }

/**
 * Écritures REST du seed (sans les images). Rien n'est supprimé, et ce qui existe déjà est ménagé :
 *   - organisme présent : seuls les champs de profil sont réécrits (`memberUserIds` reste intact) ;
 *   - fiche publique (`organizationDirectory`) : réécrite en entier, elle ne contient que des champs publics ;
 *   - fonds présent : les lignes de démo et les parrainages sont ajoutés s'ils manquent (appendMissingElements),
 *     jamais de réécriture : le solde réel du groupe est conservé.
 */
export function planOrganizationWrites(seed: OrganizationSeed, existing: Existing, docName: (path: string) => string): RestWrite[] {
  const writes: RestWrite[] = []
  for (const organization of seed.organizations) {
    const path = `organizations/${organization.id}`
    writes.push(existing.organizations.has(organization.id)
      ? {
          update: { name: docName(path), fields: toRestFields(organization.profile) },
          updateMask: { fieldPaths: Object.keys(organization.profile) },
          currentDocument: { exists: true }
        }
      : {
          update: { name: docName(path), fields: toRestFields({ ...organization.profile, memberUserIds: [] }) },
          currentDocument: { exists: false }
        })
    writes.push({ update: { name: docName(`${directoryCollection}/${organization.id}`), fields: toRestFields(organization.directory) } })
  }
  for (const { path, data } of [...seed.donations, ...seed.sponsorships]) {
    writes.push({ update: { name: docName(path), fields: toRestFields(data) } })
  }
  for (const fund of seed.funds) {
    if (!existing.funds.has(fund.groupId)) {
      writes.push({ update: { name: docName(fund.path), fields: toRestFields(fund.data) }, currentDocument: { exists: false } })
      continue
    }
    const values = (list: unknown[]) => (toRestFields({ list }).list as { arrayValue: { values: Record<string, unknown>[] } }).arrayValue.values
    writes.push({
      update: { name: docName(fund.path), fields: {} as RestFields },
      updateMask: { fieldPaths: [] },
      updateTransforms: [
        { fieldPath: 'entries', appendMissingElements: { values: values(fund.data.entries) } },
        ...(fund.data.sponsorOrganizationIds.length === 0 ? [] : [
          { fieldPath: 'sponsorOrganizationIds', appendMissingElements: { values: values(fund.data.sponsorOrganizationIds) } }
        ])
      ],
      currentDocument: { exists: true }
    })
  }
  return writes
}

/** Écritures des images (photo de profil et bannière), même format que les médias de groupe. */
export function planOrganizationMediaWrites(
  seed: OrganizationSeed, bytesOf: (file: string) => Buffer, docName: (path: string) => string
): RestWrite[] {
  return seed.organizations.flatMap((organization) => organization.media.map((media) => {
    const data = bytesOf(media.file)
    if (data.length === 0 || data.length > 300 * 1024) throw new Error(`${media.file} : ${data.length} octets (300 Kio au plus)`)
    return {
      update: {
        name: docName(media.path),
        fields: {
          data: { bytesValue: data.toString('base64') },
          contentType: { stringValue: 'image/jpeg' },
          width: { integerValue: String(media.width) },
          height: { integerValue: String(media.height) },
          updatedAt: { timestampValue: mediaDate.toISOString() }
        }
      }
    }
  }))
}

export function describeSeed(seed: OrganizationSeed): string[] {
  const cents = (value: number) => `${(value / 100).toFixed(2)} $`
  return [
    ...seed.organizations.map((organization) => {
      const donations = seed.donations.filter(({ data }) => data.organizationId === organization.id)
      const sponsorships = seed.sponsorships.filter(({ data }) => data.organizationId === organization.id)
      return `Organisme : ${organization.profile.name} (${organization.id}, ${organization.profile.geohash}) : ` +
        `${donations.length} don(s), ${cents(donations.reduce((sum, { data }) => sum + data.amountCents, 0))}, ` +
        `${sponsorships.length} parrainage(s), photo + bannière`
    }),
    ...seed.funds.map((fund) =>
      `Fonds ${fund.groupId} : ${fund.data.entries.length} contribution(s), ` +
      `${cents(fund.data.entries.reduce((sum, { amountCents }) => sum + amountCents, 0))}, ` +
      `${fund.data.subsidizedHouseholds} ménage(s) aidé(s)`)
  ]
}

/** Écritures du rattachement d'un compte : `users/{uid}.organizationId` + rôle, et l'uid dans `memberUserIds`. */
export function planMemberWrites(uid: string, docName: (path: string) => string): RestWrite[] {
  return [
    {
      update: { name: docName(`users/${uid}`), fields: toRestFields({ organizationId }) },
      updateMask: { fieldPaths: ['organizationId'] },
      updateTransforms: [{ fieldPath: 'roles', appendMissingElements: { values: [{ stringValue: 'organization' }] } }],
      currentDocument: { exists: true }
    },
    {
      update: { name: docName(`organizations/${organizationId}`), fields: {} },
      updateMask: { fieldPaths: [] },
      updateTransforms: [{ fieldPath: 'memberUserIds', appendMissingElements: { values: [{ stringValue: uid }] } }],
      currentDocument: { exists: true }
    }
  ]
}
