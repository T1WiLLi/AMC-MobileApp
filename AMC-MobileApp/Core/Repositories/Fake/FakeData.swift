// FakeData.swift
// Jeu de données fake réaliste (Montréal) pour les dépôts en mémoire et les previews.
// Le seed complet de démo (E16, fixtures JSON) viendra séparément ; ce jeu reste petit et stable.

import Foundation

nonisolated struct FakeData: Sendable {
    var users: [AppUser]
    var households: [Household]
    var groups: [NeighborhoodGroup]
    /// Membres par id de groupe.
    var members: [String: [GroupMember]]
    var vendors: [Vendor]
    var products: [Product]
    var offers: [Offer]
    var groupOrders: [GroupOrder]
    /// Parts par id de commande groupée.
    var shares: [String: [Share]]
    var pickupPoints: [PickupPoint]
    /// B-056 : invitations à usage unique des groupes privés.
    var invitations: [GroupInvitation] = []

    /// Ids utiles dans les previews et les tests.
    enum ID {
        static let amina = "user-amina"
        static let aminaHousehold = "household-benali"
        static let saintMichel = "group-saint-michel"
        static let hochelaga = "group-hochelaga"
        /// B-056 : groupe privé créé par Amina, sur invitation seulement.
        static let villerayKitchen = "group-villeray-prive"
        static let fermeRive = "vendor-ferme-rive"
        static let moulinsDuNord = "vendor-moulins-du-nord"
        static let potatoes = "product-pommes-de-terre"
        static let rice = "product-riz-basmati"
        static let apples = "product-pommes-cortland"
        static let potatoOffer = "offer-pommes-de-terre"
        static let riceOffer = "offer-riz-basmati"
        static let appleOffer = "offer-pommes-cortland"
        static let potatoOrder = "order-saint-michel-pommes-de-terre"
        static let jarryPickup = "pickup-jarry"
        static let pieIXPickup = "pickup-pie-ix"
        static let communityPickup = "pickup-centre-saint-michel"
        static let fournil = "vendor-fournil"
        static let jardinsUrbains = "vendor-jardins-urbains"
    }

    /// Saint-Michel : la commande de pommes de terre est à 19 parts, la part d'Amina fait franchir le palier de 20.
    static let montreal: FakeData = {
        let now = Date.now
        let day: TimeInterval = 86_400
        let saturday = now.addingTimeInterval(3 * day)
        let slot = PickupSlot(start: saturday, end: saturday.addingTimeInterval(3 * 3_600))

        let neighborHouseholds = (1...11).map { index in
            Household(id: "household-voisin-\(index)", name: "Voisins \(index)", size: 2 + index % 4,
                      geohash: "f25dv", userIds: [])
        }
        let saintMichelMembers =
            [GroupMember(householdId: ID.aminaHousehold, role: .coordinator, joinedAt: now.addingTimeInterval(-30 * day))]
            + neighborHouseholds.map { GroupMember(householdId: $0.id, role: .member, joinedAt: now.addingTimeInterval(-10 * day)) }

        // B-056 : Amina a créé un groupe privé avec trois voisins.
        let villerayMembers =
            [GroupMember(householdId: ID.aminaHousehold, role: .coordinator, joinedAt: now.addingTimeInterval(-20 * day))]
            + neighborHouseholds.prefix(3).map { GroupMember(householdId: $0.id, role: .member, joinedAt: now.addingTimeInterval(-5 * day)) }

        // 19 parts réparties sur 11 ménages voisins (Amina n'a pas encore pris la sienne).
        let quantities = [2, 1, 3, 1, 2, 1, 2, 2, 1, 2, 2]
        let potatoShares = zip(neighborHouseholds, quantities).map { household, quantity in
            Share(householdId: household.id, quantity: quantity, finalPriceCents: nil, isPaid: false,
                  suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false)
        }

        let potatoOffer = Offer(
            id: ID.potatoOffer, vendorId: ID.fermeRive, productId: ID.potatoes, totalShares: 40,
            share: ShareSpec(container: .bag, weight: .init(10, .kilogram), valueCents: 1_599),
            tiers: [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990),
                    PriceTier(minShares: 30, priceCents: 850)],
            minimumSharesToLaunch: 10, deadline: now.addingTimeInterval(2 * day), zones: ["f25d", "f25e"], status: .active
        )

        return FakeData(
            users: [
                AppUser(id: ID.amina, displayName: "Amina Benali", photoURL: DemoMedia.aminaAvatar, language: .french,
                        roles: [.family, .host], neighborhood: "Saint-Michel", dietaryPreferences: [.halal],
                        seniorMode: false, householdId: ID.aminaHousehold, vendorId: nil),
            ],
            households: [
                Household(id: ID.aminaHousehold, name: "Famille Benali", size: 5, geohash: "f25dv", userIds: [ID.amina]),
            ] + neighborHouseholds,
            groups: [
                NeighborhoodGroup(id: ID.saintMichel, name: "Voisins de Saint-Michel", neighborhood: "Saint-Michel",
                                  centerGeohash: "f25dv", radiusMeters: 1_200, coordinatorIds: [ID.amina],
                                  householdCount: saintMichelMembers.count, isPublic: true, inviteCode: "SM-2026",
                                  branding: GroupBranding(displayName: "Saint-Michel en commun", emblem: "leaf.fill",
                                                          accentLight: "#1E6B52", accentDark: "#5FC9A0",
                                                          welcomeMessage: "Bienvenue chez les voisins de Saint-Michel !"),
                                  photoURL: DemoMedia.saintMichelPhoto, bannerURL: DemoMedia.saintMichelBanner),
                NeighborhoodGroup(id: ID.hochelaga, name: "Hochelaga solidaire", neighborhood: "Hochelaga",
                                  centerGeohash: "f25ej", radiusMeters: 900, coordinatorIds: [],
                                  householdCount: 27, isPublic: true, inviteCode: "HO-2026",
                                  branding: GroupBranding(emblem: "heart.circle.fill", accentLight: "#8E3B8F",
                                                          accentDark: "#D79BE0",
                                                          welcomeMessage: "Hochelaga, on se serre les coudes."),
                                  photoURL: DemoMedia.hochelagaPhoto, bannerURL: DemoMedia.hochelagaBanner),
                // B-056 : groupe privé, jamais listé ; on y entre avec une invitation d'Amina.
                NeighborhoodGroup(id: ID.villerayKitchen, name: "Cuisine collective Villeray", neighborhood: "Villeray",
                                  centerGeohash: "f25du", radiusMeters: 1_000, coordinatorIds: [ID.amina],
                                  householdCount: villerayMembers.count, isPublic: false, inviteCode: "",
                                  branding: GroupBranding(emblem: "fork.knife.circle.fill", accentLight: "#A0442C",
                                                          accentDark: "#F0A58C",
                                                          welcomeMessage: "Bienvenue à la cuisine collective !"),
                                  createdBy: ID.amina),
            ],
            members: [ID.saintMichel: saintMichelMembers, ID.villerayKitchen: villerayMembers],
            vendors: [
                Vendor(id: ID.fermeRive, legalName: "Ferme Bio-Rive", kind: .farm,
                       description: "Légumes biologiques cultivés à Mirabel depuis 1998.",
                       photoURLs: [DemoMedia.marcheBanner, DemoMedia.marchePhoto, DemoMedia.saintMichelBanner], servedZones: ["f25d", "f25e"], averageRating: 4.7, isVerified: true,
                       storefrontGeohash: "f25dvuh", city: "Mirabel",
                       memberSince: now.addingTimeInterval(-420 * day)),
                Vendor(id: ID.moulinsDuNord, legalName: "Les Moulins du Nord", kind: .wholesaler,
                       description: "Grossiste en céréales et légumineuses, entrepôt à Laval.",
                       photoURLs: [], servedZones: ["f25d"], averageRating: 4.4, isVerified: true,
                       storefrontGeohash: "f25dvrh", city: "Laval",
                       memberSince: now.addingTimeInterval(-300 * day)),
                // Producteurs du quartier, sans lot ouvert : visibles sur la carte des familles (T-091).
                Vendor(id: ID.fournil, legalName: "Le Fournil du coin", kind: .bakery,
                       description: "Boulangerie de quartier : pains au levain et viennoiseries du jour.",
                       photoURLs: [], servedZones: ["f25dv"], averageRating: 4.9, isVerified: true,
                       storefrontGeohash: "f25dve7", city: "Montréal",
                       memberSince: now.addingTimeInterval(-95 * day)),
                Vendor(id: ID.jardinsUrbains, legalName: "Coop Les Jardins urbains", kind: .cooperative,
                       description: "Coopérative de jardins sur les toits : fines herbes, tomates et miel.",
                       photoURLs: [], servedZones: ["f25dv"], averageRating: nil, isVerified: false,
                       storefrontGeohash: "f25dvm2", city: "Montréal",
                       memberSince: now.addingTimeInterval(-12 * day)),
            ],
            products: [
                Product(id: ID.potatoes, vendorId: ID.fermeRive, name: "Pommes de terre jaunes", category: .produce,
                        unit: "sac de 10 kg", origin: "Mirabel, QC", tags: [.organic, .local], photoURL: nil,
                        referenceGroceryPriceCents: 1_599),
                Product(id: ID.apples, vendorId: ID.fermeRive, name: "Pommes Cortland", category: .produce,
                        unit: "caisse de 5 kg", origin: "Rougemont, QC", tags: [.local], photoURL: nil,
                        referenceGroceryPriceCents: 1_499),
                Product(id: ID.rice, vendorId: ID.moulinsDuNord, name: "Riz basmati", category: .grains,
                        unit: "sac de 10 kg", origin: "Importé", tags: [.halal, .vegan], photoURL: nil,
                        referenceGroceryPriceCents: 2_899),
            ],
            offers: [
                potatoOffer,
                Offer(id: ID.riceOffer, vendorId: ID.moulinsDuNord, productId: ID.rice, totalShares: 30,
                      share: ShareSpec(container: .bag, weight: .init(10, .kilogram), valueCents: 2_899),
                      tiers: [PriceTier(minShares: 8, priceCents: 2_300), PriceTier(minShares: 16, priceCents: 1_990)],
                      minimumSharesToLaunch: 8, deadline: now.addingTimeInterval(4 * day), zones: ["f25d"], status: .active),
                Offer(id: ID.appleOffer, vendorId: ID.fermeRive, productId: ID.apples, totalShares: 25,
                      share: ShareSpec(container: .crate, weight: .init(5, .kilogram), valueCents: 1_499),
                      tiers: [PriceTier(minShares: 5, priceCents: 1_100), PriceTier(minShares: 15, priceCents: 950)],
                      minimumSharesToLaunch: 5, deadline: now.addingTimeInterval(6 * day), zones: ["f25e"], status: .active),
            ],
            groupOrders: [
                GroupOrder(id: ID.potatoOrder, groupId: ID.saintMichel, offerId: ID.potatoOffer, status: .reached,
                           currentTierIndex: potatoOffer.tierIndex(forCommittedShares: 19),
                           committedShares: 19, committedHouseholds: potatoShares.count,
                           pickupPointId: ID.jarryPickup, pickupSlots: [slot]),
            ],
            shares: [ID.potatoOrder: potatoShares],
            pickupPoints: [
                PickupPoint(id: ID.jarryPickup, hostUserId: ID.amina, name: "Chez Amina, rue Jarry",
                            address: "Rue Jarry Est, Saint-Michel, Montréal", photoURL: nil, capacity: 25,
                            accessibility: [.stepFree, .nearMetro], slots: [slot], geohash: "f25dvs2"),
                PickupPoint(id: ID.pieIXPickup, hostUserId: "user-karim", name: "Chez Karim, boul. Pie-IX",
                            address: "8150 boul. Pie-IX, Saint-Michel, Montréal", photoURL: nil, capacity: 15,
                            accessibility: [.parking],
                            slots: PickupSlotBook.consecutiveSlots(from: saturday.addingTimeInterval(-2 * 3_600),
                                                                   count: 3, duration: 3_600, capacity: 6),
                            geohash: "f25dvk4"),
                PickupPoint(id: ID.communityPickup, hostUserId: "user-sylvie",
                            name: "Centre communautaire Saint-Michel",
                            address: "7501 rue François-Perrault, Saint-Michel, Montréal", photoURL: nil, capacity: 60,
                            accessibility: [.wheelchair, .stepFree, .elevator, .nearMetro],
                            slots: PickupSlotBook.consecutiveSlots(from: saturday, count: 4, duration: 1_800,
                                                                   capacity: 10),
                            geohash: "f25dv94"),
            ],
            invitations: [
                GroupInvitation(code: "VIL4K7", groupId: ID.villerayKitchen, createdBy: ID.amina,
                                createdAt: now.addingTimeInterval(-2 * 3_600)),
                GroupInvitation(code: "VILR2M", groupId: ID.villerayKitchen, createdBy: ID.amina,
                                createdAt: now.addingTimeInterval(-6 * day), usedBy: "household-voisin-3",
                                usedAt: now.addingTimeInterval(-5 * day)),
                GroupInvitation(code: "VILX9P", groupId: ID.villerayKitchen, createdBy: ID.amina,
                                createdAt: now.addingTimeInterval(-4 * day), revokedAt: now.addingTimeInterval(-3 * day)),
            ]
        )
    }()
}

/// Photos de démo (T-122) : images Unsplash du catalogue d'assets (crédits dans docs/credits.md).
nonisolated enum DemoMedia {
    static let aminaAvatar = MediaURL.asset("AvatarAmina")
    static let saintMichelPhoto = MediaURL.asset("GroupPhotoSaintMichel")
    static let saintMichelBanner = MediaURL.asset("BannerSaintMichel")
    static let hochelagaPhoto = MediaURL.asset("GroupPhotoHochelaga")
    static let hochelagaBanner = MediaURL.asset("BannerHochelaga")
    static let marchePhoto = MediaURL.asset("GroupPhotoMarche")
    static let marcheBanner = MediaURL.asset("BannerMarche")
    /// Voisins pour les piles d'avatars des previews.
    static let neighbors = ["AvatarVoisin1", "AvatarVoisin2", "AvatarVoisin3"].map(MediaURL.asset)
}
