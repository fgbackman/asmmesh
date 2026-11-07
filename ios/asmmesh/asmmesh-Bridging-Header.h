// What Swift sees of the assembly core (ios/asm/ios_ui.s and src/*.s).
#include <stdint.h>

// starting and the heartbeat
void am_set_device_name(const char *utf8);
void am_start(void);
long am_set_name(const char *utf8);

// listed rooms: ours, other people's, and asks to join ours
long am_room_listed(long i);
long am_room_set_listed(long i, long on);
long am_ad_count(void);
const char *am_ad_info(long k, long f);
uint64_t am_ad_id(long k);
long am_ad_asked(long k);
long am_ad_away(long k);
long am_ad_ask(long k);
long am_jr_count(void);
const char *am_jr_info(long i, long f);
long am_jr_answer(long i, long let_in);
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

// Hue bridges (hue.s): b 0-3; host "" when that slot is empty
const char *am_hue_host(long b);
const char *am_hue_name(long b);
long am_hue_paired(long b);

// what you typed, and Home's commands as you type (term_hist.s, as on the Mac)
const char *am_hist_prev(const char *typing);   // the line before, or NULL
const char *am_hist_next(void);                 // the line after (past the newest: the draft)
void am_hist_reset(void);
const char *am_hist_line(long k);               // k back from the newest, or NULL
long am_sg_count(const char *typing);           // matches (0 outside Home)
const char *am_sg_word(long i);
long am_sg_more(long i);                        // 1: takes more words after it

// people on the mesh
long am_node_count(void);
const char *am_node_nick(long i);
uint64_t am_node_id(long i);
long am_node_index(uint64_t id);
long am_seek_send(uint64_t to, const uint8_t *data, long len);
long am_node_info(long i, long k);          // 0 hops, 1 dBm, 2 seconds since heard, 3 relayed
char *am_node_fp(long i, char *buf);        // i = -1: this phone
const char *am_nick(void);

// bitchat people (bc_ble.s): walled off, a name and a line to show, nothing to act on
// MeshCore (mc_ble.s): the radio, and its contacts
long am_mc_state(void);                      // 0 off, 1 connecting, 2 starting, 3 ready
const char *am_mc_radio(void);
long am_mc_contacts(void);
const char *am_mc_contact_name(long i);
long am_mc_contact_seen(long i);             // unix time of their last advert

// Meshtastic (mt_ble.s): the radio, and the nodes it knows
long am_mt_state(void);                      // 0 off, 1 connecting, 2 starting, 3 ready
long am_mt_nodes(void);
const char *am_mt_node_name(long i);
long am_mt_node_seen(long i);                // unix time they were last heard

long am_bc_count(void);
const char *am_bc_nick(long k);
char *am_bc_line(long k, char *buf);       // buf: 128 bytes
const char *am_bc_hexid(long k);            // their peer id as hex ("bitchat chat <it>")
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

// Ninefold (nf_mesh.s): one game at a time, in its own invite-only room
long am_nf_state(void);                      // 0 none, 1 lobby, 2 starting, 3 playing, 4 checking, 5 scored
long am_nf_room(void);                       // the game room's index, or -1
long am_nf_host(void);                       // 1 if this phone starts the rounds
long am_nf_left(void);                       // seconds until the round starts / ends
char *am_nf_tiles(char *buf);                // buf: 10 bytes; 9 capitals, the centre 5th
long am_nf_status(char *buf, long cap);
long am_nf_mine(char *buf, long cap);        // your words this round, by spaces
long am_nf_players(char *buf, long cap);     // "name\twords\tscore\n" each, best first
long am_nf_result(long k, char *buf, long cap);  // the round's results, line k (0 after the last)
long am_nf_new(const long *people, long n, long rounds, long minutes, long family);
void nf_shuffle(void);
const char *am_nf_last(void);                // the answer to the last word typed, or ""

// chess (ch_mesh.s): one game at a time, over asmmesh or a bitchat private chat
long am_ch_state(void);                      // 0 none, 2 playing, 3 over
long am_ch_room(void);                       // the game's room (or chat) index, or -1
long am_ch_me(void);                         // 0 we're white, 8 black
long am_ch_piece(long square);               // 0x88 square: 0 empty, 1-6 white, 9-14 black
long am_ch_last(void);                       // from | to << 8, or -1
long am_ch_targets(long square, uint8_t *out);  // out: 32; where the piece there may go now
long am_ch_status(char *buf, long cap);
long am_ch_moves(char *buf, long cap);
const char *am_ch_opponent(void);
long am_ch_move(long from, long to);         // 1 if played
void am_ch_say(const char *word);            // "resign", "draw"

// Your shortcuts (quick.s): a name for Home commands, kept between launches
long am_qk_count(void);
const char *am_qk_name(long i);
const char *am_qk_cmds(long i);
void am_qk_run(long i);                      // runs each command in Home
long am_qk_save(const char *name, const char *commands);  // 0, -1 full, -2 bad name, -3 empty
long am_qk_delete(long i);

// Fivefold (ff_mesh.s): the game shown is a race or duel whose room is here, else today's word
long am_ff_mode(void);                       // 0 none, 1 today's word, 2 race, 3 duel
long am_ff_state(void);                      // 1 a duel: choosing their word, 2 guessing, 3 done
long am_ff_room(void);                       // a race or duel's room index, or -1
long am_ff_cell(long row, long col);         // letter << 8 | colour (0 1 2, 3 sent); 0 empty
long am_ff_key(long letter);                 // 'a'-'z': 3 not tried, else its best colour
long am_ff_status(char *buf, long cap);
long am_ff_share(char *buf, long cap);       // the squares (never the word)
long am_ff_others(char *buf, long cap);      // a race's other players and their colours
long am_ff_try(const char *text);            // a guess (a duel's first: their word): row, or < 0
const char *am_ff_why(long code);            // why a guess didn't count
void am_ff_solo(void);                       // today's word, on the screen

// block, report, the chat filter (safety.s)
long am_blk_node(long node);                 // 1 if that person is blocked
void am_blk_set_node(long node, long on);
void am_report_node(long node);              // an email about them (to the report address), and blocked
long am_filter(void);                        // 1 if the chat filter is on
void am_filter_set(long on);
const char *am_report_to(void);              // where reports go, or ""
void am_report_to_set(const char *address);

// objects the core talks to: the text field voice writes into, the Talk button
extern void *g_field;
extern void *g_talkbtn;
