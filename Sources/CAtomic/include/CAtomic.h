#ifndef CATOMIC_H
#define CATOMIC_H

#include <stdint.h>

/// One mixer slot. Layout is fixed and shared between the control plane
/// (GraphOwner) and the real-time render path (RenderCore).
///
/// - target_milli: 0...1000 gain in thousandths. Written by the control plane
///   via atomic store, read by RT once per render call.
/// - current_milli: ramp state, touched by the RT path only.
/// - peak: per-call peak accumulator, RT only.
/// - peak_shared: last published peak (float bits), RT publishes, UI polls.
typedef struct {
    _Atomic uint16_t target_milli;
    uint32_t current_milli;
    float peak;
    _Atomic uint32_t peak_shared;
} cat_slot_t;

/// Atomic counter (e.g. number of active slots), written control plane,
/// read by RT.
typedef struct {
    _Atomic uint32_t value;
} cat_flag_t;

uint16_t cat_slot_get_target(const cat_slot_t *slot);
void cat_slot_set_target(cat_slot_t *slot, uint16_t target);
float cat_slot_read_peak(const cat_slot_t *slot);
void cat_slot_publish_peak(cat_slot_t *slot, float peak);

uint32_t cat_flag_get(const cat_flag_t *flag);
void cat_flag_set(cat_flag_t *flag, uint32_t value);

#endif /* CATOMIC_H */
