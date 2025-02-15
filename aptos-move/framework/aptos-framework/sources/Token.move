/// This module provides the foundation for Tokens.
module AptosFramework::Token {
    use std::ascii;
    use std::errors;
    use std::event::{Self, EventHandle};
    use std::option::{Self, Option};
    use std::signer;

    use AptosFramework::Table::{Self, Table};
    const ROYALTY_POINTS_DENOMINATOR: u64 = 1000000;

    const EALREADY_HAS_BALANCE: u64 = 0;
    const EBALANCE_NOT_PUBLISHED: u64 = 1;
    const ECOLLECTIONS_NOT_PUBLISHED: u64 = 2;
    const ECOLLECTION_NOT_PUBLISHED: u64 = 3;
    const ECOLLECTION_ALREADY_EXISTS: u64 = 4;
    const ECREATE_WOULD_EXCEED_MAXIMUM: u64 = 5;
    const EINSUFFICIENT_BALANCE: u64 = 6;
    const EINVALID_COLLECTION_NAME: u64 = 7;
    const EINVALID_TOKEN_MERGE: u64 = 8;
    const EMINT_WOULD_EXCEED_MAXIMUM: u64 = 9;
    const ENO_BURN_CAPABILITY: u64 = 10;
    const ENO_MINT_CAPABILITY: u64 = 11;
    const ETOKEN_ALREADY_EXISTS: u64 = 12;
    const ETOKEN_NOT_PUBLISHED: u64 = 13;
    const ETOKEN_STORE_NOT_PUBLISHED: u64 = 14;
    const ETOKEN_SPLIT_AMOUNT_LARGER_THEN_TOKEN_AMOUNT: u64 = 15;

    //
    // Core data structures for holding tokens
    //

    /// Represents ownership of a the data associated with this Token
    struct Token has store {
        id: TokenId,
        value: u64,
    }


    /// Represents a unique identity for the token
    struct TokenId has copy, drop, store {
        // The creator of this token
        creator: address,
        // The collection or set of related tokens within the creator's account
        collection: ascii::String,
        // Unique name within a collection within the creator's account
        name: ascii::String,
    }

    /// Represents token resources owned by token owner
    struct TokenStore has key {
        tokens: Table<TokenId, Token>,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
    }

    /// Set of data sent to the event stream during a receive
    struct DepositEvent has drop, store {
        id: TokenId,
        amount: u64,
    }

    /// Set of data sent to the event stream during a withdrawal
    struct WithdrawEvent has drop, store {
        id: TokenId,
        amount: u64,
    }

    /// create collection event with creator address and collection name
    struct CreateCollectionEvent has drop, store {
        creator: address,
        collection_name: ascii::String,
        uri: ascii::String,
        description: ascii::String,
        maximum: Option<u64>,
    }

    /// token creation event id of token created
    struct CreateTokenEvent has drop, store {
        id: TokenId,
        token_data: TokenData,
        initial_balance: u64,
    }

    /// mint token event. This event triggered when creator adds more supply to existing token
    struct MintTokenEvent has drop, store {
        id: TokenId,
        amount: u64,
    }

    //
    // Core data structures for creating and maintaining tokens
    //

    /// Represent collection and token metadata for a creator
    struct Collections has key {
        collections: Table<ascii::String, Collection>,
        token_data: Table<TokenId, TokenData>,
        burn_capabilities: Table<TokenId, BurnCapability>,
        mint_capabilities: Table<TokenId, MintCapability>,
        create_collection_events: EventHandle<CreateCollectionEvent>,
        create_token_events: EventHandle<CreateTokenEvent>,
        mint_token_events: EventHandle<MintTokenEvent>,
    }

    /// Represent the collection metadata
    struct Collection has store {
        // Describes the collection
        description: ascii::String,
        // Unique name within this creators account for this collection
        name: ascii::String,
        // URL for additional information /media
        uri: ascii::String,
        // Total number of distinct Tokens tracked by the collection
        count: u64,
        // Optional maximum number of tokens allowed within this collections
        maximum: Option<u64>,
    }

    /// The royalty of a token
    struct Royalty has copy, drop, store {
        // The basis point and denominator is ROYAL_BASIS_POINT_DENOMINATOR (1,000,000)
        royalty_points_per_million: u64,
        // if the token is jointly owned by multiple creators,
        // the group of creators should create a shared account.
        // the creator_account will be the shared account address.
        creator_account: address,
    }

    /// The data associated with the Tokens
    struct TokenData has copy, drop, store {
        // Unique name within this creators account for this Token's collection
        collection: ascii::String,
        // Describes this Token
        description: ascii::String,
        // The name of this Token
        name: ascii::String,
        // Optional maximum number of this type of Token.
        maximum: Option<u64>,
        // Total number of this type of Token
        supply: Option<u64>,
        // URL for additional information / media
        uri: ascii::String,
        // the royalty of the token
        royalty: Royalty,
    }

    /// Capability required to mint tokens.
    struct MintCapability has store {
        token_id: TokenId,
    }

    /// Capability required to burn tokens.
    struct BurnCapability has store {
        token_id: TokenId,
    }

    //
    // Creator Script functions
    //

    public entry fun create_limited_collection_script(
        creator: &signer,
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>,
        maximum: u64,
    ) acquires Collections {
        create_collection(
            creator,
            ascii::string(name),
            ascii::string(description),
            ascii::string(uri),
            option::some(maximum),
        );
    }

    public entry fun create_unlimited_collection_script(
        creator: &signer,
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>,
    ) acquires Collections {
        create_collection(
            creator,
            ascii::string(name),
            ascii::string(description),
            ascii::string(uri),
            option::none(),
        );
    }

    public entry fun create_limited_token_script(
        creator: &signer,
        collection: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        monitor_supply: bool,
        initial_balance: u64,
        maximum: u64,
        uri: vector<u8>,
        royalty_points_per_million: u64
    ) acquires Collections, TokenStore {
        create_token(
            creator,
            ascii::string(collection),
            ascii::string(name),
            ascii::string(description),
            monitor_supply,
            initial_balance,
            option::some(maximum),
            ascii::string(uri),
            royalty_points_per_million
        );
    }

    public entry fun create_unlimited_token_script(
        creator: &signer,
        collection: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        monitor_supply: bool,
        initial_balance: u64,
        uri: vector<u8>,
        royalty_points_per_million: u64
    ) acquires Collections, TokenStore {
        create_token(
            creator,
            ascii::string(collection),
            ascii::string(name),
            ascii::string(description),
            monitor_supply,
            initial_balance,
            option::none(),
            ascii::string(uri),
            royalty_points_per_million,
        );
    }

    //
    // Transaction Script functions
    //

    public entry fun direct_transfer_script(
        sender: &signer,
        receiver: &signer,
        creators_address: address,
        collection: vector<u8>,
        name: vector<u8>,
        amount: u64,
    ) acquires TokenStore {
        let token_id = create_token_id_raw(creators_address, collection, name);
        direct_transfer(sender, receiver, token_id, amount);
    }

    public entry fun initialize_token_script(account: &signer) {
        initialize_token_store(account);
    }

    public entry fun initialize_token_for_id(
        account: &signer,
        creators_address: address,
        collection: vector<u8>,
        name: vector<u8>,
    ) acquires TokenStore {
        let token_id = create_token_id_raw(creators_address, collection, name);
        initialize_token(account, token_id);
    }

    //
    // Public functions for holding tokens
    //

    /// Deposit the token balance into the owner's account and emit an event.
    public fun deposit_token(
        account: &signer,
        token: Token,
    ) acquires TokenStore {
        let account_addr = signer::address_of(account);
        initialize_token_store(account);
        let tokens = &mut borrow_global_mut<TokenStore>(account_addr).tokens;
        if (!Table::contains(tokens, token.id)) {
            initialize_token(account, token.id);
        };

        direct_deposit(account_addr, token)
    }

    /// Deposit the token balance into the recipients account and emit an event.
    public fun direct_deposit(account_addr: address, token: Token) acquires TokenStore {
        let token_store = borrow_global_mut<TokenStore>(account_addr);

        event::emit_event<DepositEvent>(
            &mut token_store.deposit_events,
            DepositEvent { id: token.id, amount: token.value },
        );

        direct_deposit_without_event(account_addr, token);
    }

    /// Deposit the token balance into the recipients account without emitting an event.
    public fun direct_deposit_without_event(account_addr: address, token: Token) acquires TokenStore {
        assert!(
            exists<TokenStore>(account_addr),
            errors::not_published(ETOKEN_STORE_NOT_PUBLISHED),
        );
        let token_store = borrow_global_mut<TokenStore>(account_addr);

        assert!(
            Table::contains(&token_store.tokens, token.id),
            errors::not_published(EBALANCE_NOT_PUBLISHED),
        );
        let recipient_token = Table::borrow_mut(&mut token_store.tokens, token.id);

        merge(recipient_token, token);
    }

    public fun direct_transfer(
        sender: &signer,
        receiver: &signer,
        token_id: TokenId,
        amount: u64,
    ) acquires TokenStore {
        let token = withdraw_token(sender, token_id, amount);
        deposit_token(receiver, token)
    }

    public fun initialize_token(account: &signer, token_id: TokenId) acquires TokenStore {
        let account_addr = signer::address_of(account);
        assert!(
            exists<TokenStore>(account_addr),
            errors::not_published(ETOKEN_STORE_NOT_PUBLISHED),
        );
        let tokens = &mut borrow_global_mut<TokenStore>(account_addr).tokens;

        assert!(
            !Table::contains(tokens, token_id),
            errors::already_published(EALREADY_HAS_BALANCE),
        );
        Table::add(tokens, token_id, Token { value : 0, id: token_id });
    }

    public fun initialize_token_store(account: &signer) {
        if (!exists<TokenStore>(signer::address_of(account))) {
            move_to(
                account,
                TokenStore {
                    tokens: Table::new(),
                    deposit_events: event::new_event_handle<DepositEvent>(account),
                    withdraw_events: event::new_event_handle<WithdrawEvent>(account),
                },
            );
        }
    }

    public fun merge(dst_token: &mut Token, source_token: Token) {
        assert!(&dst_token.id == &source_token.id, errors::invalid_argument(EINVALID_TOKEN_MERGE));
        dst_token.value = dst_token.value + source_token.value;
        let Token { id: _, value: _ } = source_token;
    }

    public fun split(dst_token: &mut Token, amount: u64): Token {
        assert!(dst_token.value >= amount, ETOKEN_SPLIT_AMOUNT_LARGER_THEN_TOKEN_AMOUNT);
        dst_token.value = dst_token.value - amount;
        Token {
            id: dst_token.id,
            value: amount
        }
    }

    public fun get_token_value(token: &Token): u64 {
        token.value
    }

    public fun token_id(token: &Token): &TokenId {
        &token.id
    }

    /// Transfers `amount` of tokens from `from` to `to`.
    public fun transfer(
        from: &signer,
        id: TokenId,
        to: address,
        amount: u64,
    ) acquires TokenStore {
        let token = withdraw_token(from, id ,amount);
        direct_deposit(to, token);
    }

    public fun withdraw_token(
        account: &signer,
        id: TokenId,
        amount: u64,
    ): Token acquires TokenStore {
        let account_addr = signer::address_of(account);
        let token_store = borrow_global_mut<TokenStore>(account_addr);
        event::emit_event<WithdrawEvent>(
            &mut token_store.withdraw_events,
            WithdrawEvent { id, amount },
        );
        withdraw_without_event_internal(account_addr, id, amount)
    }

    fun withdraw_without_event_internal(
        account_addr: address,
        id: TokenId,
        amount: u64
    ): Token acquires TokenStore {
        assert!(
            exists<TokenStore>(account_addr),
            errors::not_published(ETOKEN_STORE_NOT_PUBLISHED),
        );
        let tokens = &mut borrow_global_mut<TokenStore>(account_addr).tokens;

        assert!(
            Table::contains(tokens, id),
            errors::not_published(EBALANCE_NOT_PUBLISHED),
        );
        let balance = &mut Table::borrow_mut(tokens, id).value;
        *balance = *balance - amount;

        Token { id, value: amount }
    }

    //
    // Public functions for creating and maintaining tokens
    //

    /// Burn token with capability.
    public fun burn(
        account: &signer,
        token: Token,
    ) acquires Collections {
        let account_addr = signer::address_of(account);
        assert!(
            exists<Collections>(account_addr),
            errors::not_published(ECOLLECTIONS_NOT_PUBLISHED),
        );
        let collections = borrow_global_mut<Collections>(account_addr);

        assert!(
            Table::contains(&collections.token_data, token.id),
            errors::not_published(ETOKEN_NOT_PUBLISHED),
        );

        assert!(
            Table::contains(&collections.burn_capabilities, token.id),
            errors::requires_capability(ENO_BURN_CAPABILITY),
        );
        let _cap = Table::borrow(&collections.burn_capabilities, token.id);

        let token_data = Table::borrow_mut(&mut collections.token_data, token.id);

        if (option::is_some(&token_data.supply)) {
            let supply = option::borrow_mut(&mut token_data.supply);
            *supply = *supply - token.value;
        };

        let Token { id: _, value: _ } = token;
    }

    /// Create a new collection to hold tokens
    public fun create_collection(
        creator: &signer,
        name: ascii::String,
        description: ascii::String,
        uri: ascii::String,
        maximum: Option<u64>,
    ) acquires Collections {
        let account_addr = signer::address_of(creator);
        if (!exists<Collections>(account_addr)) {
            move_to(
                creator,
                Collections {
                    collections: Table::new(),
                    token_data: Table::new(),
                    burn_capabilities: Table::new(),
                    mint_capabilities: Table::new(),
                    create_collection_events:  event::new_event_handle<CreateCollectionEvent>(creator),
                    create_token_events: event::new_event_handle<CreateTokenEvent>(creator),
                    mint_token_events: event::new_event_handle<MintTokenEvent>(creator),
                },
            )
        };

        let collections = &mut borrow_global_mut<Collections>(account_addr).collections;

        assert!(
            !Table::contains(collections, name),
            errors::already_published(ECOLLECTION_ALREADY_EXISTS),
        );

        let collection = Collection {
            description,
            name: *&name,
            uri,
            count: 0,
            maximum,
        };

        Table::add(collections, name, collection);
        let collection_handle =  borrow_global_mut<Collections>(account_addr);
        event::emit_event<CreateCollectionEvent>(
            &mut collection_handle.create_collection_events,
            CreateCollectionEvent {
                creator: account_addr,
                collection_name: *&name,
                uri,
                description,
                maximum
            }
        );
    }

    public fun create_token(
        account: &signer,
        collection: ascii::String,
        name: ascii::String,
        description: ascii::String,
        monitor_supply: bool,
        initial_balance: u64,
        maximum: Option<u64>,
        uri: ascii::String,
        royalty_points_per_million: u64
    ): TokenId acquires Collections, TokenStore {
        let account_addr = signer::address_of(account);
        assert!(
            exists<Collections>(account_addr),
            errors::not_published(ECOLLECTIONS_NOT_PUBLISHED),
        );
        let collections = borrow_global_mut<Collections>(account_addr);

        let token_id = create_token_id(account_addr, collection, name);

        assert!(
            Table::contains(&collections.collections, token_id.collection),
            errors::already_published(ECOLLECTION_NOT_PUBLISHED),
        );
        assert!(
            !Table::contains(&collections.token_data, token_id),
            errors::already_published(ETOKEN_ALREADY_EXISTS),
        );

        let collection = Table::borrow_mut(&mut collections.collections, token_id.collection);
        collection.count = collection.count + 1;
        if (option::is_some(&collection.maximum)) {
            assert!(
                *option::borrow(&collection.maximum) >= collection.count,
                ECREATE_WOULD_EXCEED_MAXIMUM,
            );
        };

        let supply = if (monitor_supply) { option::some(0) } else { option::none() };

        let token_data = TokenData {
            collection: *&token_id.collection,
            description,
            name: *&token_id.name,
            maximum,
            supply,
            uri,
            royalty: Royalty {
                royalty_points_per_million,
                creator_account: signer::address_of(account)
            }
        };
        Table::add(&mut collections.token_data, token_id, token_data);
        Table::add(
            &mut collections.burn_capabilities,
            token_id,
            BurnCapability { token_id },
        );
        Table::add(
            &mut collections.mint_capabilities,
            token_id,
            MintCapability { token_id },
        );

        if (initial_balance > 0) {
            initialize_token_store(account);
            initialize_token(account, token_id);
            mint(account, signer::address_of(account), token_id, initial_balance);
        };

        let token_handle =  borrow_global_mut<Collections>(account_addr);
        event::emit_event<CreateTokenEvent>(
            &mut token_handle.create_token_events,
            CreateTokenEvent {
                id: token_id,
                token_data,
                initial_balance,
            }
        );

        token_id
    }

    public fun create_token_id(
        creator: address,
        collection: ascii::String,
        name: ascii::String,
    ): TokenId {
        TokenId { creator, collection, name }
    }

    public fun create_token_id_raw(
        creator: address,
        collection: vector<u8>,
        name: vector<u8>,
    ): TokenId {
        TokenId {
            creator,
            collection: ascii::string(collection),
            name: ascii::string(name),
        }
    }

    /// Create new tokens and deposit them into dst_addr's account.
    public fun mint(
        account: &signer,
        dst_addr: address,
        token_id: TokenId,
        amount: u64,
    ) acquires Collections, TokenStore {
        assert!(
            exists<Collections>(token_id.creator),
            errors::not_published(ECOLLECTIONS_NOT_PUBLISHED),
        );
        let minter_collections = borrow_global_mut<Collections>(signer::address_of(account));

        assert!(
            Table::contains(&minter_collections.mint_capabilities, token_id),
            errors::requires_capability(ENO_MINT_CAPABILITY),
        );
        let _cap = Table::borrow(&minter_collections.mint_capabilities, token_id);

        assert!(
            exists<Collections>(token_id.creator),
            errors::not_published(ECOLLECTIONS_NOT_PUBLISHED),
        );
        let creator_collections = borrow_global_mut<Collections>(token_id.creator);

        assert!(
            Table::contains(&creator_collections.token_data, token_id),
            errors::not_published(ETOKEN_NOT_PUBLISHED),
        );
        let token_data = Table::borrow_mut(&mut creator_collections.token_data, token_id);

        if (option::is_some(&token_data.supply)) {
            let supply = option::borrow_mut(&mut token_data.supply);
            *supply = *supply + amount;
            if (option::is_some(&token_data.maximum)) {
                let maximum = option::borrow_mut(&mut token_data.maximum);
                assert!(*supply <= *maximum, EMINT_WOULD_EXCEED_MAXIMUM);
            };
        };

        direct_deposit(dst_addr, Token { id: token_id, value: amount });
    }

    public fun balance_of(owner: address, id: TokenId): u64 acquires  TokenStore {
        let token_store = borrow_global<TokenStore>(owner);
        if (Table::contains(&token_store.tokens, id)) {
            Table::borrow(&token_store.tokens, id).value
        } else {
            0
        }
    }

    // ****************** TEST-ONLY FUNCTIONS **************

    #[test(creator = @0x1, owner = @0x2)]
    public fun create_withdraw_deposit_token(
        creator: signer,
        owner: signer,
    ) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 1, 1, 1);

        let token = withdraw_token(&creator, token_id, 1);
        deposit_token(&owner, token);
    }

    #[test(creator = @0x1, owner = @0x2)]
    public fun create_withdraw_deposit_editions(
        creator: signer,
        owner: signer,
    ) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 2, 5, 5);

        let token_0 = withdraw_token(&creator, token_id, 1);
        let token_1 = withdraw_token(&creator, token_id, 1);
        deposit_token(&owner, token_0);
        deposit_token(&creator, token_1);
        let token_2 = withdraw_token(&creator, token_id, 1);
        deposit_token(&owner, token_2);
    }

    #[test(creator = @0x1)]
    #[expected_failure] // (abort_code = 9)]
    public fun test_token_maximum(creator: signer) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 2, 2, 1);
        mint(&creator, signer::address_of(&creator), token_id, 1);
    }

    #[test(creator = @0x1)]
    #[expected_failure] // (abort_code = 5)]
    public fun test_collection_maximum(creator: signer) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 2, 2, 1);
        create_token(
            &creator,
            token_id.collection,
            ascii::string(b"Token"),
            ascii::string(b"Hello, Token"),
            true,
            2,
            option::some(100),
            ascii::string(b"https://aptos.dev"),
            0,
        );

    }

    #[test(creator = @0x1, owner = @0x2)]
    public entry fun direct_transfer_test(
        creator: signer,
        owner: signer,
    ) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 2, 2, 2);
        direct_transfer(&creator, &owner, token_id, 1);
        let token = withdraw_token(&owner, token_id, 1);
        deposit_token(&creator, token);
    }

    #[test_only]
    public fun create_collection_and_token(
        creator: &signer,
        amount: u64,
        collection_max: u64,
        token_max: u64,
    ): TokenId acquires Collections, TokenStore {
        let collection_name = ascii::string(b"Hello, World");

        create_collection(
            creator,
            *&collection_name,
            ascii::string(b"Collection: Hello, World"),
            ascii::string(b"https://aptos.dev"),
            option::some(collection_max),
        );

        create_token(
            creator,
            *&collection_name,
            ascii::string(b"Token: Hello, Token"),
            ascii::string(b"Hello, Token"),
            true,
            amount,
            option::some(token_max),
            ascii::string(b"https://aptos.dev"),
           0,
        )
    }

    #[test(creator = @0xFF)]
    fun test_create_events_generation(creator: signer) acquires Collections, TokenStore {
        create_collection_and_token(&creator, 1, 2, 1);
        let collections = borrow_global<Collections>(signer::address_of(&creator));
        assert!(event::get_event_handle_counter(&collections.create_collection_events) == 1, 1);
        assert!(event::get_event_handle_counter(&collections.create_token_events) == 1, 1);
    }
}
