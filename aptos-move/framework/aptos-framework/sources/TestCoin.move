/// This module defines a minimal and generic Coin and Balance.
/// modified from https://github.com/move-language/move/tree/main/language/documentation/tutorial
module AptosFramework::TestCoin {
    use std::ascii;
    use std::errors;
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};

    use AptosFramework::Coin::{Self, BurnCapability, MintCapability};
    use AptosFramework::SystemAddresses;

    /// Error codes
    const ENO_CAPABILITIES: u64 = 1;
    const EALREADY_DELEGATED: u64 = 2;
    const EDELEGATION_NOT_FOUND: u64 = 3;

    struct TestCoin has key { }

    struct Capabilities has key {
        mint_cap: MintCapability<TestCoin>,
    }

    /// Delegation token created by delegator and can be claimed by the delegatee as MintCapability.
    struct DelegatedMintCapability has store {
        to: address
    }

    /// The container stores the current pending delegations.
    struct Delegations has key {
        inner: vector<DelegatedMintCapability>,
    }

    public fun initialize(
        aptos_framework: &signer,
        core_resource: &signer,
    ): (MintCapability<TestCoin>, BurnCapability<TestCoin>) {
        SystemAddresses::assert_aptos_framework(aptos_framework);

        let (mint_cap, burn_cap) = Coin::initialize<TestCoin>(
            aptos_framework,
            ascii::string(b"Test Coin"),
            ascii::string(b"TC"),
            6, /* decimals */
            false, /* monitor_supply */
        );

        // Aptos framework needs mint cap to mint coins to initial validators.
        move_to(aptos_framework, Capabilities { mint_cap: copy mint_cap });

        // Mint the core resource account TestCoin for gas so it can execute system transactions.
        // TODO: Only do this for testnets.
        Coin::register_internal<TestCoin>(core_resource);
        let coins = Coin::mint<TestCoin>(
            18446744073709551615,
            &mint_cap,
        );
        Coin::deposit<TestCoin>(signer::address_of(core_resource), coins);
        move_to(core_resource, Capabilities { mint_cap: copy mint_cap });
        move_to(core_resource, Delegations { inner: vector::empty() });

        (mint_cap, burn_cap)
    }

    /// Create new test coins and deposit them into dst_addr's account.
    public entry fun mint(
        account: &signer,
        dst_addr: address,
        amount: u64,
    ) acquires Capabilities {
        let account_addr = signer::address_of(account);

        assert!(
            exists<Capabilities>(account_addr),
            errors::not_published(ENO_CAPABILITIES),
        );

        let capabilities = borrow_global<Capabilities>(account_addr);
        let coins_minted = Coin::mint<TestCoin>(amount, &capabilities.mint_cap);
        Coin::deposit<TestCoin>(dst_addr, coins_minted);
    }

    /// Create delegated token for the address so the account could claim MintCapability later.
    public entry fun delegate_mint_capability(account: signer, to: address) acquires Delegations {
        SystemAddresses::assert_core_resource(&account);
        let delegations = &mut borrow_global_mut<Delegations>(@CoreResources).inner;
        let i = 0;
        while (i < vector::length(delegations)) {
            let element = vector::borrow(delegations, i);
            assert!(element.to != to, errors::invalid_argument(EALREADY_DELEGATED));
            i = i + 1;
        };
        vector::push_back(delegations, DelegatedMintCapability { to });
    }

    /// Claim the delegated mint capability and destroy the delegated token.
    public entry fun claim_mint_capability(account: &signer) acquires Delegations, Capabilities {
        let maybe_index = find_delegation(signer::address_of(account));
        assert!(option::is_some(&maybe_index), EDELEGATION_NOT_FOUND);
        let idx = *option::borrow(&maybe_index);
        let delegations = &mut borrow_global_mut<Delegations>(@CoreResources).inner;
        let DelegatedMintCapability { to: _} = vector::swap_remove(delegations, idx);

        // Make a copy of mint cap and give it to the specified account.
        let mint_cap = borrow_global<Capabilities>(@CoreResources).mint_cap;
        move_to(account, Capabilities { mint_cap });
    }

    fun find_delegation(addr: address): Option<u64> acquires Delegations {
        let delegations = &borrow_global<Delegations>(@CoreResources).inner;
        let i = 0;
        let len = vector::length(delegations);
        let index = option::none();
        while (i < len) {
            let element = vector::borrow(delegations, i);
            if (element.to == addr) {
                index = option::some(i);
                break
            };
            i = i + 1;
        };
        index
    }
}
