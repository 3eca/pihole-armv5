/* ARMv5 Linux compatibility for FTL's signal-safe event queue.
 * SPDX-License-Identifier: EUPL-1.2
 */
#ifndef FTL_EVENT_ATOMIC_H
#define FTL_EVENT_ATOMIC_H
#include <stdbool.h>
#if defined(__linux__) && defined(__arm__) && __ARM_ARCH < 6
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
/* Linux's fixed kuser ABI provides a lock-free 32-bit compare/exchange,
 * including memory barriers and kernel handling of interrupted sequences.
 * Do not replace this with libatomic: a lock interrupted by a signal can
 * deadlock when the handler accesses the same slot.
 * https://www.kernel.org/doc/Documentation/arm/kernel_user_helpers.txt
 */
typedef volatile int32_t event_slot_t;
typedef int (*event_cmpxchg_fn)(int32_t, int32_t, volatile int32_t *);
__attribute__((constructor)) static void check_event_kuser(void)
{
    if (*(volatile const uint32_t *)0xffff0ffc < 2) {
        fputs("FTL ARMv5 requires Linux kuser cmpxchg (helper version >= 2)\n", stderr);
        abort();
    }
}
static inline bool event_exchange(event_slot_t *slot, bool value)
{
    int32_t previous;
    const event_cmpxchg_fn cmpxchg = (event_cmpxchg_fn)0xffff0fc0;
    do {
        previous = *slot;
    } while (cmpxchg(previous, value ? 1 : 0, slot) != 0);
    return previous != 0;
}
#else
#include <stdatomic.h>
typedef _Atomic bool event_slot_t;
_Static_assert(ATOMIC_BOOL_LOCK_FREE == 2,
               "Event queue must be lock-free, it is used from a signal handler");
static inline bool event_exchange(event_slot_t *slot, bool value)
{
    return atomic_exchange(slot, value);
}
#endif
#endif
