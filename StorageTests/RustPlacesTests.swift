/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest
import Shared
@testable import Client
@testable import Storage

class RustPlacesTests: XCTestCase {
    var files: FileAccessor!
    var places: RustPlaces!
    
    override func setUp() {
        files = MockFiles()

        let databasePath = URL(fileURLWithPath: (try! files.getAndEnsureDirectory()), isDirectory: true).appendingPathComponent("testplaces.db").path
        try? files.remove("testplaces.db")

        places = RustPlaces(databasePath: databasePath)
        _ = places.reopenIfClosed()
    }

    /**
        Basic "smoke tests" of the history metadata. Robust test suite exists within the library itself.
     */
    func testHistoryMetadataBasics() {
        XCTAssertTrue(places.deleteHistoryMetadataOlderThan(olderThan: 0).value.isSuccess)
        XCTAssertTrue(places.deleteHistoryMetadataOlderThan(olderThan: INT64_MAX).value.isSuccess)
        XCTAssertTrue(places.deleteHistoryMetadataOlderThan(olderThan: -1).value.isSuccess)

        let emptyRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertTrue(emptyRead.isSuccess)
        XCTAssertNotNil(emptyRead.successValue)
        XCTAssertEqual(emptyRead.successValue!.count, 0)
        
        // Observing facts one-by-one.
        let metadataKey1 = HistoryMetadataKey(url: "https://www.mozilla.org", searchTerm: nil, referrerUrl: nil)
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey1,
            observation: HistoryMetadataObservation(
                titleObservation: "Mozilla Test",
                viewTimeObservation: nil,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey1,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: 1,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey1,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: nil,
                documentTypeObservation: .regular
            )
        ).value.isSuccess)
        
        var singleItemRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertTrue(singleItemRead.isSuccess)
        XCTAssertNotNil(singleItemRead.successValue)
        XCTAssertEqual(singleItemRead.successValue!.count, 1)
        XCTAssertEqual(singleItemRead.successValue![0].title, "Mozilla Test")
        XCTAssertEqual(singleItemRead.successValue![0].documentType, DocumentType.regular)
        XCTAssertEqual(singleItemRead.successValue![0].totalViewTime, 1)
        
        // Able to aggregate total view time.
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey1,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: 11,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        
        singleItemRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(singleItemRead.successValue!.count, 1)
        XCTAssertEqual(singleItemRead.successValue![0].totalViewTime, 12)
        
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey1,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: 3,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        
        singleItemRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(singleItemRead.successValue!.count, 1)
        XCTAssertEqual(singleItemRead.successValue![0].totalViewTime, 15)
        
        // Able to change document type.
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey1,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: nil,
                documentTypeObservation: .media
            )
        ).value.isSuccess)
        
        singleItemRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(singleItemRead.successValue!.count, 1)
        XCTAssertEqual(singleItemRead.successValue![0].documentType, DocumentType.media)
        
        // Unable to change title.
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey1,
            observation: HistoryMetadataObservation(
                titleObservation: "New title",
                viewTimeObservation: nil,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        singleItemRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(singleItemRead.successValue!.count, 1)
        XCTAssertEqual(singleItemRead.successValue![0].title, "Mozilla Test")
    
        // Able to observe facts for multiple keys.
        let metadataKey2 = HistoryMetadataKey(url: "https://www.mozilla.org/another", searchTerm: nil, referrerUrl: "https://www.mozilla.org")
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey2,
            observation: HistoryMetadataObservation(
                titleObservation: "Another Mozilla",
                viewTimeObservation: nil,
                documentTypeObservation: nil
            )
        ).value.isSuccess)

        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey2,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: nil,
                documentTypeObservation: .regular
            )
        ).value.isSuccess)
        
        var multipleItemsRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(multipleItemsRead.successValue!.count, 2)
        
        // Observations for a different key unaffected.
        XCTAssertEqual(multipleItemsRead.successValue![0].documentType, DocumentType.regular)
        XCTAssertEqual(multipleItemsRead.successValue![0].title, "Another Mozilla")
        XCTAssertEqual(multipleItemsRead.successValue![0].totalViewTime, 0)
        XCTAssertEqual(multipleItemsRead.successValue![1].documentType, DocumentType.media)
        XCTAssertEqual(multipleItemsRead.successValue![1].title, "Mozilla Test")
        XCTAssertEqual(multipleItemsRead.successValue![1].totalViewTime, 15)
        
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey2,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: 25,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        multipleItemsRead = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(multipleItemsRead.successValue!.count, 2)
        XCTAssertEqual(multipleItemsRead.successValue![0].documentType, DocumentType.regular)
        XCTAssertEqual(multipleItemsRead.successValue![0].title, "Another Mozilla")
        XCTAssertEqual(multipleItemsRead.successValue![0].totalViewTime, 25)
        XCTAssertEqual(multipleItemsRead.successValue![1].documentType, DocumentType.media)
        XCTAssertEqual(multipleItemsRead.successValue![1].title, "Mozilla Test")
        XCTAssertEqual(multipleItemsRead.successValue![1].totalViewTime, 15)
        
        // Able to query by title.
        var queryResults = places.queryHistoryMetadata(query: "another", limit: 0).value
        XCTAssertEqual(queryResults.successValue!.count, 0)
        queryResults = places.queryHistoryMetadata(query: "another", limit: 10).value
        XCTAssertEqual(queryResults.successValue!.count, 1)
        queryResults = places.queryHistoryMetadata(query: "mozilla", limit: 10).value
        XCTAssertEqual(queryResults.successValue!.count, 2)
        
        // Able to query by url.
        let metadataKey3 = HistoryMetadataKey(url: "https://www.firefox.ru/download", searchTerm: nil, referrerUrl: "https://www.mozilla.org")
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey3,
            observation: HistoryMetadataObservation(
                titleObservation: "Скачать Фаерфокс",
                viewTimeObservation: nil,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        queryResults = places.queryHistoryMetadata(query: "firefox", limit: 10).value
        XCTAssertEqual(queryResults.successValue!.count, 1)
        XCTAssertEqual(queryResults.successValue![0].key.url, "https://www.firefox.ru/download")
        XCTAssertEqual(queryResults.successValue![0].title, "Скачать Фаерфокс")
        
        // Able to query by search term.
        let metadataKey4 = HistoryMetadataKey(url: "https://www.example.com", searchTerm: "Sample webpage", referrerUrl: nil)
        XCTAssertTrue(places.noteHistoryMetadataObservation(
            key: metadataKey4,
            observation: HistoryMetadataObservation(
                titleObservation: nil,
                viewTimeObservation: 1337,
                documentTypeObservation: nil
            )
        ).value.isSuccess)
        queryResults = places.queryHistoryMetadata(query: "sample", limit: 10).value
        XCTAssertEqual(queryResults.successValue!.count, 1)
        XCTAssertEqual(queryResults.successValue![0].key.url, "https://www.example.com/")
        
        // Able to delete.
        queryResults = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(queryResults.successValue!.count, 4)
        XCTAssertTrue(places.deleteHistoryMetadataOlderThan(olderThan: INT64_MAX).value.isSuccess)
        queryResults = places.getHistoryMetadataSince(since: 0).value
        XCTAssertEqual(queryResults.successValue!.count, 0)
    }
}
