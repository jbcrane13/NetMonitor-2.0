#include "cresolv.h"
#include <netdb.h>
#include <resolv.h>
#include <string.h>
#include <sys/socket.h>

int nm_copy_dns_servers(char *out, int out_len) {
    if (out == NULL || out_len <= 0) return -1;
    out[0] = '\0';

    struct __res_state state;
    memset(&state, 0, sizeof(state));
    if (res_ninit(&state) != 0) return -1;

    union res_sockaddr_union addrs[MAXNS];
    int count = res_getservers(&state, addrs, MAXNS);
    int written = 0;
    size_t used = 0;
    for (int i = 0; i < count; i++) {
        const struct sockaddr *sa = (const struct sockaddr *)&addrs[i];
        char host[NI_MAXHOST];
        if (getnameinfo(sa, sa->sa_len, host, sizeof(host), NULL, 0, NI_NUMERICHOST) != 0) continue;
        size_t len = strlen(host);
        if (used + len + 2 > (size_t)out_len) break;
        memcpy(out + used, host, len);
        used += len;
        out[used++] = '\n';
        out[used] = '\0';
        written++;
    }
    res_ndestroy(&state);
    return written;
}
