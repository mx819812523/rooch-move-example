module red_envelope::red_envelope {
    use std::option;
    use std::string::String;
    use std::vector;
    use moveos_std::event::emit;
    use moveos_std::type_info;
    use rooch_framework::transaction;
    use rooch_framework::transaction::TransactionSequenceInfo;
    use moveos_std::table;
    use moveos_std::table::Table;
    use bitcoin_move::types;
    use moveos_std::timestamp;
    use bitcoin_move::types::Header;
    use bitcoin_move::bitcoin;
    use moveos_std::tx_context;
    use moveos_std::bcs;
    use moveos_std::hash;
    use rooch_framework::account_coin_store;
    use moveos_std::timestamp::now_milliseconds;
    use moveos_std::object;
    use rooch_framework::coin_store;
    use moveos_std::tx_context::sender;
    use moveos_std::table_vec;
    use moveos_std::account;
    use moveos_std::object::{ObjectID, new, Object, to_shared, transfer};
    use moveos_std::table_vec::TableVec;
    use rooch_framework::coin_store::CoinStore;

    const U64MAX: u64 = 18446744073709551615;
    const DEPLOYER: address = @red_envelope;

    const ErrorNotSupportType: u64 = 1;
    const ErrorEnvelopeInsufficient: u64 = 2;
    const ErrorWrongOpenTime: u64 = 3;
    const ErrorAlreadyClaimed: u64 = 4;
    const ErrorBitcoinClientError: u64 = 5;
    const ErrorNotSender: u64 = 6;
    const ErrorWrongAddNFTTime: u64 = 7;



    struct NFTEnvelope<phantom T: key+store> has key, store {
        sender: address,
        start_time: u64,
        end_time: u64,
        claimed_address: vector<address>,
        nft: TableVec<Object<T>>,
        meta: EnvelopeMeta
    }

    struct CoinEnvelope<phantom CoinType: key+store> has key, store {
        sender: address,
        coin_type: String,
        claim_type: u8,
        start_time: u64,
        end_time: u64,
        total_envelope: u64,
        total_coin: u256,
        claimed_address: Table<address, u256>,
        remaining_coin: u256,
        coin_store: Object<CoinStore<CoinType>>,
        meta: EnvelopeMeta,
    }

    struct EnvelopeMeta has drop, copy, store {
        name: String,
        desc: String,
        image_url: String,
        theme_mode: u8,
        color_mode: u8
    }

    struct EnvelopeTable has key, store {
        coin_envelope: TableVec<ObjectID>,
        nft_envelope: TableVec<ObjectID>,
        user_table: Table<address, TableVec<ObjectID>>
    }

    struct ClaimCoinEvent has copy, drop {
        envelope_id: ObjectID,
        addr: address,
        coin: u256,
        time: u64
    }

    struct ClaimNFTEvent has copy, drop {
        envelope_id: ObjectID,
        addr: address,
        nft_id: ObjectID,
        time: u64
    }

    fun init(owner: &signer) {
        account::move_resource_to(owner, EnvelopeTable{
            coin_envelope: table_vec::new(),
            nft_envelope: table_vec::new(),
            user_table: table::new()
        });
    }

    public entry fun create_nft_envelope<T: key+store>(
        name: String,
        desc: String,
        image_url: String,
        theme_mode: u8,
        color_mode: u8,
        start_time: u64,
        end_time: u64,
        nft_vec: vector<Object<T>>
    ){
        if (end_time <= start_time) {
            end_time = U64MAX;
        };
        let envelope_nft = table_vec::new<Object<T>>();
        let i = vector::length(&nft_vec);
        while (i > 0) {
            table_vec::push_back(&mut envelope_nft, vector::pop_back(&mut nft_vec));
            i = i - 1;
        };
        vector::destroy_empty(nft_vec);
        let envelope_obj = new(NFTEnvelope<T>{
            sender: sender(),
            start_time,
            end_time,
            claimed_address: vector[],
            nft: envelope_nft,
            meta: EnvelopeMeta{
                name,
                desc,
                image_url,
                theme_mode,
                color_mode
            }
        });
        let envelope_id = object::id(&envelope_obj);
        let envelope_table = account::borrow_mut_resource<EnvelopeTable>(DEPLOYER);
        table_vec::push_back(&mut envelope_table.nft_envelope, envelope_id);
        if (!table::contains(&envelope_table.user_table, sender())){
            table::add(&mut envelope_table.user_table, sender(), table_vec::singleton(envelope_id))
        }else {
            table_vec::push_back(table::borrow_mut(&mut envelope_table.user_table, sender()), envelope_id);
        };
        to_shared(envelope_obj);
    }
    public entry fun add_nft2envelope<T:key+store>(
        envelope_obj: &mut Object<NFTEnvelope<T>>,
        nft_vec: vector<Object<T>>
    ) {
        let envelope = object::borrow_mut(envelope_obj);
        assert!(envelope.sender == sender(), ErrorNotSender);
        assert!(envelope.start_time > now_milliseconds(), ErrorWrongAddNFTTime);
        let i = vector::length(&nft_vec);
        while (i > 0) {
            table_vec::push_back(&mut envelope.nft, vector::pop_back(&mut nft_vec));
            i = i - 1;
        };
        vector::destroy_empty(nft_vec);
    }

    entry fun claim_nft_envelope<T:key+store>(
        envelope_obj: &mut Object<NFTEnvelope<T>>
    ){
        let envelope_id = object::id(envelope_obj);
        let envelope = object::borrow_mut(envelope_obj);
        let now_time = now_milliseconds();
        assert!(envelope.start_time <= now_time, ErrorWrongOpenTime);
        assert!(envelope.end_time >= now_time, ErrorWrongOpenTime);
        assert!(!vector::contains(&envelope.claimed_address, &sender()), ErrorAlreadyClaimed);

        let max_value = (table_vec::length(&envelope.nft) as u256);
        let magic_number = generate_magic_number();
        let claim_value = generate_index(magic_number, max_value);
        let nft = table_vec::swap_remove(&mut envelope.nft, (claim_value as u64));
        let nft_id = object::id(&nft);
        emit(ClaimNFTEvent{
            envelope_id,
            addr: sender(),
            nft_id,
            time: now_milliseconds()
        });
        transfer(nft, sender());
        vector::push_back(&mut envelope.claimed_address, sender());
    }

    public entry fun recovery_nft_envelope<T: key+store>(
        envelope_obj: &mut Object<NFTEnvelope<T>>
    ){
        let envelope = object::borrow_mut(envelope_obj);
        assert!(envelope.end_time < now_milliseconds(), ErrorWrongOpenTime);
        assert!(envelope.sender == sender(), ErrorNotSender);
        let total_remeaning_nft = table_vec::length(&envelope.nft);
        let i = 0;
        while (i < total_remeaning_nft) {
            transfer(table_vec::pop_back(&mut envelope.nft), sender());
            i = i + 1;
            if (i >= 500) {
                break
            }
        }
    }

    public entry fun create_coin_envelope<CoinType: key+store>(
        from: &signer,
        name: String,
        desc: String,
        image_url: String,
        theme_mode: u8,
        color_mode: u8,
        claim_type: u8,
        total_envelope: u64,
        total_coin: u256,
        start_time: u64,
        end_time: u64,
    ) {
        assert!(claim_type <= 1, ErrorNotSupportType);
        if (end_time <= start_time) {
            end_time = U64MAX;
        };
        let envelope_coin_store = coin_store::create_coin_store<CoinType>();
        let coin = account_coin_store::withdraw<CoinType>(from, total_coin);
        coin_store::deposit(&mut envelope_coin_store, coin);
        let envelope_obj = new(CoinEnvelope{
            sender: sender(),
            coin_type: type_info::type_name<CoinType>(),
            claim_type,
            start_time,
            end_time,
            total_envelope,
            total_coin,
            remaining_coin: total_coin,
            claimed_address: table::new(),
            coin_store: envelope_coin_store,
            meta: EnvelopeMeta{
                name,
                desc,
                image_url,
                theme_mode,
                color_mode
            }
        });
        let envelope_id = object::id(&envelope_obj);
        let envelope_table = account::borrow_mut_resource<EnvelopeTable>(DEPLOYER);
        table_vec::push_back(&mut envelope_table.coin_envelope, envelope_id);
        if (!table::contains(&envelope_table.user_table, sender())){
            table::add(&mut envelope_table.user_table, sender(), table_vec::singleton(envelope_id))
        }else {
            table_vec::push_back(table::borrow_mut(&mut envelope_table.user_table, sender()), envelope_id);
        };
        to_shared(envelope_obj);
    }

    entry fun claim_coin_envelope<CoinType: key+store>(
        envelope_obj: &mut Object<CoinEnvelope<CoinType>>
    ){
        let envelope_id = object::id(envelope_obj);
        let envelope = object::borrow_mut(envelope_obj);
        assert!(table::length(&envelope.claimed_address) < envelope.total_envelope, ErrorEnvelopeInsufficient);
        let now_time = now_milliseconds();
        assert!(envelope.start_time <= now_time, ErrorWrongOpenTime);
        assert!(envelope.end_time >= now_time, ErrorWrongOpenTime);
        assert!(!table::contains(&envelope.claimed_address, sender()), ErrorAlreadyClaimed);
        let claim_value = 0;
        if (envelope.claim_type == 0) {
            // Equal distribution
            claim_value = envelope.total_coin / (envelope.total_envelope as u256);
            let reward_coin = coin_store::withdraw(&mut envelope.coin_store, claim_value);
            account_coin_store::deposit(sender(), reward_coin);
        }else if (envelope.claim_type == 1) {
            // Rand distribution
            let left_envelope = envelope.total_envelope - table::length(&envelope.claimed_address);
            if (left_envelope == 1) {
                // The last recipient will receive the remaining amount in full
                claim_value = coin_store::balance(&envelope.coin_store);
                let reward_coin = coin_store::withdraw(&mut envelope.coin_store, claim_value);
                account_coin_store::deposit(sender(), reward_coin);

            }else {
                let max_value = coin_store::balance(&envelope.coin_store) / (left_envelope as u256) * 2;
                let magic_number = generate_magic_number();
                claim_value = generate_index(magic_number, max_value);
                let reward_coin = coin_store::withdraw(&mut envelope.coin_store, claim_value);
                account_coin_store::deposit(sender(), reward_coin);
            }
        };
        emit(ClaimCoinEvent{
            envelope_id,
            addr: sender(),
            coin: claim_value,
            time: now_time
        });
        envelope.remaining_coin = coin_store::balance(&envelope.coin_store);
        table::add(&mut envelope.claimed_address, sender(), claim_value);

    }

    public entry fun recovery_coin_envelope<CoinType: key+store>(
        envelope_obj: &mut Object<CoinEnvelope<CoinType>>
    ){
        let envelope = object::borrow_mut(envelope_obj);
        assert!(envelope.end_time < now_milliseconds(), ErrorWrongOpenTime);
        assert!(envelope.sender == sender(), ErrorNotSender);
        let claim_value = coin_store::balance(&envelope.coin_store);
        let reward_coin = coin_store::withdraw(&mut envelope.coin_store, claim_value);
        envelope.remaining_coin = coin_store::balance(&envelope.coin_store);
        account_coin_store::deposit(sender(), reward_coin);
    }

    fun latest_block_height(): u64 {
        let height_hash = bitcoin::get_latest_block();
        assert!(option::is_some(&height_hash), ErrorBitcoinClientError);
        let (height,_hash) = types::unpack_block_height_hash(option::destroy_some(height_hash));
        height
    }

    fun generate_magic_number(): u64 {
        // generate a random number from tx_context
        let bytes = vector::empty<u8>();
        let tx_sequence_info_opt = tx_context::get_attribute<TransactionSequenceInfo>();
        if (option::is_some(&tx_sequence_info_opt)) {
            let tx_sequence_info = option::extract(&mut tx_sequence_info_opt);
            let tx_accumulator_root = transaction::tx_accumulator_root(&tx_sequence_info);
            let tx_accumulator_root_bytes = bcs::to_bytes(&tx_accumulator_root);
            vector::append(&mut bytes, tx_accumulator_root_bytes);
        } else {
            // if it doesn't exist, get the tx hash
            vector::append(&mut bytes, bcs::to_bytes(&tx_context::tx_hash()));
        };
        vector::append(&mut bytes, bcs::to_bytes(&tx_context::sequence_number()));
        vector::append(&mut bytes, bcs::to_bytes(&tx_context::sender()));
        vector::append(&mut bytes, bcs::to_bytes(&timestamp::now_milliseconds()));

        let seed = hash::sha3_256(bytes);
        let magic_number = bytes_to_u64(seed);
        magic_number
    }

    fun generate_index(magic_number: u64, max_value: u256): u256 {
        // generate the box with the block hash and the magic number
        let block_height = latest_block_height();
        let block_opt = bitcoin::get_block_by_height(block_height);
        assert!(option::is_some<Header>(&block_opt), ErrorBitcoinClientError);
        let block = option::extract(&mut block_opt);
        let bytes = vector::empty<u8>();
        vector::append(&mut bytes, bcs::to_bytes(&block));
        vector::append(&mut bytes, bcs::to_bytes(&magic_number));
        vector::append(&mut bytes, bcs::to_bytes(&tx_context::sequence_number()));
        vector::append(&mut bytes, bcs::to_bytes(&tx_context::sender()));
        vector::append(&mut bytes, bcs::to_bytes(&tx_context::tx_hash()));

        let seed = hash::sha3_256(bytes);
        let value = bytes_to_u256(seed);

        value % max_value // An uniform distribution random number range in [0, max_value)

    }

    fun bytes_to_u64(bytes: vector<u8>): u64 {
        let value = 0u64;
        let i = 0u64;
        while (i < 8) {
            value = value | ((*vector::borrow(&bytes, i) as u64) << ((8 * (7 - i)) as u8));
            i = i + 1;
        };
        return value
    }

    public fun bytes_to_u256(bytes: vector<u8>): u256 {
        let output: u256 = 0;
        let bytes_length: u64 = 32;
        let idx: u64 = 0;
        while (idx < bytes_length) {
            let current_byte = *std::vector::borrow(&bytes, idx);
            output = (output << 8) | (current_byte as u256) ;
            idx = idx + 1;
        };
        output
    }
}
