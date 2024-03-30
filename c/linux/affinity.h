#define _GNU_SOURCE
#include <stdio.h>
#include <pthread.h>
#include <sched.h>


int set_affinity(size_t cpu) {
    cpu_set_t cpuset;

    // Initialize the CPU set to zero
    CPU_ZERO(&cpuset);
    // Add CPU 0 to the set
    CPU_SET(cpu, &cpuset);

    // Apply the CPU set to the current thread
    return pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
}
