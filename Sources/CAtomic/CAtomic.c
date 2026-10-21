#include "CAtomic.h"
#include <stdatomic.h>
#include <string.h>

uint16_t cat_slot_get_target(const cat_slot_t *slot) {
    return atomic_load_explicit(&slot->target_milli, memory_order_relaxed);
}

void cat_slot_set_target(cat_slot_t *slot, uint16_t target) {
    atomic_store_explicit(&slot->target_milli, target, memory_order_relaxed);
}

float cat_slot_read_peak(const cat_slot_t *slot) {
    uint32_t bits = atomic_load_explicit(&slot->peak_shared, memory_order_relaxed);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

void cat_slot_publish_peak(cat_slot_t *slot, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    atomic_store_explicit(&slot->peak_shared, bits, memory_order_relaxed);
}

float cat_slot_read_input_peak(const cat_slot_t *slot) {
    uint32_t bits = atomic_load_explicit(&slot->input_peak_shared, memory_order_relaxed);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

void cat_slot_publish_input_peak(cat_slot_t *slot, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    atomic_store_explicit(&slot->input_peak_shared, bits, memory_order_relaxed);
}

uint32_t cat_flag_get(const cat_flag_t *flag) {
    return atomic_load_explicit(&flag->value, memory_order_relaxed);
}

void cat_flag_set(cat_flag_t *flag, uint32_t value) {
    atomic_store_explicit(&flag->value, value, memory_order_relaxed);
}
