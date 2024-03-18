# ABPS Architecture

## Actors
Actors are stored in a tree-like structure. Each actor can have many children, forming the supervision tree as well.
If an actor stops (on purpose or on accident/crash), it should send it's parent actor a special message
on the priority queue telling it that it died and why.

## MailBoxes
Mailboxes contain two lock free queues of messages (next pointer) and a pointer to associated actor. One queue
is for normal messages, the other one is for priority messages. When checking for work, the priority queue is checked
first and when it's empty, the normal queue is used instead.

## Scheduler
The scheduler gets assigned to a thread. Each scheduler has a vector of mailboxes, which it iterates over in order
to search for work. If it does not find any, it should try steal work from other schedulers. It will try to migrate
the mailbox to itself, leaving the original with a nullopt.

## Actor Reference
An actor reference contains a way to access the mailbox.

## Sending Messages
To send a message, we access the mailbox of an actor through it's actor reference and push the message onto the queue.
If a mailbox is not available anymore, the message goes to a special mailbox for dead messages.
