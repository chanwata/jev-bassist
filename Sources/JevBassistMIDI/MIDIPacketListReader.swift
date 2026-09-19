@preconcurrency import CoreMIDI

struct RawMIDIPacket: Equatable, Sendable {
    let hostTime: UInt64
    let bytes: [UInt8]
}

enum MIDIPacketListReader {
    static func copyPackets(
        from packetList: UnsafePointer<MIDIPacketList>
    ) -> [RawMIDIPacket] {
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) else {
            return []
        }

        let packetStorage = UnsafeRawPointer(packetList).advanced(by: packetOffset)
        var packetPointer = UnsafeMutablePointer(
            mutating: packetStorage.assumingMemoryBound(to: MIDIPacket.self)
        )
        var packets: [RawMIDIPacket] = []
        packets.reserveCapacity(Int(packetList.pointee.numPackets))

        for _ in 0..<packetList.pointee.numPackets {
            let packet = packetPointer.pointee
            let bytes = withUnsafeBytes(of: packet.data) {
                Array($0.prefix(Int(packet.length)))
            }
            packets.append(RawMIDIPacket(hostTime: packet.timeStamp, bytes: bytes))
            packetPointer = MIDIPacketNext(packetPointer)
        }

        return packets
    }
}
