# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-11-02

### Added
- First release: the classic tile-matching solitaire. Take matching pairs of
  free tiles off the table until it is empty; flowers match flowers and
  seasons match seasons.
- Six layouts: Pyramid (56 tiles), Fortress (72), Temple (72, default),
  Bridge (88), Big pyramid (120) and Turtle (144).
- Every deal can be won: deals are built backwards from an empty table.
- Hints checked to keep the game winnable from the current position (with an
  honest label when the on-device search runs out of time); the hint also
  says when the game can no longer be won.
- Shuffle into an arrangement that can be cleared, Undo for pairs and
  shuffles, tiles-left and free-pairs counters, timer and auto-save.
- Statistics per layout (won / played, best time) and a Daily Challenge.
- Two tile styles drawn for grey-scale e-ink: Readable (numbers and suit
  signs) and Traditional; optional greying of blocked tiles.
