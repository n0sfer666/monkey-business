/* Synthetic packet qualification. Never linked into the router application. */
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#define REQUIRE(x, message) do { if (!(x)) { perror(message); exit(1); } } while (0)
static struct sockaddr_in address(unsigned short port) {
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET; a.sin_port = htons(port);
    REQUIRE(inet_pton(AF_INET, "127.0.0.1", &a.sin_addr) == 1, "address");
    return a;
}
static int udp(unsigned short port) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    REQUIRE(fd >= 0, "udp socket");
    struct sockaddr_in a = address(port);
    REQUIRE(bind(fd, (struct sockaddr *)&a, sizeof(a)) == 0, "udp bind");
    struct timeval timeout = { .tv_sec = 1, .tv_usec = 0 };
    REQUIRE(setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0, "udp timeout");
    return fd;
}
static void exact(int fd, unsigned char *buffer, size_t size) {
    size_t done = 0;
    while (done < size) {
        ssize_t count = recv(fd, buffer + done, size - done, 0);
        REQUIRE(count > 0, "SOCKS read"); done += (size_t)count;
    }
}
static void foreign(unsigned short port, const unsigned char *data, size_t length) {
    pid_t pid = fork(); REQUIRE(pid >= 0, "fork");
    if (pid == 0) {
        REQUIRE(setuid(65534) == 0, "setuid");
        int fd = udp(0); struct sockaddr_in a = address(port);
        REQUIRE(sendto(fd, data, length, 0, (struct sockaddr *)&a, sizeof(a)) == (ssize_t)length, "foreign send");
        close(fd); _exit(0);
    }
    int status; REQUIRE(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0, "foreign child");
}
static int dns_server(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0); REQUIRE(fd >= 0, "DNS socket");
    struct sockaddr_in bind_address = address(53); bind_address.sin_addr.s_addr = htonl(INADDR_ANY);
    REQUIRE(bind(fd, (struct sockaddr *)&bind_address, sizeof(bind_address)) == 0, "DNS bind");
    for (;;) {
        unsigned char query[4096], answer[8192]; struct sockaddr_in peer; socklen_t size = sizeof(peer);
        ssize_t length = recvfrom(fd, query, sizeof(query), 0, (struct sockaddr *)&peer, &size);
        if (length < 12 || length > 4000) continue;
        size_t end = 12;
        while (end < (size_t)length && query[end] != 0 && query[end] < 64) end += (size_t)query[end] + 1;
        end += 5; if (end > (size_t)length) continue; length = (ssize_t)end;
        memcpy(answer, query, (size_t)length); answer[2] = 0x81; answer[3] = 0x80;
        answer[6] = 0; answer[7] = 1; answer[8] = 0; answer[9] = 0; answer[10] = 0; answer[11] = 0;
        const unsigned char record[] = {0xc0,0x0c,0,1,0,1,0,0,0,30,0,4,192,0,2,42};
        memcpy(answer + length, record, sizeof(record));
        REQUIRE(sendto(fd, answer, (size_t)length + sizeof(record), 0, (struct sockaddr *)&peer, size) == length + (ssize_t)sizeof(record), "DNS answer");
    }
}
static int direct_server(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0), reuse = 1;
    REQUIRE(fd >= 0, "direct socket");
    REQUIRE(setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) == 0, "reuse");
    struct sockaddr_in a = address(18081); a.sin_addr.s_addr = htonl(INADDR_ANY);
    REQUIRE(bind(fd, (struct sockaddr *)&a, sizeof(a)) == 0 && listen(fd, 32) == 0, "direct listen");
    for (;;) {
        int client = accept(fd, NULL, NULL); if (client < 0) continue;
        const char response[] = "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\ndirect";
        send(client, response, sizeof(response)-1, MSG_NOSIGNAL); close(client);
        puts("direct-contact"); fflush(stdout);
    }
}
int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "direct-server") == 0) return direct_server();
    if (argc == 2 && strcmp(argv[1], "dns-server") == 0) return dns_server();
    int control = -1;
    for (int attempt = 0; attempt < 60; attempt++) {
        control = socket(AF_INET, SOCK_STREAM, 0); REQUIRE(control >= 0, "tcp socket");
        struct sockaddr_in a = address(12001);
        if (connect(control, (struct sockaddr *)&a, sizeof(a)) == 0) break;
        close(control); control = -1; usleep(50000);
    }
    REQUIRE(control >= 0, "SOCKS readiness");
    struct timeval timeout = { .tv_sec = 3, .tv_usec = 0 };
    REQUIRE(setsockopt(control, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0, "tcp timeout");
    unsigned char response[4096];
    unsigned char method[] = {5, 1, 2};
    REQUIRE(send(control, method, sizeof(method), 0) == sizeof(method), "method send");
    exact(control, response, 2); REQUIRE(response[0] == 5 && response[1] == 2, "password method");
    unsigned char auth[] = "\1\11synthetic\11synthetic";
    REQUIRE(send(control, auth, sizeof(auth)-1, 0) == sizeof(auth)-1, "auth send");
    exact(control, response, 2); REQUIRE(response[0] == 1 && response[1] == 0, "auth accepted");
    unsigned char associate[] = {5,3,0,1,0,0,0,0,0,0};
    REQUIRE(send(control, associate, sizeof(associate), 0) == sizeof(associate), "associate send");
    exact(control, response, 10);
    REQUIRE(memcmp(response, "\5\0\0\1\177\0\0\1", 8) == 0, "loopback relay");
    unsigned short relay = ((unsigned short)response[8] << 8) | response[9];
    int target = udp(0); struct sockaddr_in target_address; socklen_t size = sizeof(target_address);
    REQUIRE(getsockname(target, (struct sockaddr *)&target_address, &size) == 0, "target address");
    unsigned char packet[32] = {0,0,0,1,127,0,0,1};
    memcpy(packet + 8, &target_address.sin_port, 2); memcpy(packet + 10, "synthetic", 9);
    foreign(relay, packet, 19);
    REQUIRE(recv(target, response, sizeof(response), 0) < 0 && (errno == EAGAIN || errno == EWOULDBLOCK), "foreign relay blocked");
    int root = udp(0); struct sockaddr_in relay_address = address(relay);
    REQUIRE(sendto(root, packet, 19, 0, (struct sockaddr *)&relay_address, sizeof(relay_address)) == 19, "root send");
    struct sockaddr_in peer; socklen_t peer_size = sizeof(peer);
    ssize_t received = recvfrom(target, response, sizeof(response), 0, (struct sockaddr *)&peer, &peer_size);
    REQUIRE(received == 9 && memcmp(response, "synthetic", 9) == 0, "root VPN path");
    REQUIRE(sendto(target, response, 9, 0, (struct sockaddr *)&peer, peer_size) == 9, "target response");
    received = recv(root, response, sizeof(response), 0);
    REQUIRE(received >= 9 && memcmp(response + received - 9, "synthetic", 9) == 0, "root VPN response");
    foreign(ntohs(target_address.sin_port), (const unsigned char *)"unrelated", 9);
    REQUIRE(recv(target, response, sizeof(response), 0) == 9 && memcmp(response, "unrelated", 9) == 0, "unrelated UDP unaffected");
    close(root); close(target); close(control);
    printf("PASS: Hysteria dynamic relay %u blocks uid=65534 before first packet; root VPN and unrelated UDP work\n", relay);
    return 0;
}
