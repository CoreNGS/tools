#!/bin/sh

# Fatal trap 12: page fault while in kernel mode
# cpuid = 21; apic id = 29
# fault virtual address   = 0x5eb9977d
# fault code              = supervisor read data, page not present
# instruction pointer     = 0x20:0xffffffff80d8f181
# stack pointer           = 0x28:0xfffffe0126709300
# frame pointer           = 0x28:0xfffffe0126709750
# code segment            = base 0x0, limit 0xfffff, type 0x1b
#                         = DPL 0, pres 1, long 1, def32 0, gran 1
# processor eflags        = interrupt enabled, resume, IOPL = 0
# current process         = 12 (swi1: netisr 0)
# trap number             = 12
# panic: page fault
# cpuid = 21
# time = 1589220309
# KDB: stack backtrace:
# db_trace_self_wrapper() at db_trace_self_wrapper+0x2b/frame 0xfffffe0126708fb0
# vpanic() at vpanic+0x182/frame 0xfffffe0126709000
# panic() at panic+0x43/frame 0xfffffe0126709060
# trap_fatal() at trap_fatal+0x387/frame 0xfffffe01267090c0
# trap_pfault() at trap_pfault+0x99/frame 0xfffffe0126709120
# trap() at trap+0x2a5/frame 0xfffffe0126709230
# calltrap() at calltrap+0x8/frame 0xfffffe0126709230
# --- trap 0xc, rip = 0xffffffff80d8f181, rsp = 0xfffffe0126709300, rbp = 0xfffffe0126709750 ---
# sctp_process_control() at sctp_process_control+0x1351/frame 0xfffffe0126709750
# sctp_common_input_processing() at sctp_common_input_processing+0x4f1/frame 0xfffffe01267098c0
# sctp6_input_with_port() at sctp6_input_with_port+0x22c/frame 0xfffffe01267099b0
# sctp6_input() at sctp6_input+0xb/frame 0xfffffe01267099c0
# ip6_input() at ip6_input+0xe89/frame 0xfffffe0126709aa0
# swi_net() at swi_net+0x1a1/frame 0xfffffe0126709b20
# ithread_loop() at ithread_loop+0x279/frame 0xfffffe0126709bb0
# fork_exit() at fork_exit+0x80/frame 0xfffffe0126709bf0
# fork_trampoline() at fork_trampoline+0xe/frame 0xfffffe0126709bf0
# --- trap 0, rip = 0, rsp = 0, rbp = 0 ---
# KDB: enter: panic
# [ thread pid 12 tid 100083 ]
# Stopped at      kdb_enter+0x37: movq    $0,0x10ca9a6(%rip)
# db>

# Reproduced on r360902
# Fixed by r360942

[ `uname -p` = "i386" ] && exit 0

. ../default.cfg
kldstat -v | grep -q sctp || kldload sctp.ko
cat > /tmp/syzkaller12.c <<EOF
// https://syzkaller.appspot.com/bug?id=978bd3a9b4c66b88dd523a3b8b32a1b0aa47ed83
// autogenerated by syzkaller (https://github.com/google/syzkaller)

#define _GNU_SOURCE

#include <sys/types.h>

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

static void execute_one(void);

#define WAIT_FLAGS 0

static void loop(void)
{
  int iter;
  for (iter = 0;; iter++) {
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
      if (current_time_ms() - start < 5 * 1000)
        continue;
      kill_and_wait(pid, &status);
      break;
    }
  }
}

uint64_t r[1] = {0xffffffffffffffff};

void execute_one(void)
{
  intptr_t res = 0;
  res = syscall(SYS_socket, 0x1cul, 1ul, 0x84);
  if (res != -1)
    r[0] = res;
  *(uint8_t*)0x20000000 = 0x1c;
  *(uint8_t*)0x20000001 = 0x1c;
  *(uint16_t*)0x20000002 = htobe16(0x4e22);
  *(uint32_t*)0x20000004 = 0;
  *(uint8_t*)0x20000008 = 0;
  *(uint8_t*)0x20000009 = 0;
  *(uint8_t*)0x2000000a = 0;
  *(uint8_t*)0x2000000b = 0;
  *(uint8_t*)0x2000000c = 0;
  *(uint8_t*)0x2000000d = 0;
  *(uint8_t*)0x2000000e = 0;
  *(uint8_t*)0x2000000f = 0;
  *(uint8_t*)0x20000010 = 0;
  *(uint8_t*)0x20000011 = 0;
  *(uint8_t*)0x20000012 = 0;
  *(uint8_t*)0x20000013 = 0;
  *(uint8_t*)0x20000014 = 0;
  *(uint8_t*)0x20000015 = 0;
  *(uint8_t*)0x20000016 = 0;
  *(uint8_t*)0x20000017 = 0;
  *(uint32_t*)0x20000018 = 0;
  syscall(SYS_bind, r[0], 0x20000000ul, 0x1cul);
  *(uint8_t*)0x20000180 = 0x5f;
  *(uint8_t*)0x20000181 = 0x1c;
  *(uint16_t*)0x20000182 = htobe16(0x4e22);
  *(uint32_t*)0x20000184 = 0;
  *(uint64_t*)0x20000188 = htobe64(0);
  *(uint64_t*)0x20000190 = htobe64(1);
  *(uint32_t*)0x20000198 = 0;
  syscall(SYS_connect, r[0], 0x20000180ul, 0x1cul);
}
int main(void)
{
  syscall(SYS_mmap, 0x20000000ul, 0x1000000ul, 7ul, 0x1012ul, -1, 0ul);
  loop();
  return 0;
}
// https://syzkaller.a
EOF
mycc -o /tmp/syzkaller12 -Wall -Wextra -O2 /tmp/syzkaller12.c -lpthread ||
    exit 1

(cd /tmp; ./syzkaller12) &
sleep 60
pkill -9 syzkaller12
wait

rm -f /tmp/syzkaller12 /tmp/syzkaller12.c /tmp/syzkaller12.core
exit 0