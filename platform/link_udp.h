/* platform/link_udp.c: the desktop's link between consoles, UDP multicast on the local network. */
#pragma once
#include <stdbool.h>
#include <stdint.h>

bool link_udp_open(void);
void link_udp_close(void);
bool link_udp_send(const uint8_t *p, int n);
int link_udp_recv(uint8_t *p, int max);
uint32_t link_udp_id(void);
