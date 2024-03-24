package main

import "actor"
import "core:fmt"
import "core:os"

MaxMessages :: 10_000_000

Command :: enum {
	Inc,
}

stop_behaviour :: proc(
	self: ^actor.Actor,
	sys: ^actor.System,
	state: ^actor.State,
	from: actor.ActorRef,
	msg: any,
) {
	fmt.println("stopping")
	actor.stop(sys)
}

counting_behaviour :: proc(
	self: ^actor.Actor,
	sys: ^actor.System,
	state: ^actor.State,
	from: actor.ActorRef,
	msg: any,
) {
	switch d in msg {
	case actor.ActorRef:
		self.state = d
	case u128:
		if d >= MaxMessages {
			actor.become(self, stop_behaviour)
		}
		actor.send(sys, self.ref, state^.(actor.ActorRef), d + 1)
	}
}

main :: proc() {
	fmt.println(os.processor_core_count())
	sys := actor.new_system()
	a := actor.spawn(sys, nil, nil, counting_behaviour)
	b := actor.spawn(sys, nil, a, counting_behaviour)
	c := actor.spawn(sys, nil, b, counting_behaviour)
	d := actor.spawn(sys, nil, c, counting_behaviour)
	actor.send(sys, a, a, d)
	actor.send(sys, a, a, u128(0))

	actor.work(sys)

	fmt.println("Messages: ", sys.message_counter)

	actor.destroy_system(sys)
}
