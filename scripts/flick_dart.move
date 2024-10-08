script {
    use flick_arena_bet::game;

    fun flick_dart(host: signer, player: address, score: u64) {
        game::flick_dart(&host, player, score);
    }
}