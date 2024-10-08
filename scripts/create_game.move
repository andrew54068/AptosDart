script {
    use flick_arena_bet::game;

    fun create_game(host: signer, target_score: u64, max_rounds: u64) {
        game::initialize(&host, target_score, max_rounds);
    }
}