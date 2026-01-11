#Requires AutoHotkey v2.0
#SingleInstance

; Danish chars on ;'[
;
; !;::Send {U+00E6}   ; æ
;+!;::Send {U+00C6}   ; Æ
; !'::Send {U+00F8}   ; ø
;+!'::Send {U+00D8}   ; Ø
; ![::Send {U+00E5}   ; å
;+![::Send {U+00C5}   ; Å



; Danish chars on ;'[  (AutoHotkey v2)

 !;::Send("{U+00E6}")   ; æ
+!;::Send("{U+00C6}")   ; Æ

 !'::Send("{U+00F8}")   ; ø
+!'::Send("{U+00D8}")   ; Ø

 ![::Send("{U+00E5}")   ; å
+![::Send("{U+00C5}")   ; Å