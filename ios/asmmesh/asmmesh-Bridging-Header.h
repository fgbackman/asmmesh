// What Swift sees of the assembly core (ios/asm/ios_ui.s and src/*.s).
#include <stdint.h>

// starting and the heartbeat
void am_start(void);
void am_tick(void);

// rooms
long am_room_count(void);
uint64_t am_room_id(long i);
const char *am_room_name(long i);
long am_room_unread(long i);
long am_room_mine(long i);
long am_cur_room(void);
void am_select_room(long i);
void am_send(const char *text);
void am_home(const char *text);

// people on the mesh
long am_node_count(void);
const char *am_node_nick(long i);
long am_node_info(long i, long k);          // 0 hops, 1 dBm, 2 seconds since heard, 3 relayed
char *am_node_fp(long i, char *buf);        // i = -1: this phone
const char *am_nick(void);
char *am_status(void);

// actions; each shows its own prompt
void am_new_room(void);
void am_invite(long node);
void am_leave_room(void);
void am_delete_room(void);
long am_delete_room_ask(char *title, char *info);
long am_delete_room_confirmed(char *title, char *info);
void am_change_name(void);
void am_talk(void);
void am_connect_st(void);
void am_connect_ha(void);
void am_connect_lifx(void);
void am_connect_govee(void);
void am_pair_hue(void);
void am_pair_nano(void);
void am_airdrop(void);
long am_scan_count(void);
const char *am_scan_cell(long row, long column);
const char *am_scan_details(long row);
void am_scan_pair(long row);
void am_scan_setup(long row);
long am_spin_get(long what, long i, long s);
void am_spin_set(long what, long i, long s, long value, const char *text);
void am_mesh_pass(void);
void am_refresh_home(void);

// services (Settings)
long am_svc_count(void);
long am_svc_field(long i, long k);          // 1 title, 2 subtitle, 3 SF Symbol (char *), 4 colour
long am_svc_on(long i);
void am_svc_set(long i, long on);

// Bluetooth sensors and nearby devices
long am_sensor_count(void);
long am_sensor_info(long i, long k);        // 0 label, 1 reading, 2 age, 3 kind (char *), 4 named, 5 dBm
long am_near_count(void);
long am_near_info(long i, long k);          // 0 name, 1 maker, 2 what (char *), 3 dBm, 4 age, 5 flags

// objects the core talks to: the text field voice writes into, the Talk button
extern void *g_field;
extern void *g_talkbtn;
