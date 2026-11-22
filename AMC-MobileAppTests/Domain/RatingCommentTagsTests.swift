import Testing
@testable import AMC_MobileApp

/// Mots rapides de la feuille d'avis : ajout au commentaire, retrait, limite de longueur.
struct RatingCommentTagsTests {
    @Test func addsTagToEmptyComment() {
        #expect(RatingCommentTags.toggled("Bonne ambiance", in: "", maxLength: 280) == "Bonne ambiance")
        #expect(RatingCommentTags.toggled("Bonne ambiance", in: "   ", maxLength: 280) == "Bonne ambiance")
    }

    @Test func appendsAfterCommaOrSentence() {
        #expect(RatingCommentTags.toggled("Bien organisé", in: "Bonne ambiance", maxLength: 280)
                == "Bonne ambiance, bien organisé")
        #expect(RatingCommentTags.toggled("Bien organisé", in: "On adore le groupe !", maxLength: 280)
                == "On adore le groupe ! Bien organisé")
    }

    @Test func removesTagAndCleansCommas() {
        #expect(RatingCommentTags.toggled("Bien organisé", in: "Bonne ambiance, bien organisé", maxLength: 280)
                == "Bonne ambiance")
        #expect(RatingCommentTags.toggled("Bonne ambiance", in: "Bonne ambiance, bien organisé", maxLength: 280)
                == "Bien organisé")
        #expect(RatingCommentTags.toggled("Bien organisé", in: "Bonne ambiance, bien organisé, prix avantageux",
                                          maxLength: 280) == "Bonne ambiance, prix avantageux")
        #expect(RatingCommentTags.toggled("Bonne ambiance", in: "Bonne ambiance", maxLength: 280) == "")
    }

    @Test func detectsTagIgnoringCase() {
        #expect(RatingCommentTags.contains("Bien organisé", in: "Super, bien organisé"))
        #expect(!RatingCommentTags.contains("Bon prix", in: "Super ambiance"))
    }

    @Test func refusesTagThatWouldExceedLimit() {
        #expect(RatingCommentTags.toggled("Bonne ambiance", in: "Super", maxLength: 10) == nil)
    }

    @Test func suggestionsAreNonEmpty() {
        #expect(RatingCommentTags.group.count == 5)
        #expect(RatingCommentTags.vendor.count == 5)
    }
}
