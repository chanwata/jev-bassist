@preconcurrency import CoreMIDI

struct RawMIDIPacket: Equatable, Sendable {
    let hostTime: UInt64
    let bytes: [UInt8]
}

enum MIDIPacketListReader {
    static func copyPackets(
        from packetList: UnsafePointer<MIDIPacketList>
    ) -> [RawMIDIPacket] {
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet),
              let timeStampOffset = MemoryLayout<MIDIPacket>.offset(of: \.timeStamp),
              let lengthOffset = MemoryLayout<MIDIPacket>.offset(of: \.length),
              let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data) else {
            return []
        }

        let packetStorage = UnsafeRawPointer(packetList).advanced(by: packetOffset)
        var packetPointer = UnsafeMutablePointer(
            mutating: packetStorage.assumingMemoryBound(to: MIDIPacket.self)
        )
        var packets: [RawMIDIPacket] = []
        packets.reserveCapacity(Int(packetList.pointee.numPackets))

        for _ in 0..<packetList.pointee.numPackets {
            let packetStorage = UnsafeRawPointer(packetPointer)
            let hostTime = packetStorage.loadUnaligned(
                fromByteOffset: timeStampOffset,
                as: MIDITimeStamp.self
            )
            let length = packetStorage.loadUnaligned(
                fromByteOffset: lengthOffset,
                as: UInt16.self
            )
            let data = packetStorage
                .advanced(by: dataOffset)
                .assumingMemoryBound(to: UInt8.self)
            let bytes = Array(UnsafeBufferPointer(start: data, count: Int(length)))
            packets.append(RawMIDIPacket(hostTime: hostTime, bytes: bytes))
            packetPointer = MIDIPacketNext(packetPointer)
        }

        return packets
    }
}
