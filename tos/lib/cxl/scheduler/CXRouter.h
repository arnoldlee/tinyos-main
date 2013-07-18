#ifndef CX_ROUTER_H
#define CX_ROUTER_H

typedef struct contact_entry{
  am_addr_t nodeId;
  bool dataPending;
} contact_entry_t;

#ifndef CX_MAX_SUBNETWORK_SIZE
#define CX_MAX_SUBNETWORK_SIZE 60
#endif

#define SS_KEY_MAX_DOWNLOAD_ROUNDS 0x19

#ifndef DEFAULT_MAX_DOWNLOAD_ROUNDS
#define DEFAULT_MAX_DOWNLOAD_ROUNDS 2
#endif

#endif
