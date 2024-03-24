package actor

import "core:c"
import "core:thread"
import "core:sys/unix"

foreign import pthread "system:pthread"

// Assume a system with up to 64 cores.
cpu_set_t :: struct {
    // Using a 64-bit integer to represent CPU cores (up to 64 cores).
    // Each bit in the integer represents whether a core is included (1) or not (0).
    mask: u64,
}

foreign pthread {
    pthread_setaffinity_np :: proc(thread: unix.pthread_t, cpusetsize: c.size_t, cpuset: ^cpu_set_t) -> c.int ---
}

// Initializes the CPU set to be empty.
CPU_ZERO :: proc (set: ^cpu_set_t) {
    set.mask = 0
}

// Adds a CPU to the set.
CPU_SET :: proc (cpu: uint, set: ^cpu_set_t) {
    if cpu >= 0 && cpu < 64 {
        set.mask |= (1 << cpu)
    }
}

set_affinity :: proc(thread: ^thread.Thread, index: int) {
    cpu_set : cpu_set_t
    CPU_ZERO(&cpu_set)
    CPU_SET(auto_cast index, &cpu_set)

    pthread_setaffinity_np(thread.unix_thread, size_of(i32), &cpu_set)
}