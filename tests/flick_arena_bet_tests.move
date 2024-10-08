#[test_only]
module flick_arena_bet::game_tests {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use flick_arena_bet::game;

    #[test(host = @0x1, player1 = @0x2, player2 = @0x3, aptos_framework = @aptos_framework)]
    public entry fun test_game_flow(
        host: signer,
        player1: signer,
        player2: signer,
        aptos_framework: signer
    ) {
        // Setup
        let (
            host_addr,
            player1_addr,
            player2_addr,
            burn_cap,
            mint_cap
        ) = setup_accounts_and_coin(
            &host,
            &player1,
            &player2,
            &aptos_framework
        );

        // Initialize game
        let target_score = 101;
        let max_round = 10;
        game::initialize(&host, target_score, max_round);

        // Register and bet
        let bet_amount = 100000000;
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount);

        // Simulate game play
        let game_ended = false;
        let turn = 0;
        while (!game_ended) {
            let current_player_addr = if (turn % 2 == 0) player1_addr else player2_addr;

            // Determine scores for this turn
            let (throw1, throw2, throw3) = if (turn % 2 == 0) {
                // Player 1's turns
                if (turn == 0) (60, 20, 21) else (0, 0, 0) // shouldn't reach here
            } else {
                // Player 2's turns
                if (turn == 1) (20, 20, 40) else (20, 20, 1) // shouldn't reach here
            };

            // Execute the three throws
            game::flick_dart(&host, current_player_addr, throw1);
            game::flick_dart(&host, current_player_addr, throw2);
            game::flick_dart(&host, current_player_addr, throw3);

            let (_, player1_score, _) = game::get_player_info(host_addr, 0);
            let (_, player2_score, _) = game::get_player_info(host_addr, 1);

            if (player1_score == 0 || player2_score == 0) {
                game_ended = true;
            };

            turn = turn + 1;
        };

        // Determine the winner
        let (_, player1_final_score, _) = game::get_player_info(host_addr, 0);
        let winner_addr = if (player1_final_score == 0) player1_addr else player2_addr;

        // Verify game state
        let (_, game_ended, _, _) = game::get_game_state(host_addr);
        assert!(game_ended, 1);

        // Verify balances
        let winner_balance = coin::balance<AptosCoin>(winner_addr);
        let loser_addr = if (winner_addr == player1_addr) player2_addr else player1_addr;
        let loser_balance = coin::balance<AptosCoin>(loser_addr);
        let host_balance = coin::balance<AptosCoin>(host_addr);

        let initial_balance = 1000000000;
        // Winner should have their initial balance plus the bet amount (minus any fees)
        assert!(winner_balance > initial_balance, 2);
        // Loser should have their initial balance minus the bet amount
        assert!(
            loser_balance == initial_balance - bet_amount,
            3
        );
        // Host should have received a fee
        assert!(host_balance > initial_balance, 4);

        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(host = @0x1, player1 = @0x2, player2 = @0x3, aptos_framework = @aptos_framework)]
    public entry fun test_game_draw(
        host: signer,
        player1: signer,
        player2: signer,
        aptos_framework: signer
    ) {
        // Setup
        let (
            host_addr,
            player1_addr,
            player2_addr,
            burn_cap,
            mint_cap
        ) = setup_accounts_and_coin(
            &host,
            &player1,
            &player2,
            &aptos_framework
        );

        // Initialize game
        let target_score = 101;
        game::initialize(&host, target_score, 1);

        // Register and bet
        let bet_amount = 100000000;
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount);

        // Simulate a draw scenario (both players reach zero in the same round)
        game::flick_dart(&host, player1_addr, 51);
        game::flick_dart(&host, player1_addr, 49);
        game::flick_dart(&host, player1_addr, 0);
        game::flick_dart(&host, player2_addr, 51);
        game::flick_dart(&host, player2_addr, 49);
        game::flick_dart(&host, player2_addr, 0);

        // Verify final scores
        let (_, player1_score, _) = game::get_player_info(host_addr, 0);
        let (_, player2_score, _) = game::get_player_info(host_addr, 1);
        assert!(
            player1_score == 1 && player2_score == 1,
            0
        );

        // Verify game state
        let (_, game_ended, _, _) = game::get_game_state(host_addr);
        assert!(game_ended, 1);

        // Verify balances (assuming bets are returned in case of a draw)
        let initial_balance = 1000000000;
        assert!(
            coin::balance<AptosCoin>(player1_addr) == initial_balance,
            3
        );
        assert!(
            coin::balance<AptosCoin>(player2_addr) == initial_balance,
            4
        );

        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(host = @0x1, player1 = @0x2, player2 = @0x3, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 9)]
    public entry fun test_game_order(
        host: signer,
        player1: signer,
        player2: signer,
        aptos_framework: signer
    ) {
        // Setup
        let (
            host_addr,
            player1_addr,
            player2_addr,
            burn_cap,
            mint_cap
        ) = setup_accounts_and_coin(
            &host,
            &player1,
            &player2,
            &aptos_framework
        );

        // Initialize game
        let target_score = 101;
        game::initialize(&host, target_score, 1);

        // Register and bet
        let bet_amount = 100000000;
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount);

        // Simulate a draw scenario (both players reach zero in the same round)
        game::flick_dart(&host, player1_addr, 51);
        game::flick_dart(&host, player2_addr, 51);

        // Verify final scores
        let (_, player1_score, _) = game::get_player_info(host_addr, 0);
        let (_, player2_score, _) = game::get_player_info(host_addr, 1);
        assert!(
            player1_score == 1 && player2_score == 1,
            0
        );

        // Verify game state
        let (_, game_ended, _, _) = game::get_game_state(host_addr);
        assert!(game_ended, 1);

        // Verify balances (assuming bets are returned in case of a draw)
        let initial_balance = 1000000000;
        assert!(
            coin::balance<AptosCoin>(player1_addr) == initial_balance,
            3
        );
        assert!(
            coin::balance<AptosCoin>(player2_addr) == initial_balance,
            4
        );

        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(host = @0x1, player1 = @0x2, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 5)]
    public entry fun test_start_game_with_one_player(
        host: signer,
        player1: signer,
        aptos_framework: signer
    ) {
        let (
            host_addr,
            player1_addr,
            _,
            burn_cap,
            mint_cap
        ) = setup_accounts_and_coin(
            &host,
            &player1,
            &player1,
            &aptos_framework
        );

        // Initialize the game
        game::initialize(&host, 100, 2);

        // Register player1
        game::register_and_bet(&player1, host_addr, 100);

        // Get game state
        let (
            is_game_started,
            is_game_ended,
            _,
            prize_pool
        ) = flick_arena_bet::game::get_game_state(host_addr);

        // Assert game state
        assert!(!is_game_started, 0);
        assert!(!is_game_ended, 1);

        // Attempt to flick dart (this should fail because the game hasn't started)
        game::flick_dart(&host, player1_addr, 20);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(host = @0x1, player1 = @0x2, player2 = @0x3, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 11)]
    // Assuming error code 5 is for insufficient funds
    public entry fun test_insufficient_funds(
        host: signer,
        player1: signer,
        player2: signer,
        aptos_framework: signer
    ) {
        let (
            host_addr,
            player1_addr,
            _,
            burn_cap,
            mint_cap
        ) = setup_accounts_and_coin(
            &host,
            &player1,
            &player2,
            &aptos_framework
        );

        // Initialize game
        game::initialize(&host, 501, 20);

        // Try to bet with more funds than available
        let bet_amount = 1000000000; // More than the initial balance
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount - 1);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(host = @0x1, player1 = @0x2, player2 = @0x3, player3 = @0x4, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 2)] // Assuming error code 6 is for game already started
    public entry fun test_max_players_reached(host: signer, player1: signer, player2: signer, player3: signer, aptos_framework: signer) {
        let (host_addr, player1_addr, player2_addr, burn_cap, mint_cap) = setup_accounts_and_coin(&host, &player1, &player2, &aptos_framework);
        let player3_addr = signer::address_of(&player3);
        account::create_account_for_test(player3_addr);
        coin::register<AptosCoin>(&player3);

        // Initialize game
        game::initialize(&host, 501, 20);

        // Register two players (assuming the max is 2)
        let bet_amount = 100000000;
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount);

        // Try to register a third player
        game::register_and_bet(&player3, host_addr, bet_amount);

        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(host = @0x1, player1 = @0x2, player2 = @0x3, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 12)] // EGAME_NOT_ENDED
    public entry fun test_reset_game_failed(
        host: signer,
        player1: signer,
        player2: signer,
        aptos_framework: signer
    ) {
        // Setup
        let (
            host_addr,
            player1_addr,
            player2_addr,
            burn_cap,
            mint_cap
        ) = setup_accounts_and_coin(
            &host,
            &player1,
            &player2,
            &aptos_framework
        );

        // Initialize game
        let target_score = 101;
        let max_round = 10;
        game::initialize(&host, target_score, max_round);

        // Register and bet
        let bet_amount = 100000000;
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount);

        // Play a few rounds
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player2_addr, 30);
        game::flick_dart(&host, player2_addr, 30);
        game::flick_dart(&host, player2_addr, 30);

        // Verify game state before reset
        let (is_started, is_ended, host_address, _) = game::get_game_state(host_addr);
        assert!(is_started, 1);
        assert!(!is_ended, 2);
        assert!(host_address == host_addr, 3);

        // Reset the game
        game::initialize(&host, target_score, max_round);

        // // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(host = @0x1, player1 = @0x2, player2 = @0x3, aptos_framework = @aptos_framework)]
    public entry fun test_reset_game(
        host: signer,
        player1: signer,
        player2: signer,
        aptos_framework: signer
    ) {
        // Setup
        let (
            host_addr,
            player1_addr,
            player2_addr,
            burn_cap,
            mint_cap
        ) = setup_accounts_and_coin(
            &host,
            &player1,
            &player2,
            &aptos_framework
        );

        // Initialize game
        let target_score = 101;
        let max_round = 10;
        game::initialize(&host, target_score, max_round);

        // Register and bet
        let bet_amount = 50000000;
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount);

        // Play a few rounds
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player2_addr, 30);
        game::flick_dart(&host, player2_addr, 30);
        game::flick_dart(&host, player2_addr, 30);
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player1_addr, 20);
        game::flick_dart(&host, player1_addr, 1);

        // Verify game state before reset
        let (is_started, is_ended, host_address, prize_pool) = game::get_game_state(host_addr);
        assert!(is_started, 1);
        assert!(is_ended, 2);
        assert!(host_address == host_addr, 3);
        assert!(prize_pool == 2 * bet_amount, 4);

        // Reset the game
        game::initialize(&host, target_score + 1, max_round + 1);

        // Verify game state after reset
        let (is_started, is_ended, host_address, prize_pool) = game::get_game_state(host_addr);
        assert!(!is_started, 5);
        assert!(!is_ended, 6);
        assert!(host_address == host_addr, 7);
        assert!(prize_pool == 0, 8);

        let bet_amount = 30000000;
        game::register_and_bet(&player1, host_addr, bet_amount);
        game::register_and_bet(&player2, host_addr, bet_amount);

        // Verify game state after reset
        let (is_started, is_ended, host_address, prize_pool) = game::get_game_state(host_addr);
        assert!(is_started, 9);
        assert!(!is_ended, 10);
        assert!(host_address == host_addr, 11);
        assert!(prize_pool == 2 * bet_amount, 12);

        // Verify player info is reset
        let (player_address, score, bet) = game::get_player_info(host_addr, 0);
        assert!(player_address == player1_addr, 13);
        assert!(score == target_score + 1, 14);
        assert!(bet == bet_amount, 15);

        let (player_address, score, bet) = game::get_player_info(host_addr, 1);
        assert!(player_address == player2_addr, 16);
        assert!(score == target_score + 1, 17);
        assert!(bet == bet_amount, 18);

        // Verify game config is maintained
        let (stored_target_score, stored_max_round) = game::get_game_config(host_addr);
        assert!(stored_target_score == target_score + 1, 19);
        assert!(stored_max_round == max_round + 1, 20);

        game::flick_dart(&host, player1_addr, 20);

        let (player_address, score, bet) = game::get_player_info(host_addr, 0);
        assert!(player_address == player1_addr, 21);
        assert!(score == target_score + 1 - 20, 22);
        assert!(bet == bet_amount, 23);


        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    // Helper function to set up accounts and coin
    fun setup_accounts_and_coin(
        host: &signer,
        player1: &signer,
        player2: &signer,
        aptos_framework: &signer
    ): (
        address,
        address,
        address,
        coin::BurnCapability<AptosCoin>,
        coin::MintCapability<AptosCoin>
    ) {
        let host_addr = signer::address_of(host);
        let player1_addr = signer::address_of(player1);
        let player2_addr = signer::address_of(player2);

        account::create_account_for_test(host_addr);
        account::create_account_for_test(player1_addr);
        account::create_account_for_test(player2_addr);

        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(
            aptos_framework
        );

        let initial_balance = 1000000000;
        coin::register<AptosCoin>(host);
        coin::register<AptosCoin>(player1);
        coin::register<AptosCoin>(player2);

        coin::deposit(
            host_addr,
            coin::mint<AptosCoin>(initial_balance, &mint_cap)
        );
        coin::deposit(
            player1_addr,
            coin::mint<AptosCoin>(initial_balance, &mint_cap)
        );
        coin::deposit(
            player2_addr,
            coin::mint<AptosCoin>(initial_balance, &mint_cap)
        );

        (
            host_addr,
            player1_addr,
            player2_addr,
            burn_cap,
            mint_cap
        )
    }

}