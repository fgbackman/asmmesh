// weather.s — weather, sunrise/sunset and air quality for where you are, from
// Open-Meteo (free, no key). Where you are: "my city is Healdsburg" (Open-Meteo
// geocoding), or, until you say, a guess from your internet address (ipapi.co).
//
//   "weather"            now, and today's high/low/rain/sunset
//   "weather tomorrow"   tomorrow
//   "will it rain"       chance of rain today and tomorrow
//   "sunset" / "sunrise"
//   "air quality"        US AQI and PM2.5
//   "use celsius" / "use fahrenheit"
//
// Sunrise and sunset also feed rules like "at sunset turn on the porch light".

.include "macros.inc"

.set W_QUIET,    0
.set W_NOW,      1
.set W_TOMORROW, 2
.set W_AIR,      3
.set W_SUN,      4
.set W_RAIN,     5

.data
.p2align 3
.globl _g_sunrise_min
_g_sunrise_min:  .quad -1             // minutes after midnight, today; -1 unknown
.globl _g_sunset_min
_g_sunset_min:   .quad -1
_g_w_asked:      .quad 0              // ipapi asked already
.zerofill __DATA,__bss,_g_loc_lat,24,4
.zerofill __DATA,__bss,_g_loc_lon,24,4
.zerofill __DATA,__bss,_g_loc_name,64,4
.zerofill __DATA,__bss,_g_w_url,512,4
.zerofill __DATA,__bss,_g_w_tag,16,4
.zerofill __DATA,__bss,_g_w_line,480,4
.zerofill __DATA,__bss,_g_w_line2,480,4
.zerofill __DATA,__bss,_g_w_a,64,4
.zerofill __DATA,__bss,_g_w_b,160,4
.zerofill __DATA,__bss,_g_w_c,64,4
.zerofill __DATA,__bss,_g_w_d,64,4
.zerofill __DATA,__bss,_g_w_city,96,4

.section __DATA,__const
.p2align 3
Lcodes:
    .quad 0, Lwc_clear
    .quad 1, Lwc_mostly
    .quad 2, Lwc_partly
    .quad 3, Lwc_overcast
    .quad 45, Lwc_fog
    .quad 48, Lwc_fog
    .quad 51, Lwc_drizzle
    .quad 53, Lwc_drizzle
    .quad 55, Lwc_drizzle
    .quad 56, Lwc_fdrizzle
    .quad 57, Lwc_fdrizzle
    .quad 61, Lwc_lrain
    .quad 63, Lwc_rain
    .quad 65, Lwc_hrain
    .quad 66, Lwc_frain
    .quad 67, Lwc_frain
    .quad 71, Lwc_lsnow
    .quad 73, Lwc_snow
    .quad 75, Lwc_hsnow
    .quad 77, Lwc_snow
    .quad 80, Lwc_lshowers
    .quad 81, Lwc_showers
    .quad 82, Lwc_hshowers
    .quad 85, Lwc_snowshowers
    .quad 86, Lwc_snowshowers
    .quad 95, Lwc_thunder
    .quad 96, Lwc_hail
    .quad 99, Lwc_hail
    .quad -1, Lwc_unknown

.text
.p2align 2

// void _weather_init(void) — saved location, then today's sunrise/sunset
.globl _weather_init
_weather_init:
    ENTER 0
    ADRL x0, Ls_pref_lat
    ADRL x1, _g_loc_lat
    mov  x2, #24
    bl   _pref_get
    ADRL x0, Ls_pref_lon
    ADRL x1, _g_loc_lon
    mov  x2, #24
    bl   _pref_get
    ADRL x0, Ls_pref_loc
    ADRL x1, _g_loc_name
    mov  x2, #64
    bl   _pref_get
    mov  x0, #W_QUIET
    bl   _weather_ask
    LEAVE 0

// long _celsius(void) -> 1 if you asked for Celsius
_celsius:
    ENTER 16
    ADRL x0, Ls_pref_units
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]
    cmp  w9, #'c'
    cset x0, eq
    LEAVE 16

// void _weather_ask(long mode) — forecast (or air quality) for our location
.globl _weather_ask
_weather_ask:
    ENTER 16
    mov  x19, x0
    ADRL x8, _g_loc_lat
    ldrb w9, [x8]
    cbnz w9, Lwa_have
    ADRL x8, _g_w_asked               // where are we? ask once from the internet address
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, _g_w_tag
    mov  x1, #16
    ADRL x2, Lf_tag_ip
    mov  x3, x19
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, Ls_ipapi
    mov  x2, #0
    mov  x3, #0
    ADRL x4, _g_w_tag
    bl   _http
    LEAVE 16
Lwa_have:
    cmp  x19, #W_AIR
    b.eq Lwa_air
    bl   _celsius
    ADRL x6, Ls_fahrenheit
    ADRL x9, Ls_celsius_u
    cmp  x0, #0
    csel x5, x9, x6, ne
    ADRL x0, _g_w_url
    mov  x1, #512
    ADRL x2, Lf_forecast
    ADRL x3, _g_loc_lat
    ADRL x4, _g_loc_lon
    bl   _sfmt
    ADRL x0, _g_w_tag
    mov  x1, #16
    ADRL x2, Lf_tag_w
    mov  x3, x19
    bl   _sfmt
    b    Lwa_send
Lwa_air:
    ADRL x0, _g_w_url
    mov  x1, #512
    ADRL x2, Lf_air
    ADRL x3, _g_loc_lat
    ADRL x4, _g_loc_lon
    bl   _sfmt
    ADRL x0, _g_w_tag
    ADRL x1, Ls_tag_air
    mov  x2, #16
    bl   _strlcpy
Lwa_send:
    ADRL x0, Ls_GET
    ADRL x1, _g_w_url
    mov  x2, #0
    mov  x3, #0
    ADRL x4, _g_w_tag
    bl   _http
    LEAVE 16

// void _weather_city(const char *city) — "my city is ..." -> geocode it
.globl _weather_city
_weather_city:
    ENTER 0
    mov  x19, x0
    ADRL x20, _g_w_city               // URL-safe: letters, digits, - and , ; spaces as %20
    mov  x21, #0
Lwc_loop:
    ldrb w9, [x19], #1
    cbz  w9, Lwc_end
    cmp  x21, #80
    b.hs Lwc_end
    cmp  w9, #' '
    b.eq Lwc_space
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.ls Lwc_keep
    orr  w10, w9, #0x20
    sub  w10, w10, #'a'
    cmp  w10, #25
    b.ls Lwc_keep
    cmp  w9, #'-'
    b.eq Lwc_keep
    cmp  w9, #0x80                    // UTF-8 bytes (São Paulo): percent-encode
    b.hs Lwc_pct
    b    Lwc_loop
Lwc_keep:
    strb w9, [x20, x21]
    add  x21, x21, #1
    b    Lwc_loop
Lwc_space:
    mov  w9, #'+'
    strb w9, [x20, x21]
    add  x21, x21, #1
    b    Lwc_loop
Lwc_pct:
    mov  w10, #'%'
    strb w10, [x20, x21]
    lsr  w10, w9, #4
    ADRL x11, Lhex
    ldrb w10, [x11, x10]
    add  x12, x21, #1
    strb w10, [x20, x12]
    and  w10, w9, #15
    ldrb w10, [x11, x10]
    add  x12, x21, #2
    strb w10, [x20, x12]
    add  x21, x21, #3
    b    Lwc_loop
Lwc_end:
    strb wzr, [x20, x21]
    cbz  x21, Lwc_none
    ADRL x0, _g_w_url
    mov  x1, #512
    ADRL x2, Lf_geocode
    ADRL x3, _g_w_city
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_w_url
    mov  x2, #0
    mov  x3, #0
    ADRL x4, Ls_tag_geo
    bl   _http
    LEAVE 0
Lwc_none:
    ADRL x0, Ls_city_what
    bl   _home_say0
    LEAVE 0

// void _weather_units(long celsius)
.globl _weather_units
_weather_units:
    ENTER 0
    ADRL x1, Ls_f
    ADRL x9, Ls_c
    cmp  x0, #0
    csel x1, x9, x1, ne
    mov  x19, x0
    ADRL x0, Ls_pref_units
    bl   _pref_set
    ADRL x0, Ls_units_f
    ADRL x9, Ls_units_c
    cmp  x19, #0
    csel x0, x9, x0, ne
    bl   _home_say0
    LEAVE 0

// const char *_wcode(long code) -> "partly cloudy"
_wcode:
    ADRL x8, Lcodes
Lwcd_loop:
    ldp  x9, x10, [x8], #16
    tbnz x9, #63, Lwcd_hit
    cmp  x9, x0
    b.ne Lwcd_loop
Lwcd_hit:
    mov  x0, x10
    ret

// long _hhmm(const char *iso) -> minutes after midnight from "2026-09-29T06:59", or -1
.globl _hhmm
_hhmm:
    cbz  x0, Lhm_bad
    mov  x9, x0
Lhm_t:
    ldrb w10, [x9], #1
    cbz  w10, Lhm_bad
    cmp  w10, #'T'
    b.ne Lhm_t
    ldrb w10, [x9]
    ldrb w11, [x9, #1]
    ldrb w12, [x9, #3]
    ldrb w13, [x9, #4]
    sub  w10, w10, #'0'
    sub  w11, w11, #'0'
    sub  w12, w12, #'0'
    sub  w13, w13, #'0'
    mov  w14, #10
    madd w10, w10, w14, w11           // hours
    madd w12, w12, w14, w13           // minutes
    mov  w14, #60
    madd w0, w10, w14, w12
    sxtw x0, w0
    ret
Lhm_bad:
    mov  x0, #-1
    ret

// char *_clock12(long minutes, char *buf) — "6:52 pm"
.globl _clock12
_clock12:
    ENTER 0
    mov  x20, x1
    tbnz x0, #63, Lck_dash
    mov  x9, #60
    udiv x3, x0, x9
    msub x4, x3, x9, x0
    ADRL x5, Ls_am
    cmp  x3, #12
    b.lo Lck_am
    ADRL x5, Ls_pm
    sub  x3, x3, #12
Lck_am:
    cmp  x3, #0
    mov  x9, #12
    csel x3, x9, x3, eq
    mov  x0, x20
    mov  x1, #32
    ADRL x2, Lf_clock
    bl   _sfmt
    mov  x0, x20
    LEAVE 0
Lck_dash:
    mov  x0, x20
    ADRL x1, Ls_q
    mov  x2, #32
    bl   _strlcpy
    mov  x0, x20
    LEAVE 0

// const char *_place(void) -> "Healdsburg" or "your area"
_place:
    ADRL x0, _g_loc_name
    ldrb w9, [x0]
    cbnz w9, Lpl_ret
    ADRL x0, Ls_your_area
Lpl_ret:
    ret

// void _weather_response(const char *tag, id json, long status, NSError *err, NSData *raw)
.globl _weather_response
_weather_response:
    ENTER 64                          // [96] daily  [104] current  [112] mode
    mov  x19, x0
    mov  x20, x1
    str  x4, [sp, #120]               // the raw answer, for error messages
    ldrb w21, [x19, #1]
    ldrb w9, [x19, #2]
    sub  w9, w9, #'0'
    str  x9, [sp, #112]
    cbnz x3, Lwr_neterr
    cmp  x2, #300
    b.hs Lwr_http
    cmp  w21, #'i'
    b.eq Lwr_ip
    cmp  w21, #'g'
    b.eq Lwr_geo
    cmp  w21, #'a'
    b.eq Lwr_air
    b    Lwr_forecast
Lwr_neterr:
    ldr  x9, [sp, #112]
    cbz  x9, Lwr_done                 // background refresh: stay quiet
    mov  x0, x3
    bl   _err_cstr
    mov  x1, x0
    ADRL x0, Ls_w_unreach
    bl   _home_say
    LEAVE 64
Lwr_http:
    ldr  x9, [sp, #112]
    cmp  w21, #'g'
    b.eq Lwr_http_say
    cbz  x9, Lwr_done
Lwr_http_say:
    mov  x22, x2
    ADRL x23, Ls_w_forecast           // which service, and what it said
    cmp  w21, #'i'
    b.ne Lwr_http_geo
    ADRL x23, Ls_w_ipapi
Lwr_http_geo:
    cmp  w21, #'g'
    b.ne Lwr_http_air
    ADRL x23, Ls_w_geocoder
Lwr_http_air:
    cmp  w21, #'a'
    b.ne Lwr_http_reason
    ADRL x23, Ls_w_airsvc
Lwr_http_reason:
    ADRL x24, Ls_empty
    cbz  x20, Lwr_http_raw
    mov  x0, x20
    ADRL x1, Lj_reason
    bl   _jget
    bl   _jstr
    cbz  x0, Lwr_http_raw
    mov  x24, x0
    b    Lwr_http_out
Lwr_http_raw:                         // not JSON: show the start of what came back
    ldr  x0, [sp, #120]
    cbz  x0, Lwr_http_out
    MSG0 Ls_length
    cmp  x0, #100
    mov  x9, #100
    csel x0, x9, x0, hi
    str  x0, [sp, #128]
    ldr  x0, [sp, #120]
    MSG0 Ls_bytes
    mov  x1, x0
    ADRL x0, _g_w_line
    ldr  x2, [sp, #128]
    bl   _memcpy
    ADRL x8, _g_w_line
    ldr  x9, [sp, #128]
    strb wzr, [x8, x9]
Lwr_raw_clean:
    cbz  x9, Lwr_raw_done
    sub  x9, x9, #1
    ldrb w10, [x8, x9]
    cmp  w10, #' '
    b.lo Lwr_raw_sp
    cmp  w10, #0x7e
    b.ls Lwr_raw_clean
Lwr_raw_sp:
    mov  w10, #' '
    strb w10, [x8, x9]
    b    Lwr_raw_clean
Lwr_raw_done:
    ADRL x24, _g_w_line
Lwr_http_out:
    ADRL x0, _g_w_line2
    mov  x1, #480
    ADRL x2, Ls_w_http
    mov  x3, x23
    mov  x4, x22
    mov  x5, x24
    ADRL x6, _g_w_url
    bl   _sfmt
    ADRL x0, _g_w_line2
    bl   _home_say0
    cmp  w21, #'w'                    // a saved place the forecast won't take: forget it
    b.ne Lwr_done
    cmp  x22, #400
    b.ne Lwr_done
    ADRL x8, _g_loc_lat
    strb wzr, [x8]
    ADRL x8, _g_loc_lon
    strb wzr, [x8]
    bl   _loc_save
Lwr_done:
    LEAVE 64

Lwr_ip:                               // ipapi.co: {"city","region","latitude","longitude"}
    mov  x0, x20
    ADRL x1, Lj_latitude
    ADRL x2, _g_loc_lat
    bl   _jnum_to
    cbz  x0, Lwr_ip_fail
    mov  x0, x20
    ADRL x1, Lj_longitude
    ADRL x2, _g_loc_lon
    bl   _jnum_to
    cbz  x0, Lwr_ip_fail
    mov  x0, x20
    ADRL x1, Lj_city
    bl   _jget
    bl   _jstr
    cbz  x0, Lwr_ip_save
    mov  x1, x0
    ADRL x0, _g_loc_name
    mov  x2, #64
    bl   _strlcpy
Lwr_ip_save:
    bl   _loc_save
    ldr  x0, [sp, #112]               // now what was asked for
    bl   _weather_ask
    LEAVE 64
Lwr_ip_fail:
    ldr  x9, [sp, #112]
    cbz  x9, Lwr_done
    ADRL x0, Ls_city_what
    bl   _home_say0
    LEAVE 64

Lwr_geo:                              // {"results":[{"name","admin1","country","latitude","longitude"}]}
    mov  x0, x20
    ADRL x1, Lj_results
    bl   _jget
    mov  x1, #0
    bl   _jat
    mov  x21, x0
    cbz  x21, Lwr_geo_none
    ADRL x1, Lj_latitude
    ADRL x2, _g_loc_lat
    bl   _jnum_to
    cbz  x0, Lwr_geo_none
    mov  x0, x21
    ADRL x1, Lj_longitude
    ADRL x2, _g_loc_lon
    bl   _jnum_to
    mov  x0, x21
    ADRL x1, Lj_name
    bl   _jget
    bl   _jstr
    cbz  x0, Lwr_geo_save
    mov  x1, x0
    ADRL x0, _g_loc_name
    mov  x2, #64
    bl   _strlcpy
Lwr_geo_save:
    bl   _loc_save
    mov  x0, x21                      // "Healdsburg, California"
    ADRL x1, Lj_admin1
    bl   _jget
    bl   _jstr
    mov  x2, x0
    cbnz x2, Lwr_geo_say
    ADRL x2, Ls_empty
Lwr_geo_say:
    ADRL x1, _g_loc_name
    ADRL x0, Ls_loc_set
    bl   _home_say
    mov  x0, #W_QUIET
    bl   _weather_ask
    LEAVE 64
Lwr_geo_none:
    ADRL x0, Ls_city_unknown
    bl   _home_say0
    LEAVE 64

Lwr_air:                              // {"current":{"us_aqi":42,"pm2_5":9.1}}
    mov  x0, x20
    ADRL x1, Lj_current
    bl   _jget
    mov  x21, x0
    ADRL x1, Lj_us_aqi
    bl   _jget
    bl   _jround
    mov  x22, x0
    mov  x0, x21
    ADRL x1, Lj_pm25
    bl   _jget
    bl   _jround
    mov  x5, x0
    ADRL x4, Laq_good
    cmp  x22, #50
    b.ls Lwr_air_say
    ADRL x4, Laq_moderate
    cmp  x22, #100
    b.ls Lwr_air_say
    ADRL x4, Laq_sensitive
    cmp  x22, #150
    b.ls Lwr_air_say
    ADRL x4, Laq_unhealthy
    cmp  x22, #200
    b.ls Lwr_air_say
    ADRL x4, Laq_very
    cmp  x22, #300
    b.ls Lwr_air_say
    ADRL x4, Laq_hazard
Lwr_air_say:
    str  x5, [sp, #96]
    str  x4, [sp, #104]
    bl   _place
    mov  x1, x0
    mov  x2, x22
    ldr  x3, [sp, #104]
    ldr  x4, [sp, #96]
    ADRL x0, Ls_air_line
    bl   _home_say4
    LEAVE 64

Lwr_forecast:
    mov  x0, x20
    ADRL x1, Lj_daily
    bl   _jget
    str  x0, [sp, #96]
    mov  x0, x20
    ADRL x1, Lj_current
    bl   _jget
    str  x0, [sp, #104]
    ldr  x0, [sp, #96]                // sunrise / sunset for the rules
    ADRL x1, Lj_sunrise
    bl   _jget
    mov  x1, #0
    bl   _jat
    bl   _jstr
    bl   _hhmm
    ADRL x8, _g_sunrise_min
    str  x0, [x8]
    ldr  x0, [sp, #96]
    ADRL x1, Lj_sunset
    bl   _jget
    mov  x1, #0
    bl   _jat
    bl   _jstr
    bl   _hhmm
    ADRL x8, _g_sunset_min
    str  x0, [x8]
    ldr  x9, [sp, #112]
    cmp  x9, #W_NOW
    b.eq Lwf_now
    cmp  x9, #W_TOMORROW
    b.eq Lwf_tomorrow
    cmp  x9, #W_SUN
    b.eq Lwf_sun
    cmp  x9, #W_RAIN
    b.eq Lwf_rain
    LEAVE 64

Lwf_now:  // "Weather in Healdsburg: 72°, clear, feels like 70°, humidity 40%, wind 5 mph."
    ldr  x0, [sp, #104]
    ADRL x1, Lj_temp
    bl   _jget
    bl   _jround
    mov  x22, x0
    ldr  x0, [sp, #104]
    ADRL x1, Lj_code
    bl   _jget
    bl   _jint
    bl   _wcode
    mov  x23, x0
    ldr  x0, [sp, #104]
    ADRL x1, Lj_feels
    bl   _jget
    bl   _jround
    mov  x24, x0
    bl   _place
    mov  x3, x0
    mov  x4, x22
    mov  x5, x23
    mov  x6, x24
    ADRL x0, _g_w_line
    mov  x1, #480
    ADRL x2, Lf_now1
    bl   _sfmt
    ldr  x0, [sp, #104]
    ADRL x1, Lj_humidity
    bl   _jget
    bl   _jround
    mov  x22, x0
    ldr  x0, [sp, #104]
    ADRL x1, Lj_wind
    bl   _jget
    bl   _jround
    mov  x4, x0
    mov  x3, x22
    ADRL x0, _g_w_a
    mov  x1, #64
    ADRL x2, Lf_now2
    bl   _sfmt
    ADRL x0, _g_w_line
    ADRL x1, _g_w_a
    mov  x2, #480
    bl   _strlcat
    mov  x0, #0                       // "Today: high 81°, low 52°, 10% chance of rain. Sunset 6:52 pm."
    ldr  x1, [sp, #96]
    bl   _day_text
    ADRL x0, _g_w_line
    ADRL x1, _g_w_b
    mov  x2, #480
    bl   _strlcat
    ADRL x8, _g_sunset_min
    ldr  x0, [x8]
    ADRL x1, _g_w_c
    bl   _clock12
    mov  x3, x0
    ADRL x0, _g_w_a
    mov  x1, #64
    ADRL x2, Lf_sunset_tail
    bl   _sfmt
    ADRL x0, _g_w_line
    ADRL x1, _g_w_a
    mov  x2, #480
    bl   _strlcat
    ADRL x0, _g_w_line
    bl   _home_say0
    LEAVE 64

Lwf_tomorrow:
    mov  x0, #1
    ldr  x1, [sp, #96]
    bl   _day_text
    bl   _place
    mov  x1, x0
    ADRL x2, _g_w_b
    ADRL x0, Ls_tomorrow_line
    bl   _home_say
    LEAVE 64

Lwf_rain:
    ldr  x0, [sp, #96]
    ADRL x1, Lj_rainprob
    bl   _jget
    mov  x22, x0
    mov  x1, #0
    bl   _jat
    bl   _jround
    mov  x23, x0
    mov  x0, x22
    mov  x1, #1
    bl   _jat
    bl   _jround
    mov  x3, x0
    mov  x2, x23
    str  x3, [sp, #120]
    bl   _place
    mov  x1, x0
    mov  x2, x23
    ldr  x3, [sp, #120]
    ADRL x0, Ls_rain_line
    bl   _home_say
    LEAVE 64

Lwf_sun:
    ADRL x8, _g_sunrise_min
    ldr  x0, [x8]
    ADRL x1, _g_w_a
    bl   _clock12
    ADRL x8, _g_sunset_min
    ldr  x0, [x8]
    ADRL x1, _g_w_c
    bl   _clock12
    bl   _place
    mov  x3, x0
    ADRL x1, _g_w_a
    ADRL x2, _g_w_c
    ADRL x0, Ls_sun_line
    bl   _home_say
    LEAVE 64

// void _day_text(long day, NSDictionary *daily) — "Today: partly cloudy, high 81°, low 52°,
//   10% chance of rain." into _g_w_b
_day_text:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    ADRL x1, Lj_dcode
    bl   _jget
    mov  x1, x19
    bl   _jat
    bl   _jint
    bl   _wcode
    str  x0, [sp, #96]
    mov  x0, x20
    ADRL x1, Lj_tmax
    bl   _jget
    mov  x1, x19
    bl   _jat
    bl   _jround
    str  x0, [sp, #104]
    mov  x0, x20
    ADRL x1, Lj_tmin
    bl   _jget
    mov  x1, x19
    bl   _jat
    bl   _jround
    str  x0, [sp, #112]
    mov  x0, x20
    ADRL x1, Lj_rainprob
    bl   _jget
    mov  x1, x19
    bl   _jat
    bl   _jround
    mov  x7, x0
    ldr  x4, [sp, #96]
    ldr  x5, [sp, #104]
    ldr  x6, [sp, #112]
    ADRL x3, Ls_today
    ADRL x9, Ls_tomorrow_w
    cmp  x19, #0
    csel x3, x9, x3, ne
    ADRL x0, _g_w_b
    mov  x1, #160
    ADRL x2, Lf_day
    bl   _sfmt
    LEAVE 32

// long _jnum_to(id dict, const char *key, char *out24) -> 1 if a number was there
_jnum_to:
    ENTER 0
    mov  x20, x2
    bl   _jget
    cbz  x0, Ljn_no
    mov  x1, x20
    mov  x2, #24
    bl   _jdesc
    ldrb w9, [x20]
    cbz  w9, Ljn_no
    mov  x0, #1
    LEAVE 0
Ljn_no:
    mov  x0, #0
    LEAVE 0

// void _loc_save(void)
_loc_save:
    ENTER 0
    ADRL x0, Ls_pref_lat
    ADRL x1, _g_loc_lat
    bl   _pref_set
    ADRL x0, Ls_pref_lon
    ADRL x1, _g_loc_lon
    bl   _pref_set
    ADRL x0, Ls_pref_loc
    ADRL x1, _g_loc_name
    bl   _pref_set
    LEAVE 0

// void _home_say4(fmt, a, b, c, d) — a Home line with four arguments
.globl _home_say4
_home_say4:
    ENTER 512
    mov  x6, x4
    mov  x5, x3
    mov  x4, x2
    mov  x3, x1
    mov  x2, x0
    add  x0, sp, #96
    mov  x1, #400
    bl   _sfmt
    add  x0, sp, #96
    bl   _home_say0
    LEAVE 512

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lhex:            .asciz "0123456789ABCDEF"   // NUL-terminated: in a C-string section an
                                                  // unterminated string runs into the next one
Ls_GET:          .asciz "GET"
Ls_empty:        .asciz ""
Ls_ipapi:        .asciz "https://ipapi.co/json/"
Lf_forecast:     .asciz "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset&timezone=auto&forecast_days=2&wind_speed_unit=mph&temperature_unit=%s"
Lf_air:          .asciz "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=%s&longitude=%s&current=us_aqi,pm2_5"
Lf_geocode:      .asciz "https://geocoding-api.open-meteo.com/v1/search?count=1&name=%s"
Lf_tag_ip:       .asciz "wi%ld"
Lf_tag_w:        .asciz "ww%ld"
Ls_tag_air:      .asciz "wa3"
Ls_tag_geo:      .asciz "wg0"
Ls_fahrenheit:   .asciz "fahrenheit"
Ls_celsius_u:    .asciz "celsius"
Ls_pref_lat:     .asciz "loc_lat"
Ls_pref_lon:     .asciz "loc_lon"
Ls_pref_loc:     .asciz "loc_name"
Ls_pref_units:   .asciz "units"
Ls_f:            .asciz "f"
Ls_c:            .asciz "c"
Ls_units_f:      .asciz "\302\267 Temperatures in Fahrenheit."
Ls_units_c:      .asciz "\302\267 Temperatures in Celsius."
Ls_am:           .asciz "am"
Ls_pm:           .asciz "pm"
Lf_clock:        .asciz "%ld:%02ld %s"
Ls_q:            .asciz "?"
Ls_your_area:    .asciz "your area"
Ls_today:        .asciz "Today"
Ls_tomorrow_w:   .asciz "Tomorrow"
Lf_now1:         .asciz "\302\267 Weather in %s: %ld\302\260, %s, feels like %ld\302\260"
Lf_now2:         .asciz ", humidity %ld%%, wind %ld mph. "
Lf_day:          .asciz "%s: %s, high %ld\302\260, low %ld\302\260, %ld%% chance of rain."
Lf_sunset_tail:  .asciz " Sunset %s."
Ls_tomorrow_line: .asciz "\302\267 %s \342\200\224 %s"
Ls_rain_line:    .asciz "\302\267 Chance of rain in %s: %ld%% today, %ld%% tomorrow."
Ls_sun_line:     .asciz "\302\267 Sunrise %s, sunset %s in %s."
Ls_air_line:     .asciz "\302\267 Air quality in %s: US AQI %ld (%s), PM2.5 %ld \302\265g/m\302\263."
Laq_good:        .asciz "good"
Laq_moderate:    .asciz "moderate"
Laq_sensitive:   .asciz "unhealthy for sensitive groups"
Laq_unhealthy:   .asciz "unhealthy"
Laq_very:        .asciz "very unhealthy"
Laq_hazard:      .asciz "hazardous"
Ls_loc_set:      .asciz "\302\267 Location set: %s, %s. Say \342\200\234weather\342\200\235, \342\200\234sunset\342\200\235 or \342\200\234air quality\342\200\235."
Ls_city_unknown: .asciz "\302\267 I couldn't find that place. Try \342\200\234my city is Healdsburg\342\200\235 or add the state: \342\200\234my city is Portland, Oregon\342\200\235."
Ls_city_what:    .asciz "\302\267 Where are you? Say \342\200\234my city is \342\200\246\342\200\235 with your town's name."
Ls_w_unreach:    .asciz "\302\267 Can't reach the weather service: %s"
Ls_w_http:       .asciz "\302\267 %s answered HTTP %ld %s [%s]"
Ls_w_forecast:   .asciz "Open-Meteo"
Ls_w_ipapi:      .asciz "ipapi.co (where you are)"
Ls_w_geocoder:   .asciz "The Open-Meteo place search"
Ls_w_airsvc:     .asciz "Open-Meteo air quality"
Lj_reason:       .asciz "reason"
Ls_length:       .asciz "length"
Ls_bytes:        .asciz "bytes"
Lj_latitude:     .asciz "latitude"
Lj_longitude:    .asciz "longitude"
Lj_city:         .asciz "city"
Lj_results:      .asciz "results"
Lj_name:         .asciz "name"
Lj_admin1:       .asciz "admin1"
Lj_current:      .asciz "current"
Lj_daily:        .asciz "daily"
Lj_temp:         .asciz "temperature_2m"
Lj_feels:        .asciz "apparent_temperature"
Lj_humidity:     .asciz "relative_humidity_2m"
Lj_code:         .asciz "weather_code"
Lj_wind:         .asciz "wind_speed_10m"
Lj_dcode:        .asciz "weather_code"
Lj_tmax:         .asciz "temperature_2m_max"
Lj_tmin:         .asciz "temperature_2m_min"
Lj_rainprob:     .asciz "precipitation_probability_max"
Lj_sunrise:      .asciz "sunrise"
Lj_sunset:       .asciz "sunset"
Lj_us_aqi:       .asciz "us_aqi"
Lj_pm25:         .asciz "pm2_5"
Lwc_clear:       .asciz "clear"
Lwc_mostly:      .asciz "mostly clear"
Lwc_partly:      .asciz "partly cloudy"
Lwc_overcast:    .asciz "overcast"
Lwc_fog:         .asciz "foggy"
Lwc_drizzle:     .asciz "drizzle"
Lwc_fdrizzle:    .asciz "freezing drizzle"
Lwc_lrain:       .asciz "light rain"
Lwc_rain:        .asciz "rain"
Lwc_hrain:       .asciz "heavy rain"
Lwc_frain:       .asciz "freezing rain"
Lwc_lsnow:       .asciz "light snow"
Lwc_snow:        .asciz "snow"
Lwc_hsnow:       .asciz "heavy snow"
Lwc_lshowers:    .asciz "light showers"
Lwc_showers:     .asciz "showers"
Lwc_hshowers:    .asciz "heavy showers"
Lwc_snowshowers: .asciz "snow showers"
Lwc_thunder:     .asciz "thunderstorms"
Lwc_hail:        .asciz "thunderstorms with hail"
Lwc_unknown:     .asciz "unsettled"
