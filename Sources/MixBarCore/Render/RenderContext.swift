import CAtomic

/// Shared state between the control plane and the real-time render path.
/// Owned and allocated by GraphOwner; the pointer is handed to the render
/// loop as client data (ADR-004).
///
/// RT rules: after `startRenderLoop`, the RT path only reads/writes
/// `slots[i].current_milli`, `slots[i].peak`, and calls the CAtomic helpers.
/// The control plane only writes `slots[i].target_milli` (atomic) and
/// `activeSlots` (atomic) outside of that.
public struct RenderContext {
    public let slots: UnsafeMutablePointer<cat_slot_t>
    public let capacity: Int                    // allocation bound (max slots)
    public let activeSlots: UnsafeMutablePointer<cat_flag_t>
    public let rampFrames: UInt32               // ~10 ms of gain ramp
    public var frameRate: Float64               // informational
    public var outputChannels: Int              // informational

    public init(slots: UnsafeMutablePointer<cat_slot_t>,
                capacity: Int,
                activeSlots: UnsafeMutablePointer<cat_flag_t>,
                rampFrames: UInt32 = 480,
                frameRate: Float64 = 48000,
                outputChannels: Int = 2) {
        self.slots = slots
        self.capacity = capacity
        self.activeSlots = activeSlots
        self.rampFrames = rampFrames
        self.frameRate = frameRate
        self.outputChannels = outputChannels
    }
}
