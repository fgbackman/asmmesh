// voice.s — press 🎤 Talk, say a command, it runs in the Home room.
//
// SFSpeechRecognizer (on-device when the Mac supports it) fed by an
// AVAudioEngine input tap. The tap and the permission request take blocks, so
// two global block literals are laid out by hand below: no captures, so the
// runtime never copies them, and their invoke functions read globals.
// Listening stops by itself 1.5 s after you stop talking, after 10 s, or when
// you press Stop.

.include "macros.inc"

.set BLOCK_GLOBAL_SIG, 0x50000000     // BLOCK_IS_GLOBAL | BLOCK_HAS_SIGNATURE

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_talkbtn
_g_talkbtn:     .quad 0
_g_rec:         .quad 0
_g_req:         .quad 0
_g_task:        .quad 0
_g_engine:      .quad 0
_g_listening:   .quad 0
_g_have_hyp:    .quad 0
_g_final:       .quad 0
_g_hyp_tick:    .quad 0
_g_start_tick:  .quad 0
.zerofill __DATA,__bss,_g_voice_text,256,4

// struct Block_literal { isa; int flags; int reserved; invoke; descriptor }
Ltap_block:
    .quad __NSConcreteGlobalBlock
    .long BLOCK_GLOBAL_SIG
    .long 0
    .quad _voice_tap
    .quad Ltap_desc
Ltap_desc:
    .quad 0, 32, Lsig_tap             // reserved, size, signature
Lauth_block:
    .quad __NSConcreteGlobalBlock
    .long BLOCK_GLOBAL_SIG
    .long 0
    .quad _voice_auth
    .quad Lauth_desc
Lauth_desc:
    .quad 0, 32, Lsig_auth

// ---------------------------------------------------------------------------
.text
.p2align 2

// void (^tap)(AVAudioPCMBuffer *buf, AVAudioTime *when) — on the audio thread
_voice_tap:
    ENTER 0
    mov  x19, x1
    ADRL x8, _g_req
    ldr  x0, [x8]
    cbz  x0, Lvt_done
    mov  x2, x19
    MSG1 Ls_appendAudio
Lvt_done:
    LEAVE 0

// void (^auth)(SFSpeechRecognizerAuthorizationStatus) — any thread; hop to main
_voice_auth:
    ENTER 0
    LDGOT x0, __dispatch_main_q
    ADRL x2, _voice_auth_main
    bl   _dispatch_async_f            // x1 (the status) is the context
    LEAVE 0

_voice_auth_main:
    ENTER 0
    cmp  x0, #3                       // SFSpeechRecognizerAuthorizationStatusAuthorized
    b.ne Lvam_denied
    bl   _voice_start
    LEAVE 0
Lvam_denied:
    ADRL x0, Ls_denied
    bl   _home_say0
    LEAVE 0

// - (void)talk:(id)sender
.globl _voice_toggle
_voice_toggle:
    ENTER 0
    ADRL x8, _g_listening
    ldr  x9, [x8]
    cbz  x9, Lvtg_start
    bl   _voice_stop
    LEAVE 0
Lvtg_start:
    mov  x0, #SVC_VOICE               // the Talk button is a service like the rest
    bl   _svc_gate
    cbnz x0, Lvtg_on
    LEAVE 0
Lvtg_on:
    CLS  Ls_SFSpeechRecognizer
    MSG0 Ls_authorizationStatus
    cmp  x0, #3
    b.eq Lvtg_go
    cbnz x0, Lvtg_denied
    CLS  Ls_SFSpeechRecognizer
    ADRL x2, Lauth_block
    MSG1 Ls_requestAuthorization
    LEAVE 0
Lvtg_go:
    bl   _voice_start
    LEAVE 0
Lvtg_denied:
    ADRL x0, Ls_denied
    bl   _home_say0
    LEAVE 0

// void _voice_start(void)
_voice_start:
    ENTER 16
    ADRL x8, _g_rec
    ldr  x0, [x8]
    cbnz x0, Lvs_have_rec
    CLS  Ls_SFSpeechRecognizer
    MSG0 Ls_new
    ADRL x8, _g_rec
    str  x0, [x8]
    cbz  x0, Lvs_unavailable
Lvs_have_rec:
    mov  x19, x0
    MSG0 Ls_isAvailable
    tst  w0, #0xff
    b.eq Lvs_unavailable

    CLS  Ls_SFSpeechAudioBufferRecognitionRequest
    MSG0 Ls_new
    mov  x20, x0
    mov  x2, #1
    MSG1 Ls_setShouldReportPartial
    mov  x0, x19
    MSG0 Ls_supportsOnDevice
    tst  w0, #0xff
    b.eq Lvs_engine
    mov  x0, x20
    mov  x2, #1
    MSG1 Ls_setRequiresOnDevice
Lvs_engine:
    ADRL x8, _g_req
    str  x20, [x8]
    ADRL x8, _g_engine
    ldr  x0, [x8]
    cbnz x0, Lvs_have_engine
    CLS  Ls_AVAudioEngine
    MSG0 Ls_new
    ADRL x8, _g_engine
    str  x0, [x8]
Lvs_have_engine:
    mov  x21, x0
    MSG0 Ls_inputNode
    mov  x22, x0
    mov  x2, #0
    MSG1 Ls_outputFormatForBus
    mov  x4, x0
    mov  x0, x22
    mov  x2, #0                       // bus
    mov  x3, #1024                    // frames per buffer
    ADRL x5, Ltap_block
    MSG4 Ls_installTap
    mov  x0, x21
    MSG0 Ls_prepare
    str  xzr, [sp, #96]
    mov  x0, x21
    add  x2, sp, #96
    MSG1 Ls_startAndReturnError
    tst  w0, #0xff
    b.eq Lvs_nomic

    mov  x0, x19
    mov  x2, x20
    ADRL x8, _g_ctl
    ldr  x3, [x8]
    MSG2 Ls_recognitionTask
    MSG0 Ls_retain
    ADRL x8, _g_task
    str  x0, [x8]
    ADRL x8, _g_listening
    mov  x9, #1
    str  x9, [x8]
    ADRL x8, _g_have_hyp
    str  xzr, [x8]
    ADRL x8, _g_final
    str  xzr, [x8]
    ADRL x8, _g_voice_text
    strb wzr, [x8]
    ADRL x8, _g_tick
    ldr  x9, [x8]
    ADRL x8, _g_start_tick
    str  x9, [x8]
    ADRL x8, _g_hyp_tick
    str  x9, [x8]

    ADRL x8, _g_home_idx              // talk happens in Home
    ldr  x0, [x8]
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    cmp  x0, x9
    b.eq Lvs_ui
    bl   _ui_select_room
Lvs_ui:
    ADRL x0, Ls_stop_title
    bl   _talk_title
    ADRL x0, Ls_listening
    bl   _field_placeholder
    LEAVE 16

Lvs_nomic:
    mov  x0, x22
    mov  x2, #0
    MSG1 Ls_removeTap
    ADRL x8, _g_req
    ldr  x0, [x8]
    str  xzr, [x8]
    MSG0 Ls_release
    ldr  x0, [sp, #96]
    bl   _err_cstr
    mov  x1, x0
    ADRL x0, Ls_nomic
    bl   _home_say
    LEAVE 16
Lvs_unavailable:
    ADRL x0, Ls_unavailable
    bl   _home_say0
    LEAVE 16

// void _voice_stop(void) — stop the microphone; the recogniser finishes up
.globl _voice_stop
_voice_stop:
    ENTER 0
    ADRL x8, _g_listening
    ldr  x9, [x8]
    cbz  x9, Lvp_done
    str  xzr, [x8]
    ADRL x8, _g_engine
    ldr  x19, [x8]
    mov  x0, x19
    MSG0 Ls_stop
    mov  x0, x19
    MSG0 Ls_inputNode
    mov  x2, #0
    MSG1 Ls_removeTap
    ADRL x8, _g_req
    ldr  x0, [x8]
    MSG0 Ls_endAudio
    ADRL x0, Ls_talk_title
    bl   _talk_title
    ADRL x0, Ls_empty
    bl   _field_placeholder
Lvp_done:
    LEAVE 0

// void _voice_tick(void) — auto-stop after a pause or 10 seconds
.globl _voice_tick
_voice_tick:
    ENTER 0
    ADRL x8, _g_listening
    ldr  x9, [x8]
    cbz  x9, Lvk_done
    ADRL x8, _g_tick
    ldr  x19, [x8]
    ADRL x8, _g_start_tick
    ldr  x9, [x8]
    sub  x9, x19, x9
    cmp  x9, #100
    b.hs Lvk_stop
    ADRL x8, _g_have_hyp
    ldr  x9, [x8]
    cbz  x9, Lvk_done
    ADRL x8, _g_hyp_tick
    ldr  x9, [x8]
    sub  x9, x19, x9
    cmp  x9, #15
    b.lo Lvk_done
Lvk_stop:
    bl   _voice_stop
Lvk_done:
    LEAVE 0

// - speechRecognitionTask:didHypothesizeTranscription: — live text in the field
.globl _voice_hyp
_voice_hyp:
    ENTER 0
    mov  x0, x3
    MSG0 Ls_formattedString
    mov  x19, x0
    ADRL x8, _g_field
    ldr  x0, [x8]
    mov  x2, x19
    MSG1 Ls_setStringValue
    ADRL x8, _g_have_hyp
    mov  x9, #1
    str  x9, [x8]
    ADRL x8, _g_tick
    ldr  x9, [x8]
    ADRL x8, _g_hyp_tick
    str  x9, [x8]
    LEAVE 0

// - speechRecognitionTask:didFinishRecognition: — the final words
.globl _voice_final
_voice_final:
    ENTER 0
    mov  x0, x3
    MSG0 Ls_bestTranscription
    MSG0 Ls_formattedString
    MSG0 Ls_UTF8String
    cbz  x0, Lvf_done
    mov  x1, x0
    ADRL x0, _g_voice_text
    mov  x2, #256
    bl   _strlcpy
    ADRL x8, _g_final
    mov  x9, #1
    str  x9, [x8]
Lvf_done:
    LEAVE 0

// - speechRecognitionTask:didFinishSuccessfully: — run it, tidy up
.globl _voice_done
_voice_done:
    ENTER 0
    mov  w19, w3
    bl   _voice_stop
    ADRL x0, Ls_empty
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_field
    ldr  x0, [x8]
    cbz  x0, Lvd_check
    MSG1 Ls_setStringValue
Lvd_check:
    ADRL x8, _g_final
    ldr  x9, [x8]
    cbz  x9, Lvd_nothing
    ADRL x8, _g_voice_text
    ldrb w9, [x8]
    cbz  w9, Lvd_nothing
    ADRL x0, _g_voice_text
    mov  w1, #1
    bl   _home_command
    b    Lvd_release
Lvd_nothing:
    ADRL x8, _g_have_hyp
    ldr  x9, [x8]
    cbnz x9, Lvd_release
    ADRL x0, Ls_didnt_catch
    bl   _home_say0
Lvd_release:
    ADRL x8, _g_task
    ldr  x0, [x8]
    str  xzr, [x8]
    MSG0 Ls_release
    ADRL x8, _g_req
    ldr  x0, [x8]
    str  xzr, [x8]
    MSG0 Ls_release
    ADRL x8, _g_final
    str  xzr, [x8]
    LEAVE 0

// void _talk_title(const char *utf8)
_talk_title:
    ENTER 0
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_talkbtn
    ldr  x0, [x8]
    cbz  x0, Ltt_done
    MSG1 Ls_setTitle
Ltt_done:
    LEAVE 0

// void _field_placeholder(const char *utf8) — "" = the room's usual prompt
_field_placeholder:
    ENTER 0
    ldrb w9, [x0]
    cbz  w9, Lfp_room
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_field
    ldr  x0, [x8]
    cbz  x0, Lfp_done
    MSG1 Ls_setPlaceholderString
    LEAVE 0
Lfp_room:
    ADRL x8, _g_cur_room
    ldr  x0, [x8]
    bl   _ui_select_room
Lfp_done:
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lsig_tap:        .asciz "v24@?0@8@16"
Lsig_auth:       .asciz "v16@?0q8"
Ls_SFSpeechRecognizer: .asciz "SFSpeechRecognizer"
Ls_SFSpeechAudioBufferRecognitionRequest: .asciz "SFSpeechAudioBufferRecognitionRequest"
Ls_AVAudioEngine: .asciz "AVAudioEngine"
Ls_appendAudio:  .asciz "appendAudioPCMBuffer:"
Ls_authorizationStatus: .asciz "authorizationStatus"
Ls_requestAuthorization: .asciz "requestAuthorization:"
Ls_new:          .asciz "new"
Ls_retain:       .asciz "retain"
Ls_release:      .asciz "release"
Ls_isAvailable:  .asciz "isAvailable"
Ls_setShouldReportPartial: .asciz "setShouldReportPartialResults:"
Ls_supportsOnDevice: .asciz "supportsOnDeviceRecognition"
Ls_setRequiresOnDevice: .asciz "setRequiresOnDeviceRecognition:"
Ls_inputNode:    .asciz "inputNode"
Ls_outputFormatForBus: .asciz "outputFormatForBus:"
Ls_installTap:   .asciz "installTapOnBus:bufferSize:format:block:"
Ls_removeTap:    .asciz "removeTapOnBus:"
Ls_prepare:      .asciz "prepare"
Ls_startAndReturnError: .asciz "startAndReturnError:"
Ls_stop:         .asciz "stop"
Ls_endAudio:     .asciz "endAudio"
Ls_recognitionTask: .asciz "recognitionTaskWithRequest:delegate:"
Ls_formattedString: .asciz "formattedString"
Ls_bestTranscription: .asciz "bestTranscription"
Ls_UTF8String:   .asciz "UTF8String"
Ls_setStringValue: .asciz "setStringValue:"
Ls_setPlaceholderString: .asciz "setPlaceholderString:"
Ls_setTitle:     .asciz "setTitle:"
Ls_empty:        .asciz ""
Ls_talk_title:   .asciz "\360\237\216\244 Talk"
Ls_stop_title:   .asciz "\342\226\240 Stop"
Ls_listening:    .asciz "Listening\342\200\246 say something like \342\200\234kitchen lights off\342\200\235"
Ls_denied:       .asciz "\302\267 asmmesh isn't allowed to use speech recognition. Turn it on in System Settings \342\200\272 Privacy & Security \342\200\272 Speech Recognition (and Microphone)."
Ls_unavailable:  .asciz "\302\267 Speech recognition isn't available right now for this Mac's language."
Ls_nomic:        .asciz "\302\267 Couldn't start the microphone: %s"
Ls_didnt_catch:  .asciz "\302\267 Didn't catch that \342\200\224 press Talk and try again."
