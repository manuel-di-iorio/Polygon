if (!poly_is_active()) {
  // Open the editor on the authored scene: gameplay may have left the player
  // mid-jump or mid-turn, and the editor mirrors the live pose it finds.
  demo_reset_gameplay();
  poly_enable();
}
