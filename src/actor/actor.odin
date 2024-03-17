package actors

import "../uuid"

Anything :: struct {
	data: any,
	ptr:  rawptr,
}

new_anything :: proc(value: $T) -> Anything {
	p := new(T)
	p^ = value
	return Anything{p^, p}
}

free_anything :: proc(any: Anything) {
	free(any.ptr)
}

Behavior :: proc(
	self: ^Actor,
	sys: ^System,
	from: ActorRef,
	msg: any,
) -> (
	next_behaviour: Maybe(Behavior)
)

Actor :: struct {
	ref:      ActorRef,
	behavior: Behavior,
}

ActorRef :: struct {
	addr: string,
}

Message :: struct {
	to:   ActorRef,
	from: ActorRef,
	msg:  Anything,
}

System :: struct {
	actors:  map[string]Actor,
	queue:   [dynamic]Message,
	running: bool,
}

new_system :: proc() -> ^System {
	sys := new(System)
	sys.running = true
	sys.actors = make(map[string]Actor)
	sys.queue = make([dynamic]Message, 0)
	return sys
}

destroy_system :: proc(sys: ^System) {
	for len(sys.queue) > 0 {
		msg := pop(&sys.queue)
		free_anything(msg.msg)
	}
	delete(sys.queue)
	for k, v in sys.actors {
		_, _ = delete_key(&sys.actors, k)
	}
	delete(sys.actors)
	free(sys)
}

spawn :: proc(sys: ^System, behavior: Behavior) -> ActorRef {
	id := uuid.generate()
	id_string, err := uuid.clone_to_string(id)
	assert(err == nil)
	ref := ActorRef{id_string}
	sys.actors[id_string] = Actor{ref, behavior}
	return ref
}

send :: proc(sys: ^System, from: ActorRef, to: ActorRef, msg: $T) {
	m := new_anything(msg)
	append(&sys.queue, Message{to, from, m})
}

stop :: proc(sys: ^System) {
	sys.running = false
}

work :: proc(sys: ^System) {
	for sys.running {
		if len(sys.queue) == 0 {
			continue
		}
		msg := pop(&sys.queue)
		actor := &sys.actors[msg.to.addr]
		next := actor.behavior(actor, sys, msg.from, msg.msg.data)
		free_anything(msg.msg)
		if next != nil {
			actor^.behavior = next.?
		}
	}
}
