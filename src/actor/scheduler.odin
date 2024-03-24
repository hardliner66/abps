package actor

import "../lfq"

import "core:sync"
import "core:thread"

Mailbox :: struct {
    actor: ^Actor,
    messages: lfq.Queue(Message),
}

new_mailbox :: proc(actor: ^Actor) -> Mailbox {
    mailbox := Mailbox{actor, lfq.init_queue(Message)}
    return mailbox
}

add_mailbox::proc(scheduler: ^Scheduler, id_string: string, actor: ^Actor) {
    if sync.guard(&scheduler.lock) {
        scheduler^.mailboxes[id_string] = new_mailbox(actor)
    }
}

Scheduler :: struct {
    running: bool,
	mailboxes: map[string]Mailbox,
    sys: ^System,
    lock: sync.Mutex,
    thread: ^thread.Thread,
}

new_scheduler :: proc(sys: ^System) -> ^Scheduler {
    scheduler := new(Scheduler)
    scheduler.running = true
    scheduler.mailboxes = make(map[string]Mailbox)
    scheduler.sys = sys
    scheduler.lock = sync.Mutex{}
    scheduler.thread = nil
    return scheduler
}

scheduler_work :: proc(scheduler: ^Scheduler) {
	for scheduler.running {
        {
            if sync.guard(&scheduler.lock) {
                for _, mailbox in &scheduler.mailboxes {
                    msg, ok := lfq.dequeue(&mailbox.messages).?
                    if ok {
                        actor := mailbox.actor
                        actor.behavior(actor, scheduler.sys, &actor.state, msg.from, msg.msg.data)
                        free_anything(msg.msg)
                    }
                }
            }
        }
	}
}
