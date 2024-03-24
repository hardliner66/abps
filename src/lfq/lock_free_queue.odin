package lfq

import "core:sync" // Hypothetical import; actual atomic operations need FFI

Node :: struct($T: typeid) {
	value: T,
	next:  ^Node(T), // Hypothetical atomic pointer; actual implementation needs FFI
}

Queue :: struct($T: typeid) {
	head: ^Node(T),
	tail: ^Node(T),
}

enqueue :: proc(q: ^Queue($T), value: T) {
	// Allocate new node
	new_node := new(Node(T))
	new_node.value = value
	new_node.next = new(Node(T))
	for {
		tail := sync.atomic_load(&q^.tail)
		next := sync.atomic_load(&tail.next)
		if next == nil {
			// Attempt to link in the new node
			if _, ok := sync.atomic_compare_exchange_weak(&tail.next, next, new_node); ok {
				// Attempt to swing tail to the new node
				sync.atomic_compare_exchange_weak(&q^.tail, tail, new_node)
				return
			}
		} else {
			// Tail was not pointing to the last node, try to swing Tail to Next
			sync.atomic_compare_exchange_weak(&q^.tail, tail, next)
		}
	}
}

dequeue :: proc(q: ^Queue($T)) -> Maybe(T) {
	for {
		head := sync.atomic_load(&q^.head)
		tail := sync.atomic_load(&q^.tail)
		next := sync.atomic_load(&head^.next)
		if head == q.head {
			if head == tail {
				if next == nil {
					return nil // Queue is empty
				}
				// Tail is behind, try to advance it
				sync.atomic_compare_exchange_weak(&q^.tail, tail, next)
			} else {
				// Read value before CAS, otherwise another dequeue might free the next node
				val := next.value
				// Try to swing Head to the next node
				if _, ok := sync.atomic_compare_exchange_weak(&q^.head, head, next); ok {
					return val
				}
			}
		}
	}
	return nil // Unreachable, but necessary for the compiler
}

init_queue :: proc($T: typeid) -> Queue(T) {
	sentinel := new(Node(T)) // Create a dummy sentinel node
	head := new(Node(T))
	tail := new(Node(T))
	sync.atomic_store(&head, sentinel)
	sync.atomic_store(&tail, sentinel)
	return Queue(T){head, tail}
}
