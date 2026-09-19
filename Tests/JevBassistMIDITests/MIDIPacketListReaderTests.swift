import CoreMIDI
import XCTest
@testable import JevBassistMIDI

final class MIDIPacketListReaderTests: XCTestCase {
    func testCopiesMultiplePacketsFromOriginalListStorage() throws {
        let capacity = 1_024
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: capacity,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { storage.deallocate() }

        let packetList = storage.bindMemory(to: MIDIPacketList.self, capacity: 1)
        var currentPacket = MIDIPacketListInit(packetList)
        currentPacket = try add(
            [0x90, 60, 100],
            at: 101,
            to: packetList,
            capacity: capacity,
            after: currentPacket
        )
        _ = try add(
            [0x80, 60, 0],
            at: 202,
            to: packetList,
            capacity: capacity,
            after: currentPacket
        )

        let packets = MIDIPacketListReader.copyPackets(from: UnsafePointer(packetList))

        XCTAssertEqual(packets, [
            RawMIDIPacket(hostTime: 101, bytes: [0x90, 60, 100]),
            RawMIDIPacket(hostTime: 202, bytes: [0x80, 60, 0])
        ])
    }

    private func add(
        _ bytes: [UInt8],
        at time: MIDITimeStamp,
        to packetList: UnsafeMutablePointer<MIDIPacketList>,
        capacity: Int,
        after currentPacket: UnsafeMutablePointer<MIDIPacket>
    ) throws -> UnsafeMutablePointer<MIDIPacket> {
        try bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw PacketListTestError.couldNotAddPacket
            }
            return MIDIPacketListAdd(
                packetList,
                capacity,
                currentPacket,
                time,
                buffer.count,
                baseAddress
            )
        }
    }
}

private enum PacketListTestError: Error {
    case couldNotAddPacket
}
