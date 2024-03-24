package actor

import "core:sync"

State :: Any

Behavior :: proc(self: ^Actor, sys: ^System, state: ^State, from: ActorRef, msg: any)

Actor :: struct {
	ref:           ActorRef,
	behavior:      Behavior,
	last_behavior: Maybe(Behavior),
	state:         State,
	children:      [dynamic]^Actor,
	parent:        ^Actor,
	lock:          sync.Mutex,
}

new_actor :: proc(
	ref: ActorRef,
	behavior: Behavior,
	state: State,
	parent: ^Actor = nil,
) -> ^Actor {
	actor := new(Actor)
	actor.ref = ref
	actor.behavior = behavior
	actor.last_behavior = nil
	actor.state = state
	actor.children = make([dynamic]^Actor, 0)
	actor.parent = parent
	actor.lock = sync.Mutex{}
	return actor
}

destroy_actor :: proc(actor: ^Actor) {
	for child in actor.children {
		destroy_actor(child)
	}
	destroy_state(&actor.state)
}

destroy_state :: proc(state: ^State) {
}

become :: proc(self: ^Actor, behavior: Behavior) {
	if sync.guard(&self.lock) {
		self.last_behavior = self.behavior
		self.behavior = behavior
	}
}

unbecome :: proc(self: ^Actor) {
	if sync.guard(&self.lock) {
		if self^.last_behavior != nil {
			self^.behavior = self^.last_behavior.?
		}
	}
}

ActorRef :: struct {
	addr: string,
}
