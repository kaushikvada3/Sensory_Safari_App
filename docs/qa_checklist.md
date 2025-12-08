# Sensory Safari QA Checklist

## iPad
- Medium difficulty is noticeably faster than Easy and slower than Difficult.
- Non-response X marker appears on every trial in Difficult mode.
- Increasing stimulus duration from 4s to 8s keeps animal speed constant (stream runs longer only).

## Android (Samsung phone)
- UI fits within the screen: no clipped buttons, no overflow, sprites stay within bounds.
- Difficulty changes alter stream speed (Easy < Medium < Difficult < Very Difficult).
- Positive feedback shows rotating pet images without repeating back-to-back.
- No consecutive duplicate pet image displays across trials.

## Web
- Same verifications as Android (layout, speed ordering, rotating pets).
- Charts, tables, and timeline cards display “Difficult” / “Very Difficult” labels.
