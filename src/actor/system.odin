package actor

import "../uuid"
import "../lfq"

import "core:os"
import "core:thread"
import "core:sync"

System :: struct {
	root_actor: ^Actor,
    scheduling_counter: int,
    message_counter: int,
	schedulers: [dynamic]^Scheduler,
	running:    bool,
    lock: sync.Mutex,
}

new_system :: proc() -> ^System {
	sys := new(System)
	sys.running = true
	core_count := os.processor_core_count()
    core_count = 4
	for i in 0 ..< core_count {
        scheduler := new_scheduler(sys)
        t := thread.create_and_start_with_poly_data(scheduler, scheduler_work)
        scheduler.thread = t
        set_affinity(t, i)
		append(&sys.schedulers, scheduler)
	}
	sys.root_actor = new(Actor)
	ref := ActorRef{"root"}
	sys.root_actor.ref = ref
    sys.lock = sync.Mutex{}
	return sys
}

destroy_system :: proc(sys: ^System) {
    destroy_actor(sys.root_actor)
	free(sys)
}

spawn :: proc(sys: ^System, parent: ^Actor, state: State, behavior: Behavior) -> ActorRef {
	id := uuid.generate()
	id_string, err := uuid.clone_to_string(id)
	assert(err == nil)
    p := parent
    if parent == nil {
        p = sys.root_actor
    }
	ref := ActorRef{id_string}
    actor := new_actor(ref, behavior, state,  parent)
    if sync.guard(&sys.lock) {
        append(&p.children, actor)
        add_mailbox(sys.schedulers[sys.scheduling_counter % len(sys.schedulers)], id_string, actor)
        sys.scheduling_counter += 1;
    }
	return ref
}

send :: proc(sys: ^System, from: ActorRef, to: ActorRef, msg: $T) {
    {
        if sync.guard(&sys.lock) {
            sys.message_counter += 1
        }
    }

	m := new_anything(msg)
    for scheduler in sys.schedulers {
        if mailbox, ok := &scheduler.mailboxes[to.addr]; ok {
                current := &mailbox^.messages
                msg := Message{to, from, m}
                lfq.enqueue(current, msg)
            return
        }
    }
}

work :: proc(sys: ^System) {
    for scheduler in sys.schedulers {
        thread.join(scheduler.thread)
    }
}

stop :: proc(sys: ^System) {
    for scheduler in sys.schedulers {
        if sync.guard(&sys.lock) {
            scheduler.running = false
        }
    }
    if sync.guard(&sys.lock) {
	    sys.running = false
    }
}