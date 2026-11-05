# SPIN remote (SDC-1) Bluetooth LE protocol

**Source:** SPIN remote B.V. publishes the protocol for developers: *SPIN remote Bluetooth
Smart Services v1.0* (27-01-2017), a PDF in their SDK
[github.com/SPINremote/sdc-1-quickstart-ios](https://github.com/SPINremote/sdc-1-quickstart-ios),
MIT licence, © 2017 SPIN remote B.V. (see `CREDITS.md`). It covers the SPIN service
`5E5A10D3-…`, the Command characteristic `92E92B18-…` (`08 01`: force action notifications;
`09 R G B`: set the LED colour; `07`: cancel the LED override) and the Action characteristic
`182BEC1F-…` (gestures 0-19).

**Beyond the spec** (marked reserved there): gestures 20-24, the other characteristics and the
LED service below. We noted these from SPIN's own Android app (v1.1.0.14). asmmesh uses only
gestures 20-24 and, for older firmware without the Command characteristic, the LED service.

Connect as BLE central. No proprietary auth for reading gestures — just enable
notifications (write CCCD 0x2902 = 01 00) on the action characteristic.

## Interaction service  5E5A10D3-6EC7-17AF-D743-3CF1679C1CC7
- 182BEC1F-51A4-458E-4B48-C431EA701A3B  ACTION  (notify)  ONE byte = gesture code:
    0 ROTATE_RIGHT_SIDE_UP_CLOCKWISE      13 TOUCHPAD_PRESS_WEST
    1 ROTATE_RIGHT_SIDE_UP_CCW            14 TOUCHPAD_PRESS_CENTER
    2 ROTATE_SIDEWAYS_CW                  15 TOUCHPAD_LONG_PRESS_NORTH
    3 ROTATE_SIDEWAYS_CCW                 16 TOUCHPAD_LONG_PRESS_SOUTH
    4 ROTATE_UPSIDE_DOWN_CW               17 TOUCHPAD_LONG_PRESS_EAST
    5 ROTATE_UPSIDE_DOWN_CCW              18 TOUCHPAD_LONG_PRESS_WEST
    6 TOUCHPAD_SWIPE_UP                   19 TOUCHPAD_LONG_PRESS_CENTER
    7 TOUCHPAD_SWIPE_DOWN                 20 TOUCHPAD_SCROLL_CLOCKWISE
    8 TOUCHPAD_SWIPE_LEFT                 21 TOUCHPAD_SCROLL_COUNTERCLOCKWISE
    9 TOUCHPAD_SWIPE_RIGHT                22 SHELL_DOUBLE_TAP
   10 TOUCHPAD_PRESS_NORTH                23 SPIN_SLEEP
   11 TOUCHPAD_PRESS_SOUTH                24 SPIN_WAKE_UP
   12 TOUCHPAD_PRESS_EAST                255/-1 UNKNOWN
- 92E92B18-FA20-D486-5E43-099387C61A71  config (notify+write) byte0=enum + payload
- E4ED5371-870B-6C88-1347-2C8B789A64AC  (notify+write) uint8,uint32,uint8
- 2CDBCC81-B066-7886-4644-D3E2B235193E  data (notify+write)
- C221D500-D006-7DA3-634B-95CCD8172F2B  write-status (notify) enum
- 64DB9A27-FCD4-CFBC-5B48-DF01CF240F18  MOTION (notify) 4x float32 LE (quaternion/accel)
- 703FE135-0056-7398-1C4F-42E1636C2FD8  small int 0..7 (read+write+notify) e.g. haptic/level
- 227A7AA2-7393-6180-DC45-1D0970B5C68E  button-map save result (notify) enum+uint32

## LED service  BDF1ED51-6FF4-9DB7-F646-007627DD7DF3
- 4A60B963-AD6A-53A0-DE4D-DBD27386F8F1  LED colour (read+write+notify) 3 bytes R,G,B

## Firmware/OTA service  9DFACA9D-7801-22A0-9540-F0BB65E824FC  (not needed)
Standard services also present: 0x1812 HID-over-GATT, 0x180A device info, 0x180F battery.
