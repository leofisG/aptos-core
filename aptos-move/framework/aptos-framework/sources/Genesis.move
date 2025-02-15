module AptosFramework::Genesis {
    use std::signer;
    use std::errors;
    use std::event;
    use std::vector;

    use AptosFramework::Account;
    use AptosFramework::AptosGovernance;
    use AptosFramework::Coin;
    use AptosFramework::ConsensusConfig;
    use AptosFramework::TransactionPublishingOption;
    use AptosFramework::Version;
    use AptosFramework::Block;
    use AptosFramework::ChainId;
    use AptosFramework::Reconfiguration;
    use AptosFramework::Stake;
    use AptosFramework::TestCoin::{Self, TestCoin};
    use AptosFramework::Timestamp;
    use AptosFramework::TransactionFee;
    use AptosFramework::VMConfig;

    /// Invalid epoch duration.
    const EINVALID_EPOCH_DURATION: u64 = 1;

    fun initialize(
        core_resource_account: signer,
        core_resource_account_auth_key: vector<u8>,
        initial_script_allow_list: vector<vector<u8>>,
        is_open_module: bool,
        instruction_schedule: vector<u8>,
        native_schedule: vector<u8>,
        chain_id: u8,
        initial_version: u64,
        consensus_config: vector<u8>,
        min_price_per_gas_unit: u64,
        epoch_interval: u64,
        minimum_stake: u64,
        maximum_stake: u64,
        min_lockup_duration_secs: u64,
        max_lockup_duration_secs: u64,
        allow_validator_set_change: bool,
        rewards_rate: u64,
        rewards_rate_denominator: u64,
    ) {
        // This can fail genesis but is necessary so that any misconfigurations can be corrected before genesis succeeds
        assert!(epoch_interval > 0, errors::invalid_argument(EINVALID_EPOCH_DURATION));

        initialize_internal(
            &core_resource_account,
            core_resource_account_auth_key,
            initial_script_allow_list,
            is_open_module,
            instruction_schedule,
            native_schedule,
            chain_id,
            initial_version,
            consensus_config,
            min_price_per_gas_unit,
            epoch_interval,
            minimum_stake,
            maximum_stake,
            min_lockup_duration_secs,
            max_lockup_duration_secs,
            allow_validator_set_change,
            rewards_rate,
            rewards_rate_denominator,
        )
    }

    fun initialize_internal(
        core_resource_account: &signer,
        core_resource_account_auth_key: vector<u8>,
        initial_script_allow_list: vector<vector<u8>>,
        is_open_module: bool,
        instruction_schedule: vector<u8>,
        native_schedule: vector<u8>,
        chain_id: u8,
        initial_version: u64,
        consensus_config: vector<u8>,
        min_price_per_gas_unit: u64,
        epoch_interval: u64,
        minimum_stake: u64,
        maximum_stake: u64,
        min_lockup_duration_secs: u64,
        max_lockup_duration_secs: u64,
        allow_validator_set_change: bool,
        rewards_rate: u64,
        rewards_rate_denominator: u64,
    ) {
        // TODO: Only do create the core resources account in testnets
        Account::create_account_internal(signer::address_of(core_resource_account));
        Account::rotate_authentication_key_internal(core_resource_account, copy core_resource_account_auth_key);

        // Initialize the aptos framework account. This is the account where system resources and modules will be
        // deployed to. This will be entirely managed by on-chain governance and no entities have the key or privileges
        // to use this account.
        let (aptos_framework_account, framework_signer_cap) = Account::create_core_framework_account();

        // Initialize account configs on aptos framework account.
        Account::initialize(
            &aptos_framework_account,
            @AptosFramework,
            b"Account",
            b"script_prologue",
            b"module_prologue",
            b"writeset_prologue",
            b"multi_agent_script_prologue",
            b"epilogue",
            b"writeset_epilogue",
            false,
        );

        // Give the decentralized on-chain governance control over the core framework account.
        AptosGovernance::store_signer_cap(&aptos_framework_account, framework_signer_cap);

        // Consensus config setup
        ConsensusConfig::initialize(&aptos_framework_account);
        Version::initialize(&aptos_framework_account, initial_version);
        Stake::initialize_validator_set(
            &aptos_framework_account,
            minimum_stake,
            maximum_stake,
            min_lockup_duration_secs,
            max_lockup_duration_secs,
            allow_validator_set_change,
            rewards_rate,
            rewards_rate_denominator,
        );

        VMConfig::initialize(
            &aptos_framework_account,
            instruction_schedule,
            native_schedule,
            min_price_per_gas_unit,
        );

        ConsensusConfig::set(&aptos_framework_account, consensus_config);
        TransactionPublishingOption::initialize(&aptos_framework_account, initial_script_allow_list, is_open_module);

        // This is testnet-specific configuration and can be skipped for mainnet.
        // Mainnet can call Coin::initialize<MainnetCoin> directly and give mint capability to the Staking module.
        let (mint_cap, burn_cap) = TestCoin::initialize(&aptos_framework_account, core_resource_account);

        // Give Stake module MintCapability<TestCoin> so it can mint rewards.
        Stake::store_test_coin_mint_cap(&aptos_framework_account, mint_cap);

        // Give TransactionFee BurnCapability<TestCoin> so it can burn gas.
        TransactionFee::store_test_coin_burn_cap(&aptos_framework_account, burn_cap);

        // Pad the event counter for the Root account to match DPN. This
        // _MUST_ match the new epoch event counter otherwise all manner of
        // things start to break.
        event::destroy_handle(event::new_event_handle<u64>(&aptos_framework_account));
        event::destroy_handle(event::new_event_handle<u64>(&aptos_framework_account));

        // This needs to be called at the very end.
        ChainId::initialize(&aptos_framework_account, chain_id);
        Reconfiguration::initialize(&aptos_framework_account);
        Block::initialize_block_metadata(&aptos_framework_account, epoch_interval);
        Timestamp::set_time_has_started(&aptos_framework_account);
    }

    /// Sets up the initial validator set for the network.
    /// The validator "owner" accounts, and their authentication
    /// Addresses (and keys) are encoded in the `owners`
    /// Each validator signs consensus messages with the private key corresponding to the Ed25519
    /// public key in `consensus_pubkeys`.
    /// Finally, each validator must specify the network address
    /// (see types/src/network_address/mod.rs) for itself and its full nodes.
    ///
    /// Network address fields are a vector per account, where each entry is a vector of addresses
    /// encoded in a single BCS byte array.
    public entry fun create_initialize_validators(
        aptos_framework_account: signer,
        owners: vector<address>,
        consensus_pubkeys: vector<vector<u8>>,
        proof_of_possession: vector<vector<u8>>,
        validator_network_addresses: vector<vector<u8>>,
        full_node_network_addresses: vector<vector<u8>>,
        staking_distribution: vector<u64>,
        initial_lockup_timestamp: u64,
    ) {
        let num_owners = vector::length(&owners);
        let num_validator_network_addresses = vector::length(&validator_network_addresses);
        let num_full_node_network_addresses = vector::length(&full_node_network_addresses);
        assert!(num_validator_network_addresses == num_full_node_network_addresses, 0);
        let num_staking = vector::length(&staking_distribution);
        assert!(num_full_node_network_addresses == num_staking, 0);

        let i = 0;
        while (i < num_owners) {
            let owner = vector::borrow(&owners, i);
            // create each validator account and rotate its auth key to the correct value
            let owner_account = Account::create_account_internal(*owner);

            // use the operator account set up the validator config
            let cur_validator_network_addresses = *vector::borrow(&validator_network_addresses, i);
            let cur_full_node_network_addresses = *vector::borrow(&full_node_network_addresses, i);
            let consensus_pubkey = *vector::borrow(&consensus_pubkeys, i);
            let pop = *vector::borrow(&proof_of_possession, i);
            Stake::register_validator_candidate(
                &owner_account,
                consensus_pubkey,
                pop,
                cur_validator_network_addresses,
                cur_full_node_network_addresses,
            );
            Stake::increase_lockup(&owner_account, initial_lockup_timestamp);
            let amount = *vector::borrow(&staking_distribution, i);
            // Transfer coins from the root account to the validator, so they can stake and have non-zero voting power
            // and can complete consensus on the genesis block.
            Coin::register<TestCoin>(&owner_account);
            TestCoin::mint(&aptos_framework_account, *owner, amount);
            Stake::add_stake(&owner_account, amount);
            Stake::join_validator_set_internal(&owner_account, *owner);

            i = i + 1;
        };
        Stake::on_new_epoch();
    }

    #[test_only]
    public fun setup(core_resource_account: &signer) {
        initialize_internal(
            core_resource_account,
            x"0000000000000000000000000000000000000000000000000000000000000000",
            vector::empty(),
            true,
            x"", // instruction_schedule not needed for unit tests
            x"", // native schedule not needed for unit tests
            4u8, // TESTING chain ID
            0,
            x"",
            1,
            1,
            0,
            1,
            0,
            1,
            true,
            1,
            1,
        )
    }

    #[test(account = @CoreResources)]
    fun test_setup(account: signer) {
        use AptosFramework::Account;

        setup(&account);
        assert!(Account::exists_at(@AptosFramework), 0);
        assert!(Account::exists_at(@CoreResources), 0);
    }
}
