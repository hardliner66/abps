package actor

set_affinity :: proc(thread: ^thread.Thread, index: int) {
    count := logical_core_count();
    assert(index < count);

    index := index + 1;

    mask := uint(1) << uint(index);
    SetThreadAffinityMask(auto_cast thread.win32_thread, mask);
}