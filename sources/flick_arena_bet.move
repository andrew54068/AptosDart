module flick_arena_bet::game {
    use std::signer;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account;
    use aptos_framework::event;

    const MAX_DARTS_PER_TURN: u64 = 3;
    const HOST_FEE_PERCENTAGE: u64 = 1; // 1% fee

    const ENOT_INITIALIZED: u64 = 1;
    const EGAME_ALREADY_STARTED: u64 = 2;
    const EMAXIMUM_PLAYERS_REACHED: u64 = 3; // Assuming this was the original error number, adjust if needed
    const EINVALID_BET_AMOUNT: u64 = 4;
    const EGAME_NOT_IN_PROGRESS: u64 = 5;
    const ENOT_HOST: u64 = 6;
    const EINVALID_SCORE: u64 = 7;
    const ETOO_MANY_DARTS: u64 = 8;
    const EINVALID_PLAYER: u64 = 9;
    const ECURRENT_PLAYER_NOT_FINISHED: u64 = 10; // Adjust the number if needed
    const EBETS_NOT_EQUAL: u64 = 11;
    const EGAME_NOT_ENDED: u64 = 12;
    const EINVALID_PLAYER_INDEX: u64 = 13; // or whatever number is appropriate in your error code sequence

    struct GameConfig has key {
        target_score: u64,
        max_rounds: u64,
    }

    struct Player has store, drop {
        addr: address,
        score: u64,
        dart_scores: vector<vector<u64>>,
        bet: u64,
    }

    struct GameState has key {
        players: vector<Player>,
        current_player_index: u64,
        current_round: u64,
        game_started: bool,
        game_ended: bool,
        host: address,
        prize_pool: u64,
    }

    struct GameEvents has key {
        player_registered: event::EventHandle<PlayerRegisteredEvent>,
        bet_placed: event::EventHandle<BetPlacedEvent>,
        game_started: event::EventHandle<GameStartedEvent>,
        dart_flicked: event::EventHandle<DartFlickedEvent>,
        player_won: event::EventHandle<PlayerWonEvent>,
        game_ended: event::EventHandle<GameEndedEvent>,
        game_drawn: event::EventHandle<GameDrawnEvent>,
    }

    struct PlayerRegisteredEvent has drop, store {
        player: address,
        player_index: u64,
    }

    struct BetPlacedEvent has drop, store {
        player: address,
        amount: u64,
    }

    struct GameStartedEvent has drop, store {}

    struct DartFlickedEvent has drop, store {
        player: address,
        score: u64,
    }

    struct PlayerWonEvent has drop, store {
        winner: address,
        prize: u64,
    }

    struct GameEndedEvent has drop, store {
        winner: address,
    }

    struct GameDrawnEvent has drop, store {
        refund_amount: u64,
    }

    public entry fun initialize(host: &signer, target_score: u64, max_rounds: u64) acquires GameConfig, GameState {
        let host_addr = signer::address_of(host);
        
        if (!exists<GameConfig>(host_addr)) {
            move_to(host, GameConfig {
                target_score,
                max_rounds,
            });
        } else {
            // Update existing GameConfig
            let game_config = borrow_global_mut<GameConfig>(host_addr);
            game_config.target_score = target_score;
            game_config.max_rounds = max_rounds;
        };

        if (!exists<GameState>(host_addr)) {
            move_to(host, GameState {
                players: vector::empty(),
                current_player_index: 0,
                current_round: 1,
                game_started: false,
                game_ended: false,
                host: host_addr,
                prize_pool: 0,
            });
        } else {
            // Check if the current game has ended and the caller is the host
            let game_state = borrow_global<GameState>(host_addr);
            assert!(game_state.game_ended, EGAME_NOT_ENDED);
            assert!(game_state.host == host_addr, ENOT_HOST);

            // Reset existing GameState
            let game_state = borrow_global_mut<GameState>(host_addr);
            game_state.players = vector::empty();
            game_state.current_player_index = 0;
            game_state.current_round = 1;
            game_state.game_started = false;
            game_state.game_ended = false;
            game_state.prize_pool = 0;
        };

        if (!exists<GameEvents>(host_addr)) {
            move_to(host, GameEvents {
                player_registered: account::new_event_handle<PlayerRegisteredEvent>(host),
                bet_placed: account::new_event_handle<BetPlacedEvent>(host),
                game_started: account::new_event_handle<GameStartedEvent>(host),
                dart_flicked: account::new_event_handle<DartFlickedEvent>(host),
                player_won: account::new_event_handle<PlayerWonEvent>(host),
                game_ended: account::new_event_handle<GameEndedEvent>(host),
                game_drawn: account::new_event_handle<GameDrawnEvent>(host),
            });
        }
    }

    public entry fun register_and_bet(player: &signer, host_addr: address, bet_amount: u64) acquires GameState, GameConfig, GameEvents {
        let player_addr = signer::address_of(player);
        let game_state = borrow_global_mut<GameState>(host_addr);
        let game_config = borrow_global<GameConfig>(host_addr);
        let game_events = borrow_global_mut<GameEvents>(host_addr);

        assert!(!game_state.game_started, EGAME_ALREADY_STARTED);
        assert!(vector::length(&game_state.players) < 2, EMAXIMUM_PLAYERS_REACHED);
        assert!(bet_amount > 0, EINVALID_BET_AMOUNT);

        let player_index = vector::length(&game_state.players);
        let new_player = Player {
            addr: player_addr,
            score: game_config.target_score,
            dart_scores: vector::empty(),
            bet: bet_amount,
        };

        vector::push_back(&mut game_state.players, new_player);
        game_state.prize_pool = game_state.prize_pool + bet_amount;

        event::emit_event(&mut game_events.player_registered, PlayerRegisteredEvent {
            player: player_addr,
            player_index,
        });

        event::emit_event(&mut game_events.bet_placed, BetPlacedEvent {
            player: player_addr,
            amount: bet_amount,
        });

        coin::transfer<AptosCoin>(player, host_addr, bet_amount);

        if (vector::length(&game_state.players) == 2) {
            let first_player = vector::borrow(&game_state.players, 0);
            assert!(bet_amount == first_player.bet, EBETS_NOT_EQUAL);
        };

        if (vector::length(&game_state.players) == 2) {
            game_state.game_started = true;
            event::emit_event(&mut game_events.game_started, GameStartedEvent {});
        }
    }

    public entry fun flick_dart(host: &signer, player: address, score: u64) acquires GameState, GameConfig, GameEvents {
        let host_addr = signer::address_of(host);
        let game_state = borrow_global_mut<GameState>(host_addr);
        let game_config = borrow_global<GameConfig>(host_addr);
        let game_events = borrow_global_mut<GameEvents>(host_addr);

        assert!(game_state.game_started && !game_state.game_ended, EGAME_NOT_IN_PROGRESS);
        assert!(host_addr == game_state.host, ENOT_HOST);
        assert!(score >= 0 && score <= 60, EINVALID_SCORE);

        let current_player = vector::borrow_mut(&mut game_state.players, game_state.current_player_index);
        
        assert!(player == current_player.addr, EINVALID_PLAYER);

        let round_index = game_state.current_round - 1;
        if (vector::length(&current_player.dart_scores) <= round_index) {
            vector::push_back(&mut current_player.dart_scores, vector::empty());
        };

        let current_round_scores = vector::borrow_mut(&mut current_player.dart_scores, round_index);
        assert!(vector::length(current_round_scores) < MAX_DARTS_PER_TURN, ETOO_MANY_DARTS);

        vector::push_back(current_round_scores, score);
        
        event::emit_event(&mut game_events.dart_flicked, DartFlickedEvent {
            player: current_player.addr,
            score,
        });

        if (current_player.score >= score) {
            current_player.score = current_player.score - score;

            if (current_player.score == 0) {
                end_game(host, game_state, game_events, current_player.addr);
                return
            }
        };

        if (vector::length(current_round_scores) == MAX_DARTS_PER_TURN) {
            internal_switch_player(game_state, game_config, game_events, host);
        };
    }

    public entry fun switch_player(host: &signer) acquires GameState, GameConfig, GameEvents {
        let host_addr = signer::address_of(host);
        let game_state = borrow_global_mut<GameState>(host_addr);
        let game_config = borrow_global<GameConfig>(host_addr);
        let game_events = borrow_global_mut<GameEvents>(host_addr);

        internal_switch_player(game_state, game_config, game_events, host);
    }

    fun internal_switch_player(game_state: &mut GameState, game_config: &GameConfig, game_events: &mut GameEvents, host: &signer) {
        game_state.current_player_index = 1 - game_state.current_player_index;
        if (game_state.current_player_index == 0) {
            game_state.current_round = game_state.current_round + 1;
            if (game_state.current_round > game_config.max_rounds) {
                end_game(host, game_state, game_events, @0x0); // Pass @0x0 to indicate no direct winner
            }
        }
    }

    fun end_game(host: &signer, game_state: &mut GameState, game_events: &mut GameEvents, winner: address) {
        game_state.game_ended = true;
        let host_fee = game_state.prize_pool / 100 * HOST_FEE_PERCENTAGE;
        let winner_prize = game_state.prize_pool - host_fee;

        if (winner == @0x0) {
            // Determine the winner based on the lowest score
            let player0 = vector::borrow(&game_state.players, 0);
            let player1 = vector::borrow(&game_state.players, 1);
            if (player0.score < player1.score) {
                winner = player0.addr;
            } else if (player1.score < player0.score) {
                winner = player1.addr;
            } else {
                // In case of a tie, refund players
                let refund_amount = game_state.prize_pool / 2;
                transfer_coins(host, player0.addr, refund_amount);
                transfer_coins(host, player1.addr, refund_amount);
                event::emit_event(&mut game_events.game_drawn, GameDrawnEvent { refund_amount });
                event::emit_event(&mut game_events.game_ended, GameEndedEvent { winner: @0x0 });
                return
            }
        };

        transfer_coins(host, game_state.host, host_fee);
        transfer_coins(host, winner, winner_prize);
        event::emit_event(&mut game_events.player_won, PlayerWonEvent { winner, prize: winner_prize });
        event::emit_event(&mut game_events.game_ended, GameEndedEvent { winner });
    }

    fun transfer_coins(from: &signer, to: address, amount: u64) {
        let coins = coin::withdraw<AptosCoin>(from, amount);
        coin::deposit(to, coins);
    }

    fun calculate_round_score(player: &Player, round: u64): u64 {
        let round_scores = vector::borrow(&player.dart_scores, round);
        let total_score = 0;
        let i = 0;
        while (i < vector::length<u64>(round_scores)) {
            total_score = total_score + *vector::borrow(round_scores, i);
            i = i + 1;
        };
        total_score
    }

    // Public view functions
    #[view]
    public fun get_game_config(host_addr: address): (u64, u64) acquires GameConfig {
        let game_config = borrow_global<GameConfig>(host_addr);
        (game_config.target_score, game_config.max_rounds)
    }

    #[view]
    public fun get_game_state(host_addr: address): (bool, bool, address, u64) acquires GameState {
        let game_state = borrow_global<GameState>(host_addr);
        (
            game_state.game_started,
            game_state.game_ended,
            game_state.host,
            game_state.prize_pool
        )
    }

    #[view]
    public fun get_player_info(host_addr: address, player_index: u64): (address, u64, u64) acquires GameState {
        let game_state = borrow_global<GameState>(host_addr);
        let players_length = vector::length(&game_state.players);
        
        // Check if player_index is within bounds
        assert!(player_index < players_length, EINVALID_PLAYER_INDEX);
        
        let player = vector::borrow(&game_state.players, player_index);
        (player.addr, player.score, player.bet)
    }

    #[view]
    public fun get_current_round(host_addr: address): u64 acquires GameState {
        let game_state = borrow_global<GameState>(host_addr);
        game_state.current_round
    }

    #[view]
    public fun get_current_player(host_addr: address): address acquires GameState {
        let game_state = borrow_global<GameState>(host_addr);
        vector::borrow(&game_state.players, game_state.current_player_index).addr
    }

    public fun get_player_count(game_state: &GameState): u64 {
        vector::length(&game_state.players)
    }

    #[view]
    public fun is_game_ended(host_addr: address): bool acquires GameState {
        let (_, game_ended, _, _) = get_game_state(host_addr);
        game_ended
    }
}