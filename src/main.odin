package main

import "actor"
import "core:fmt"

stop_behaviour :: proc(
	self: ^actor.Actor,
	sys: ^actor.System,
	from: actor.ActorRef,
	msg: any,
) -> (
	next_behaviour: Maybe(actor.Behavior),
) {
	fmt.println("stopping")
	actor.stop(sys)
	return
}

counting_behaviour :: proc(
	self: ^actor.Actor,
	sys: ^actor.System,
	from: actor.ActorRef,
	msg: any,
) -> (
	next_behaviour: Maybe(actor.Behavior),
) {
	switch d in msg {
	case u128:
		if d >= 10_000_000 {
			return stop_behaviour
		}
		actor.send(sys, self.ref, from, d + 1)
	case string:
		fmt.println(d)
	}
	return
}

main :: proc() {
	sys := actor.new_system()
	count := actor.spawn(sys, counting_behaviour)

	// actor.send(sys, count, count, "test")
	actor.send(sys, count, count, u128(0))

	actor.work(sys)
}
