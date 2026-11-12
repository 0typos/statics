/*
 * tunpipe: carry IPv4 packets between a TUN interface and a byte stream,
 * typically the stdin/stdout of an SSH session.
 *
 * SPDX-License-Identifier: MIT
 *
 * Built into dropbearmulti as the "tunpipe" program (see
 * patches/dropbear-tunpipe.patch); also builds standalone with
 * -Dtunpipe_main=main.
 *
 * Wire format: each side first sends MAGIC, then every packet as a 2-byte
 * big-endian length followed by the packet.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/if_tun.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int tunpipe_main(int argc, char **argv);

#define MAGIC "TUNPIPE1\n"
#define MAGIC_LEN (sizeof(MAGIC) - 1)
#define MAX_ROUTES 32
#define FRAME_MAX 65535
/* An empty frame is a keepalive; a silent peer is dead after PEER_TIMEOUT. */
#define KEEPALIVE_SECS 10
#define PEER_TIMEOUT_SECS 45

static char ifname[IFNAMSIZ] = "tp%d";
static char netns_path[256];
static int nat_active;
static pid_t child = -1;
static volatile sig_atomic_t stop_signal;

static void cleanup(void);

/* Every exit after setup goes through here, so teardown runs exactly once. */
static void finish(int rc)
{
    cleanup();
    exit(stop_signal ? 128 + stop_signal : rc);
}

static void die(const char *fmt, ...)
{
    int saved = errno;
    va_list ap;
    va_start(ap, fmt);
    fputs("tunpipe: ", stderr);
    vfprintf(stderr, fmt, ap);
    if (saved)
        fprintf(stderr, ": %s", strerror(saved));
    fputc('\n', stderr);
    va_end(ap);
    finish(1);
}

static void usage(void)
{
    fputs("usage: tunpipe -l LOCAL -p PEER [-r CIDR]... [-n NETNS] [-N] [-i IFNAME]\n"
          "               [[--] COMMAND [ARG]...]\n"
          "  -l LOCAL   this end's IPv4 address\n"
          "  -p PEER    the other end's IPv4 address\n"
          "  -r CIDR    route CIDR through the tunnel (repeatable)\n"
          "  -n NETNS   put the tunnel in a new namespace /run/netns/NETNS with a\n"
          "             default route through it; run programs with\n"
          "             nsenter --net=/run/netns/NETNS COMMAND\n"
          "  -N         masquerade traffic from PEER (enables IPv4 forwarding; needs nft)\n"
          "  -i IFNAME  interface name (default tp%d)\n"
          "With COMMAND, tunpipe runs it and talks over its stdin/stdout:\n"
          "  tunpipe -l 10.9.0.2 -p 10.9.0.1 -r 10.0.0.0/8 -- \\\n"
          "      dbclient host tunpipe -l 10.9.0.1 -p 10.9.0.2 -N\n"
          "Without COMMAND it uses its own stdin/stdout (the server end).\n",
          stderr);
}

static void write_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    while (len > 0) {
        if (stop_signal)
            finish(1);
        ssize_t n = write(fd, p, len);
        if (n < 0 && errno == EINTR) {
            if (stop_signal)
                finish(1);
            continue;
        }
        if (n == 0)
            errno = EPIPE;
        if (n <= 0)
            die("write to stream");
        p += n;
        len -= (size_t)n;
    }
}

static int read_full(int fd, void *buf, size_t len)
{
    char *p = buf;
    while (len > 0) {
        if (stop_signal)
            finish(1);
        ssize_t n = read(fd, p, len);
        if (n < 0 && errno == EINTR) {
            if (stop_signal)
                finish(1);
            continue;
        }
        if (n <= 0)
            return -1;
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

static void parse_addr(const char *text, struct in_addr *addr)
{
    if (inet_pton(AF_INET, text, addr) != 1) {
        errno = 0;
        die("not an IPv4 address: %s", text);
    }
}

static void parse_cidr(const char *text, struct in_addr *net, struct in_addr *mask)
{
    char buf[INET_ADDRSTRLEN + 4];
    char *slash, *end;
    long bits;

    if (strlen(text) >= sizeof(buf))
        goto bad;
    strcpy(buf, text);
    slash = strchr(buf, '/');
    if (!slash)
        goto bad;
    *slash = '\0';
    bits = strtol(slash + 1, &end, 10);
    if (*end || end == slash + 1 || bits < 0 || bits > 32 || inet_pton(AF_INET, buf, net) != 1)
        goto bad;
    mask->s_addr = bits ? htonl(0xffffffffu << (32 - bits)) : 0;
    net->s_addr &= mask->s_addr;
    return;
bad:
    errno = 0;
    die("not an IPv4 CIDR: %s", text);
}

static void set_sin(struct sockaddr *sa, struct in_addr addr)
{
    struct sockaddr_in sin = { .sin_family = AF_INET, .sin_addr = addr };
    memcpy(sa, &sin, sizeof(sin));
}

static void if_ioctl(int sock, unsigned long req, struct ifreq *ifr, const char *what)
{
    memcpy(ifr->ifr_name, ifname, IFNAMSIZ);
    if (ioctl(sock, req, ifr) < 0)
        die("%s on %s", what, ifname);
}

static void link_up(int sock, const char *name)
{
    struct ifreq ifr = { 0 };
    snprintf(ifr.ifr_name, IFNAMSIZ, "%s", name);
    if (ioctl(sock, SIOCGIFFLAGS, &ifr) < 0)
        die("get flags of %s", name);
    ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
    if (ioctl(sock, SIOCSIFFLAGS, &ifr) < 0)
        die("bring up %s", name);
}

static void add_route(int sock, struct in_addr net, struct in_addr mask)
{
    struct rtentry rt = { 0 };
    set_sin(&rt.rt_dst, net);
    set_sin(&rt.rt_genmask, mask);
    rt.rt_flags = RTF_UP;
    rt.rt_dev = ifname;
    if (ioctl(sock, SIOCADDRT, &rt) < 0 && errno != EEXIST) {
        char dst[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &net, dst, sizeof(dst));
        die("add route %s/%d", dst, __builtin_popcount(mask.s_addr));
    }
}

/* shortcut: IPv4 only, via ioctls; add IPv6 (netlink) when someone needs it. */
static int open_tun(struct in_addr local, struct in_addr peer,
                    const struct in_addr *nets, const struct in_addr *masks,
                    int nroutes, int default_route)
{
    struct ifreq ifr = { 0 };
    struct in_addr host_mask = { .s_addr = 0xffffffffu };
    struct in_addr any = { 0 };
    int fd, sock, i;

    fd = open("/dev/net/tun", O_RDWR | O_CLOEXEC);
    if (fd < 0)
        die("open /dev/net/tun");
    ifr.ifr_flags = IFF_TUN | IFF_NO_PI;
    memcpy(ifr.ifr_name, ifname, IFNAMSIZ);
    if (ioctl(fd, TUNSETIFF, &ifr) < 0)
        die("create tun %s", ifname);
    memcpy(ifname, ifr.ifr_name, IFNAMSIZ);

    sock = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (sock < 0)
        die("socket");
    memset(&ifr, 0, sizeof(ifr));
    set_sin(&ifr.ifr_addr, local);
    if_ioctl(sock, SIOCSIFADDR, &ifr, "set address");
    set_sin(&ifr.ifr_netmask, host_mask);
    if_ioctl(sock, SIOCSIFNETMASK, &ifr, "set netmask");
    set_sin(&ifr.ifr_dstaddr, peer);
    if_ioctl(sock, SIOCSIFDSTADDR, &ifr, "set peer address");
    link_up(sock, ifname);
    if (default_route)
        add_route(sock, any, any);
    for (i = 0; i < nroutes; i++)
        add_route(sock, nets[i], masks[i]);
    close(sock);
    return fd;
}

/* Create /run/netns/NAME like `ip netns add`, and leave this process in it. */
static void enter_new_netns(const char *name)
{
    int fd, sock;

    if (strchr(name, '/') || !strcmp(name, ".") || !strcmp(name, "..")) {
        errno = 0;
        die("bad namespace name: %s", name);
    }
    if (mkdir("/run/netns", 0755) < 0 && errno != EEXIST)
        die("mkdir /run/netns");
    /* As iproute2 does, so the bind below propagates to mount namespaces
       created later. A bind made inside a service's private mount namespace
       (PrivateTmp=, ProtectSystem=) still never reaches the host. */
    if (mount("", "/run/netns", "none", MS_SHARED | MS_REC, NULL) < 0) {
        if (errno != EINVAL ||
            mount("/run/netns", "/run/netns", "none", MS_BIND | MS_REC, NULL) < 0 ||
            mount("", "/run/netns", "none", MS_SHARED | MS_REC, NULL) < 0)
            die("make /run/netns a shared mount");
    }
    snprintf(netns_path, sizeof(netns_path), "/run/netns/%s", name);
    fd = open(netns_path, O_RDONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0444);
    if (fd < 0) {
        netns_path[0] = '\0';
        die("create %s/%s", "/run/netns", name);
    }
    close(fd);
    if (unshare(CLONE_NEWNET) < 0)
        die("unshare network namespace");
    if (mount("/proc/self/ns/net", netns_path, "none", MS_BIND, NULL) < 0)
        die("bind %s", netns_path);
    sock = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (sock < 0)
        die("socket");
    link_up(sock, "lo");
    close(sock);
}

static void run_nft(const char *script)
{
    int fds[2], status;
    pid_t pid;

    if (pipe2(fds, O_CLOEXEC) < 0)
        die("pipe");
    pid = fork();
    if (pid < 0)
        die("fork");
    if (pid == 0) {
        dup2(fds[0], 0);
        dup2(2, 1); /* on the server, fd 1 is the tunnel stream */
        signal(SIGPIPE, SIG_DFL);
        execlp("nft", "nft", "-f", "-", (char *)NULL);
        _exit(127);
    }
    close(fds[0]);
    write_all(fds[1], script, strlen(script));
    close(fds[1]);
    if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status)) {
        errno = 0;
        die("nft failed (is nft on PATH?)");
    }
}

static void start_nat(struct in_addr peer)
{
    char script[768], peer_text[INET_ADDRSTRLEN];
    int fd;

    inet_ntop(AF_INET, &peer, peer_text, sizeof(peer_text));

    /* Recreate the table so a run killed with SIGKILL leaves nothing behind.
       The peer may only send as itself: forwarding is on, and anything else
       would reach routed networks un-NATed under a spoofed source. */
    snprintf(script, sizeof(script),
             "add table ip tunpipe_%s\n"
             "delete table ip tunpipe_%s\n"
             "table ip tunpipe_%s {\n"
             "  chain pre {\n"
             "    type filter hook prerouting priority raw; policy accept;\n"
             "    iifname \"%s\" ip saddr != %s drop\n"
             "  }\n"
             "  chain post {\n"
             "    type nat hook postrouting priority srcnat; policy accept;\n"
             "    ip saddr %s oifname != \"%s\" masquerade\n"
             "  }\n"
             "}\n",
             ifname, ifname, ifname, ifname, peer_text, peer_text, ifname);
    run_nft(script);
    nat_active = 1;
    /* shortcut: forwarding is left on at exit; other tunnels may rely on it.
       Restore it with refcounting if that ever matters. */
    fd = open("/proc/sys/net/ipv4/ip_forward", O_WRONLY | O_CLOEXEC);
    if (fd < 0 || write(fd, "1", 1) != 1)
        die("enable net.ipv4.ip_forward");
    close(fd);
}

/* Waits briefly for the child to exit, then terminates it. */
static int reap_child(void)
{
    struct timespec tick = { 0, 50 * 1000 * 1000 };
    int status = 0, i;

    for (i = 0; i < 60; i++) {
        if (waitpid(child, &status, WNOHANG) == child)
            goto reaped;
        if (i == 10)
            kill(child, SIGTERM);
        nanosleep(&tick, NULL);
    }
    kill(child, SIGKILL);
    waitpid(child, &status, 0);
reaped:
    child = -1;
    return status;
}

static void cleanup(void)
{
    char script[64];

    if (nat_active) {
        nat_active = 0;
        snprintf(script, sizeof(script), "delete table ip tunpipe_%s\n", ifname);
        run_nft(script);
    }
    if (netns_path[0]) {
        umount2(netns_path, MNT_DETACH);
        unlink(netns_path);
        netns_path[0] = '\0';
    }
    if (child > 0)
        reap_child();
}

static void on_signal(int sig)
{
    stop_signal = sig;
}

static int spawn(char **cmd)
{
    int sv[2];

    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) < 0)
        die("socketpair");
    child = fork();
    if (child < 0)
        die("fork");
    if (child == 0) {
        signal(SIGPIPE, SIG_DFL);
        dup2(sv[1], 0);
        dup2(sv[1], 1);
        execvp(cmd[0], cmd);
        fprintf(stderr, "tunpipe: exec %s: %s\n", cmd[0], strerror(errno));
        _exit(127);
    }
    close(sv[1]);
    return sv[0];
}

static time_t now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec;
}

/* Returns at the end of the stream; every failure exits through die(). */
static void pump(int tun, int in, int out)
{
    static unsigned char inbuf[2 * (FRAME_MAX + 2)];
    static unsigned char pkt[FRAME_MAX + 2];
    const unsigned char keepalive[2] = { 0, 0 };
    const struct timespec tick = { KEEPALIVE_SECS, 0 };
    size_t have = 0;
    time_t last_rx = now(), last_tx = last_rx;
    struct pollfd pfd[2] = { { .fd = tun, .events = POLLIN }, { .fd = in, .events = POLLIN } };
    sigset_t stops, unblocked;

    sigemptyset(&stops);
    sigaddset(&stops, SIGINT);
    sigaddset(&stops, SIGTERM);
    sigaddset(&stops, SIGHUP);
    for (;;) {
        /* Signals are blocked only between this check and ppoll, so one that
           arrives in between still interrupts ppoll, and blocking writes stay
           interruptible. */
        sigprocmask(SIG_BLOCK, &stops, &unblocked);
        if (stop_signal)
            finish(1);
        int ready = ppoll(pfd, 2, &tick, &unblocked);
        sigprocmask(SIG_SETMASK, &unblocked, NULL);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            die("poll");
        }
        /* Only on an idle wakeup: after a long blocked write, the peer's
           frames may be waiting unread. */
        if (ready == 0 && now() - last_rx >= PEER_TIMEOUT_SECS) {
            errno = 0;
            die("no data from the other end for %d s", PEER_TIMEOUT_SECS);
        }
        if (now() - last_tx >= KEEPALIVE_SECS) {
            write_all(out, keepalive, sizeof(keepalive));
            last_tx = now();
        }
        if (pfd[0].revents & (POLLERR | POLLHUP | POLLNVAL)) {
            errno = 0;
            die("%s went away", ifname);
        }
        if (pfd[0].revents & POLLIN) {
            ssize_t n = read(tun, pkt + 2, FRAME_MAX);
            if (n < 0 && errno != EINTR && errno != EAGAIN)
                die("read %s", ifname);
            if (n > 0) {
                pkt[0] = (unsigned char)(n >> 8);
                pkt[1] = (unsigned char)n;
                write_all(out, pkt, (size_t)n + 2);
                last_tx = now();
            }
        }
        if (pfd[1].revents & (POLLIN | POLLHUP | POLLERR)) {
            size_t off = 0;
            ssize_t n = read(in, inbuf + have, sizeof(inbuf) - have);
            if (n < 0 && errno == EINTR)
                continue;
            if (n < 0)
                die("read stream");
            if (n == 0)
                return;
            last_rx = now();
            have += (size_t)n;
            while (have - off >= 2) {
                size_t len = (size_t)inbuf[off] << 8 | inbuf[off + 1];
                if (have - off - 2 < len)
                    break;
                /* A bad packet is the kernel's to reject; keep the tunnel up. */
                if (len && write(tun, inbuf + off + 2, len) < 0 && errno != EINVAL)
                    die("write %s", ifname);
                off += len + 2;
            }
            memmove(inbuf, inbuf + off, have - off);
            have -= off;
        }
    }
}

int tunpipe_main(int argc, char **argv)
{
    struct in_addr local = { 0 }, peer = { 0 };
    struct in_addr nets[MAX_ROUTES], masks[MAX_ROUTES];
    char magic[MAGIC_LEN];
    const char *netns = NULL;
    int nroutes = 0, nat = 0, have_local = 0, have_peer = 0;
    int opt, tun, in = 0, out = 1, host_ns = -1, status;
    struct sigaction sa = { .sa_handler = on_signal };

    while ((opt = getopt(argc, argv, "+l:p:r:n:Ni:h")) != -1) {
        switch (opt) {
        case 'l': parse_addr(optarg, &local); have_local = 1; break;
        case 'p': parse_addr(optarg, &peer); have_peer = 1; break;
        case 'r':
            if (nroutes == MAX_ROUTES) {
                errno = 0;
                die("at most %d routes", MAX_ROUTES);
            }
            parse_cidr(optarg, &nets[nroutes], &masks[nroutes]);
            nroutes++;
            break;
        case 'n': netns = optarg; break;
        case 'N': nat = 1; break;
        case 'i':
            if (strlen(optarg) >= IFNAMSIZ) {
                errno = 0;
                die("interface name too long: %s", optarg);
            }
            strcpy(ifname, optarg);
            break;
        case 'h': usage(); return 0;
        default: usage(); return 2;
        }
    }
    if (!have_local || !have_peer) {
        usage();
        return 2;
    }

    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    if (netns) {
        host_ns = open("/proc/self/ns/net", O_RDONLY | O_CLOEXEC);
        if (host_ns < 0)
            die("open /proc/self/ns/net");
        enter_new_netns(netns);
    }
    tun = open_tun(local, peer, nets, masks, nroutes, netns != NULL);
    if (netns) {
        /* The tun stays in the new namespace; SSH and NAT stay in the host's. */
        if (setns(host_ns, CLONE_NEWNET) < 0)
            die("return to host network namespace");
        close(host_ns);
    }
    if (nat)
        start_nat(peer);
    if (optind < argc)
        in = out = spawn(argv + optind);

    write_all(out, MAGIC, MAGIC_LEN);
    if (read_full(in, magic, MAGIC_LEN) < 0 || memcmp(magic, MAGIC, MAGIC_LEN)) {
        errno = 0;
        die("the other end is not tunpipe (check that the remote command "
            "runs tunpipe and its shell prints nothing to stdout)");
    }
    fprintf(stderr, "tunpipe: %s up, %s -> ", ifname, inet_ntoa(local));
    fprintf(stderr, "%s\n", inet_ntoa(peer));

    pump(tun, in, out);
    if (child > 0) {
        close(in); /* a child waiting for EOF on its stdin can exit */
        status = reap_child();
        if (WIFEXITED(status) && WEXITSTATUS(status))
            finish(WEXITSTATUS(status));
    }
    finish(0);
    return 0; /* not reached; the tun closes at exit, after cleanup */
}
