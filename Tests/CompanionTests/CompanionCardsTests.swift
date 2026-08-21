import CompanionCore
import Foundation
import Testing

@Test @MainActor func companionCardsTests() {
    testLocationsCardParsing()
    testGalleryCardParsing()
    testInvalidLocationJSON()
    testInvalidGalleryJSON()
    testReportCutSeparation()
}

@MainActor func testLocationsCardParsing() {
    let json = """
    {
        "title": "Ubicaciones cercanas",
        "locations": [
            {
                "id": "loc-1",
                "name": "Oficina Principal",
                "lat": 19.4326,
                "lng": -99.1332,
                "address": "Calle Principal 123"
            }
        ]
    }
    """

    let block = CompanionBlocks.locations(json)
    expect(block != nil, "locations JSON parses successfully")
    expectEq(block?.locations.count, 1, "contains one location")
    expectEq(block?.locations[0].name, "Oficina Principal", "location name is correct")
}

@MainActor func testGalleryCardParsing() {
    let json = """
    {
        "title": "Galería",
        "images": [
            {
                "url": "https://example.com/image.jpg",
                "caption": "Imagen 1"
            }
        ]
    }
    """

    let block = CompanionBlocks.gallery(json)
    expect(block != nil, "gallery JSON parses successfully")
    expectEq(block?.images.count, 1, "contains one image")
}

@MainActor func testInvalidLocationJSON() {
    let invalidJSON = """
    {
        "locations": [
            {
                "name": "Missing lat/lng"
            }
        ]
    }
    """

    let block = CompanionBlocks.locations(invalidJSON)
    expect(block == nil, "invalid locations JSON returns nil (degrades to code)")
}

@MainActor func testInvalidGalleryJSON() {
    let invalidJSON = """
    {
        "images": []
    }
    """

    let block = CompanionBlocks.gallery(invalidJSON)
    expect(block == nil, "empty gallery returns nil (degrades to code)")
}

@MainActor func testReportCutSeparation() {
    let markdown = """
    Primera línea de resumen.

    ```companion:locations
    {"locations":[{"name":"Lugar","lat":0,"lng":0}]}
    ```

    Detalle que va atrás del pliegue.
    """

    let parts = MarkdownSplitter.split(markdown)
    let (summary, cards, detail) = MarkdownSplitter.reportCut(markdown)

    expect(!summary.isEmpty, "summary is not empty")
    expect(!cards.isEmpty, "cards section exists")
    expect(!detail.isEmpty, "detail section exists")
}
