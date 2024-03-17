package main

import "actor"
import "core:c/libc"
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
		actor.send(sys, self.ref, from, d + 1)
		if d >= 1 {
			return stop_behaviour
		}
	case string:
		fmt.println(d)
	}
	return
}

main :: proc() {
	sys := actor.new_system()
	count := actor.spawn(sys, counting_behaviour)

	actor.send(sys, count, count, u128(0))

	actor.work(sys)

	actor.destroy_system(sys)
}
