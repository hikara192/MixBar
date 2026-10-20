import CoreAudio
import Darwin

/// Utility for building AudioBufferLists in memory: used by FakeAudioSystem
/// and by tests. NOT used on any real-time path.
public final class InterleavedBufferList {
    public let list: UnsafeMutablePointer<AudioBufferList>
    private let raw: UnsafeMutableRawPointer
    private let dataPtrs: [UnsafeMutableRawPointer]

    /// - Parameters:
    ///   - bufferCount: number of buffers in the list.
    ///   - frames: frames per buffer.
    ///   - channels: channels per buffer (2 = interleaved stereo, 1 = mono).
    public init(bufferCount: Int, frames: Int, channels: Int = 2) {
        let byteCount = frames * channels * MemoryLayout<Float>.size
        let totalSize = MemoryLayout<AudioBufferList>.size
            + max(0, bufferCount - 1) * MemoryLayout<AudioBuffer>.size
        raw = UnsafeMutableRawPointer.allocate(byteCount: totalSize,
                                               alignment: MemoryLayout<AudioBufferList>.alignment)
        list = raw.assumingMemoryBound(to: AudioBufferList.self)
        list.pointee.mNumberBuffers = UInt32(bufferCount)

        var ptrs: [UnsafeMutableRawPointer] = []
        ptrs.reserveCapacity(bufferCount)
        let abp = UnsafeMutableAudioBufferListPointer(list)
        for i in 0..<bufferCount {
            let data = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
            memset(data, 0, byteCount)
            abp[i] = AudioBuffer(mNumberChannels: UInt32(channels),
                                 mDataByteSize: UInt32(byteCount),
                                 mData: data)
            ptrs.append(data)
        }
        dataPtrs = ptrs
    }

    public func channelData(buffer: Int) -> UnsafeMutablePointer<Float> {
        dataPtrs[buffer].assumingMemoryBound(to: Float.self)
    }

    public func frameCount(buffer: Int = 0, channels: Int = 2) -> Int {
        Int(UnsafeMutableAudioBufferListPointer(list)[buffer].mDataByteSize)
            / (channels * MemoryLayout<Float>.size)
    }

    deinit {
        dataPtrs.forEach { $0.deallocate() }
        raw.deallocate()
    }
}
