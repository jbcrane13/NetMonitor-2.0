#ifndef CRESOLV_H
#define CRESOLV_H

/// Writes the resolver's DNS server addresses (numeric, one per line) into `out`.
/// Returns the number of servers written, or -1 when the resolver can't be read.
int nm_copy_dns_servers(char *out, int out_len);

#endif
