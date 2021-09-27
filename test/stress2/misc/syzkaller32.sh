#!/bin/sh

# Fatal trap 18: integer divide fault while in kernel mode
# cpuid = 0; apic id = 00
# instruction pointer     = 0x20:0xffffffff80c2f828
# stack pointer           = 0x0:0xfffffe0131a5d9e0
# frame pointer           = 0x0:0xfffffe0131a5da30
# code segment            = base 0x0, limit 0xfffff, type 0x1b
#                         = DPL 0, pres 1, long 1, def32 0, gran 1
# processor eflags        = interrupt enabled, resume, IOPL = 0
# current process         = 12 (swi4: clock (0))
# trap number             = 18
# panic: integer divide fault
# cpuid = 0
# time = 1616401924
# KDB: stack backtrace:
# db_trace_self_wrapper() at db_trace_self_wrapper+0x2b/frame 0xfffffe0131a5d6f0
# vpanic() at vpanic+0x181/frame 0xfffffe0131a5d740
# panic() at panic+0x43/frame 0xfffffe0131a5d7a0
# trap_fatal() at trap_fatal+0x387/frame 0xfffffe0131a5d800
# trap() at trap+0xa4/frame 0xfffffe0131a5d910
# calltrap() at calltrap+0x8/frame 0xfffffe0131a5d910
# --- trap 0x12, rip = 0xffffffff80c2f828, rsp = 0xfffffe0131a5d9e0, rbp = 0xfffffe0131a5da30 ---
# realtimer_expire() at realtimer_expire+0x1a8/frame 0xfffffe0131a5da30
# softclock_call_cc() at softclock_call_cc+0x15d/frame 0xfffffe0131a5db00
# softclock() at softclock+0x66/frame 0xfffffe0131a5db20
# ithread_loop() at ithread_loop+0x279/frame 0xfffffe0131a5dbb0
# fork_exit() at fork_exit+0x80/frame 0xfffffe0131a5dbf0
# fork_trampoline() at fork_trampoline+0xe/frame 0xfffffe0131a5dbf0
# --- trap 0, rip = 0, rsp = 0, rbp = 0 ---
# KDB: enter: panic
# [ thread pid 12 tid 100160 ]
# Stopped at      kdb_enter+0x37: movq    $0,0x1286f8e(%rip)
# db> x/s version
# version: FreeBSD 14.0-CURRENT #0 main-n245565-25bfa448602: Mon Mar 22 09:13:03 CET 2021
# pho@t2.osted.lan:/usr/src/sys/amd64/compile/PHO\012
# db>

[ `uname -p` != "amd64" ] && exit 0

. ../default.cfg
cat > /tmp/syzkaller32.c <<EOF
// https://syzkaller.appspot.com/bug?id=02c1b7d91203fd30b386eb023d4a99d1494de733
// autogenerated by syzkaller (https://github.com/google/syzkaller)
// Reported-by: syzbot+157b74ff493140d86eac@syzkaller.appspotmail.com

#define _GNU_SOURCE

#include <sys/types.h>

#include <errno.h>
#include <pthread.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/endian.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static unsigned long long procid;

static void kill_and_wait(int pid, int* status)
{
  kill(pid, SIGKILL);
  while (waitpid(-1, status, 0) != pid) {
  }
}

static void sleep_ms(uint64_t ms)
{
  usleep(ms * 1000);
}

static uint64_t current_time_ms(void)
{
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts))
    exit(1);
  return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static void thread_start(void* (*fn)(void*), void* arg)
{
  pthread_t th;
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 128 << 10);
  int i = 0;
  for (; i < 100; i++) {
    if (pthread_create(&th, &attr, fn, arg) == 0) {
      pthread_attr_destroy(&attr);
      return;
    }
    if (errno == EAGAIN) {
      usleep(50);
      continue;
    }
    break;
  }
  exit(1);
}

typedef struct {
  pthread_mutex_t mu;
  pthread_cond_t cv;
  int state;
} event_t;

static void event_init(event_t* ev)
{
  if (pthread_mutex_init(&ev->mu, 0))
    exit(1);
  if (pthread_cond_init(&ev->cv, 0))
    exit(1);
  ev->state = 0;
}

static void event_reset(event_t* ev)
{
  ev->state = 0;
}

static void event_set(event_t* ev)
{
  pthread_mutex_lock(&ev->mu);
  if (ev->state)
    exit(1);
  ev->state = 1;
  pthread_mutex_unlock(&ev->mu);
  pthread_cond_broadcast(&ev->cv);
}

static void event_wait(event_t* ev)
{
  pthread_mutex_lock(&ev->mu);
  while (!ev->state)
    pthread_cond_wait(&ev->cv, &ev->mu);
  pthread_mutex_unlock(&ev->mu);
}

static int event_isset(event_t* ev)
{
  pthread_mutex_lock(&ev->mu);
  int res = ev->state;
  pthread_mutex_unlock(&ev->mu);
  return res;
}

static int event_timedwait(event_t* ev, uint64_t timeout)
{
  uint64_t start = current_time_ms();
  uint64_t now = start;
  pthread_mutex_lock(&ev->mu);
  for (;;) {
    if (ev->state)
      break;
    uint64_t remain = timeout - (now - start);
    struct timespec ts;
    ts.tv_sec = remain / 1000;
    ts.tv_nsec = (remain % 1000) * 1000 * 1000;
    pthread_cond_timedwait(&ev->cv, &ev->mu, &ts);
    now = current_time_ms();
    if (now - start > timeout)
      break;
  }
  int res = ev->state;
  pthread_mutex_unlock(&ev->mu);
  return res;
}

struct thread_t {
  int created, call;
  event_t ready, done;
};

static struct thread_t threads[16];
static void execute_call(int call);
static int running;

static void* thr(void* arg)
{
  struct thread_t* th = (struct thread_t*)arg;
  for (;;) {
    event_wait(&th->ready);
    event_reset(&th->ready);
    execute_call(th->call);
    __atomic_fetch_sub(&running, 1, __ATOMIC_RELAXED);
    event_set(&th->done);
  }
  return 0;
}

static void execute_one(void)
{
  int i, call, thread;
  for (call = 0; call < 2; call++) {
    for (thread = 0; thread < (int)(sizeof(threads) / sizeof(threads[0]));
         thread++) {
      struct thread_t* th = &threads[thread];
      if (!th->created) {
        th->created = 1;
        event_init(&th->ready);
        event_init(&th->done);
        event_set(&th->done);
        thread_start(thr, th);
      }
      if (!event_isset(&th->done))
        continue;
      event_reset(&th->done);
      th->call = call;
      __atomic_fetch_add(&running, 1, __ATOMIC_RELAXED);
      event_set(&th->ready);
      event_timedwait(&th->done, 50);
      break;
    }
  }
  for (i = 0; i < 100 && __atomic_load_n(&running, __ATOMIC_RELAXED); i++)
    sleep_ms(1);
}

static void execute_one(void);

#define WAIT_FLAGS 0

static void loop(void)
{
  int iter = 0;
  for (;; iter++) {
    int pid = fork();
    if (pid < 0)
      exit(1);
    if (pid == 0) {
      execute_one();
      exit(0);
    }
    int status = 0;
    uint64_t start = current_time_ms();
    for (;;) {
      if (waitpid(-1, &status, WNOHANG | WAIT_FLAGS) == pid)
        break;
      sleep_ms(1);
      if (current_time_ms() - start < 5000) {
        continue;
      }
      kill_and_wait(pid, &status);
      break;
    }
  }
}

uint64_t r[1] = {0x0};

void execute_call(int call)
{
  intptr_t res = 0;
  switch (call) {
  case 0:
    res = syscall(SYS_ktimer_create, 4ul, 0ul, 0x20000500ul);
    if (res != -1)
      r[0] = *(uint32_t*)0x20000500;
    break;
  case 1:
    *(uint64_t*)0x20000100 = 0x200000000000000;
    *(uint64_t*)0x20000108 = 0;
    *(uint64_t*)0x20000110 = 0;
    *(uint64_t*)0x20000118 = 0x10000;
    syscall(SYS_ktimer_settime, r[0], 0ul, 0x20000100ul, 0ul);
    break;
  }
}
int main(void)
{
  syscall(SYS_mmap, 0x20000000ul, 0x1000000ul, 7ul, 0x1012ul, -1, 0ul);
  for (procid = 0; procid < 4; procid++) {
    if (fork() == 0) {
      loop();
    }
  }
  sleep(1000000);
  return 0;
}
EOF
mycc -o /tmp/syzkaller32 -Wall -Wextra -O0 /tmp/syzkaller32.c -lpthread  ||
    exit 1

(cd ../testcases/swap; ./swap -t 1m -i 20 -h > /dev/null 2>&1) &
(cd /tmp; timeout 3m ./syzkaller32)
while pkill swap; do :; done
wait

rm -rf /tmp/syzkaller32 syzkaller32.c /tmp/syzkaller.*
exit 0