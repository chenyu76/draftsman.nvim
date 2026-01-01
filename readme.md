# Draftman.nvim

## TODO

- move edge command
- fix known problem
- wrap text option
- write a readme
- vertial line at cursor
- no quit when press space in text mode

## Known Problem

- Some wide characters (`\t`, CJK, etc.) have strange behaviour.
- Move edge command:
  - make some wrong line at some complex structure.
  - sometime move edge to the right will fail.

```
   ┌─────────┐   ┌────────┐
   │  Hello! │   │ Hello! │
   └─────────┘   └────────┘
                 ┌────────┐
                 │ Hello! │
                 └────────┘
                 ┌────────┐
                 │ Hello! │
                 └────────┘

         ┌───────────┐
         │ hello     │
         │           │
         └───────────┘



```
