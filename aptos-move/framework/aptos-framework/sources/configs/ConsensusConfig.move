/// Maintains the consensus config for the blockchain. The config is stored in a
/// Reconfiguration, and may be updated by root.
module AptosFramework::ConsensusConfig {
    use std::errors;
    use std::vector;
    use AptosFramework::Reconfiguration;
    use AptosFramework::Timestamp;
    use AptosFramework::SystemAddresses;

    /// Error with config
    const ECONFIG: u64 = 0;

    struct ConsensusConfig has key {
        config: vector<u8>,
    }

    /// Publishes the ConsensusConfig config.
    public fun initialize(account: &signer) {
        Timestamp::assert_genesis();
        SystemAddresses::assert_aptos_framework(account);

        assert!(
            !exists<ConsensusConfig>(@AptosFramework),
            errors::already_published(ECONFIG)
        );
        move_to(account, ConsensusConfig { config: vector::empty() });
    }

    /// Update the config.
    public fun set(account: &signer, config: vector<u8>) acquires ConsensusConfig {
        SystemAddresses::assert_aptos_framework(account);
        let config_ref = &mut borrow_global_mut<ConsensusConfig>(@AptosFramework).config;
        *config_ref = config;
        Reconfiguration::reconfigure();
    }
}
