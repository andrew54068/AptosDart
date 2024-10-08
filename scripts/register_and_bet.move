script {
    use flick_arena_bet::game;

    fun register_and_bet(player: signer, host_addr: address, bet_amount: u64) {
        game::register_and_bet(&player, host_addr, bet_amount);
    }
}