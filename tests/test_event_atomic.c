#include "event_atomic.h"
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <sys/time.h>
#include <unistd.h>
static event_slot_t request, ack, interrupt_event;
static volatile sig_atomic_t interrupted;
static void alarm_handler(int sig)
{
    (void)sig;
    event_exchange(&interrupt_event, true);
    interrupted = 1;
}
static void *producer(void *unused)
{
    (void)unused;
    for (int i = 0; i < 10000; i++) {
        event_exchange(&request, true);
        while (!event_exchange(&ack, false)) { }
    }
    return NULL;
}
int main(void)
{
    event_slot_t value = 0;
    assert(!event_exchange(&value, true));
    assert(event_exchange(&value, true));
    assert(event_exchange(&value, false));
    assert(!event_exchange(&value, false));
    struct sigaction action = { .sa_handler = alarm_handler };
    sigemptyset(&action.sa_mask);
    assert(sigaction(SIGALRM, &action, NULL) == 0);
    struct itimerval timer = { .it_interval = {0, 100}, .it_value = {0, 100} };
    assert(setitimer(ITIMER_REAL, &timer, NULL) == 0);
    pthread_t thread;
    assert(pthread_create(&thread, NULL, producer, NULL) == 0);
    for (int i = 0; i < 10000; i++) {
        while (!event_exchange(&request, false)) { }
        event_exchange(&ack, true);
    }
    assert(pthread_join(thread, NULL) == 0);
    timer.it_interval.tv_usec = timer.it_value.tv_usec = 0;
    assert(setitimer(ITIMER_REAL, &timer, NULL) == 0);
    assert(interrupted);
    assert(event_exchange(&interrupt_event, false));
    puts("PASS: event exchanges, 10000 threaded handshakes, concurrent signal handler");
}
