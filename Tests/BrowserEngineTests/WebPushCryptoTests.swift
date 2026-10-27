import XCTest
@testable import BrowserEngine

final class WebPushCryptoTests: XCTestCase {
    /// El ejemplo del apéndice A del RFC 8291.
    func testDecryptsTheRFC8291Example() throws {
        let keys = WebPushKeys(
            privateKey: try XCTUnwrap(Data(base64URLEncoded: "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94")),
            authSecret: try XCTUnwrap(Data(base64URLEncoded: "BTBZMqHH6r4Tts7J_aSIgg"))
        )
        XCTAssertEqual(keys.publicKey.base64URLEncodedString,
                       "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4")
        let body = try XCTUnwrap(Data(base64URLEncoded: "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"))

        let plaintext = try keys.decrypt(body)

        XCTAssertEqual(String(data: plaintext, encoding: .utf8), "When I grow up, I want to be a watermelon")
    }

    func testRejectsAMessageForAnotherSubscription() throws {
        let body = try XCTUnwrap(Data(base64URLEncoded: "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"))
        XCTAssertThrowsError(try WebPushKeys.generate().decrypt(body))
    }
}
