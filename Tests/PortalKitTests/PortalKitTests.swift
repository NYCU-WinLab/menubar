import Foundation
import Testing
@testable import PortalKit

/// Decodes real answers from portal.winlab.tw (sandbox copies, member names
/// replaced) with the generated types.
@Suite struct ContractDecoding {
    @Test func nowPlayingWithASong() throws {
        let json = #"""
        {"current":{"id":"c0a8c1b1-00e5-406b-98ef-07b2d0e71e8b","status":"playing","addedAs":"queue","fromPlaylist":true,"track":{"videoId":"fIOTDdOwaCA","title":"Only When I Look into Your Eyes","artist":"Fiji Blue","durationS":200,"thumbnail":"https://example.com/a.jpg","createdAt":"2026-10-24T08:19:09.034Z"},"addedBy":"成員","endedBy":null,"startedAt":"2026-10-24T08:38:39.247Z","endedAt":null},"paused":false,"volume":55,"autoplay":true,"positionS":12.5,"state":"playing","error":null,"online":true}
        """#
        let out = try PortalClient.decoder.decode(NowPlaying.Output.self, from: Data(json.utf8))
        #expect(out.current?.track.title == "Only When I Look into Your Eyes")
        #expect(out.current?.addedAs == .queue)
        #expect(out.state == .playing)
        #expect(out.current?.startedAt != nil)
    }

    @Test func nowPlayingIdle() throws {
        let json = #"{"current":null,"paused":false,"volume":40,"autoplay":true,"positionS":0,"state":"idle","error":null,"online":false}"#
        let out = try PortalClient.decoder.decode(NowPlaying.Output.self, from: Data(json.utf8))
        #expect(out.current == nil)
    }

    @Test func unknownEnumValueAndExtraKeysDecode() throws {
        let json = #"{"current":null,"paused":true,"volume":40,"autoplay":true,"positionS":0,"state":"buffering","error":null,"online":true,"newField":1}"#
        let out = try PortalClient.decoder.decode(NowPlaying.Output.self, from: Data(json.utf8))
        #expect(out.state == .unknown)
    }

    @Test func missingRequiredKeyFails() {
        let json = #"{"current":null,"paused":true,"autoplay":true,"positionS":0,"state":"idle","error":null,"online":true}"#
        #expect(throws: DecodingError.self) {
            try PortalClient.decoder.decode(NowPlaying.Output.self, from: Data(json.utf8))
        }
    }

    @Test func inputsEncodeWithoutNils() throws {
        let data = try JSONEncoder().encode(ListBentoOrders.Input(limit: 5, status: .open))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["status"] as? String == "open")
        let empty = try JSONEncoder().encode(ListMeetings.Input())
        #expect(String(decoding: empty, as: UTF8.self) == "{}")
    }

    @Test func datesWithAndWithoutMilliseconds() {
        #expect(PortalClient.parseDate("2026-10-24T08:19:09.034Z") != nil)
        #expect(PortalClient.parseDate("2026-10-24T08:19:09Z") != nil)
        #expect(PortalClient.parseDate("2026-10-24") == nil)
    }
}

@Suite struct Alignment {
    @Test func reportsMissingAndChangedActions() {
        let used: [String: (app: String, hash: String)] = [
            "a": (app: "music", hash: "1"), "b": (app: "music", hash: "2"), "c": (app: "door", hash: "3"),
        ]
        let remote = [
            RemoteAction(name: "a", app: "music", hash: "1"),
            RemoteAction(name: "b", app: "music", hash: "changed"),
        ]
        let status = ContractStatus(remote: remote, used: used)
        #expect(status.missing == ["c"])
        #expect(status.changed == ["b"])
    }

    @Test func everyUsedActionIsInTheTable() {
        let names = [
            Whoami.name, NowPlaying.name, ListQueue.name, SetPaused.name, SkipSong.name, SetVolume.name,
            GetDoorStatus.name, OpenDoor.name, GetNextLabMeeting.name, ListBentoOrders.name,
            GetBentoOrder.name, AddBentoOrderItem.name, ListMeetings.name,
            ListAnnouncements.name,
        ]
        #expect(Set(names) == Set(Contract.actions.keys))
    }
}

@Suite struct Stream {
    @Test func parsesDataLines() {
        #expect(ChangeStream.parse("data: set_volume") == "set_volume")
        #expect(ChangeStream.parse("data:player_ended") == "player_ended")
        #expect(ChangeStream.parse(": ping") == nil)
        #expect(ChangeStream.parse("retry: 3000") == nil)
        #expect(ChangeStream.parse("data: ") == nil)
    }
}
