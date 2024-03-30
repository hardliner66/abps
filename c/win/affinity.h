#include <windows.h>
#include <stdio.h>

int set_affinity(size_t cpu) {
    DWORD_PTR mask = (1 << cpu);
    int ret = SetThreadAffinityMask(GetCurrentThread(), mask);

    return ret;
}
