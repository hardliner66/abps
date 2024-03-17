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

Any :: union {
	// booleans
	bool,
	b8,
	b16,
	b32,
	b64,

	// integers
	int,
	i8,
	i16,
	i32,
	i64,
	i128,
	uint,
	u8,
	u16,
	u32,
	u64,
	u128,
	uintptr,

	// endian specific integers
	// little endian
	i16le,
	i32le,
	i64le,
	i128le,
	u16le,
	u32le,
	u64le,
	u128le,
	// big endian
	i16be,
	i32be,
	i64be,
	i128be,
	u16be,
	u32be,
	u64be,
	u128be,
	// floating point numbers
	f16,
	f32,
	f64,

	// endian specific floating point numbers
	// little endian
	f16le,
	f32le,
	f64le,
	// big endian
	f16be,
	f32be,
	f64be,
	// complex numbers
	complex32,
	complex64,
	complex128,
	// quaternion numbers
	quaternion64,
	quaternion128,
	quaternion256,
	// signed 32 bit integer
	// represents a Unicode code point
	// is a distinct type to `i32`
	rune,
	// strings
	string,
	cstring,

	// raw pointer type
	rawptr,

	// runtime type information specific type
	typeid,

	// custom types
	ActorRef,

	// containers
	[dynamic]Any,
	map[string]Any,
}

State :: Any

Behavior :: proc(self: ^Actor, sys: ^System, state: ^State, from: ActorRef, msg: any)

Actor :: struct {
	ref:           ActorRef,
	behavior:      Behavior,
	last_behavior: Maybe(Behavior),
	state:         State,
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
	delete(sys.actors)
	free(sys)
}

spawn :: proc(sys: ^System, state: State, behavior: Behavior) -> ActorRef {
	id := uuid.generate()
	id_string, err := uuid.clone_to_string(id)
	assert(err == nil)
	ref := ActorRef{id_string}
	sys.actors[id_string] = Actor{ref, behavior, nil, state}
	return ref
}

become :: proc(self: ^Actor, behavior: Behavior) {
	self^.last_behavior = self^.behavior
	self^.behavior = behavior
}

unbecome :: proc(self: ^Actor) {
	if self^.last_behavior != nil {
		self^.behavior = self^.last_behavior.?
	}
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
			break
		}
		msg := pop_front(&sys.queue)
		actor := &sys.actors[msg.to.addr]
		actor.behavior(actor, sys, &actor.state, msg.from, msg.msg.data)
		free_anything(msg.msg)
	}
}
