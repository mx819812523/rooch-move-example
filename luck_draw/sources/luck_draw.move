module luck_draw::luck_draw {
    use std::option;
    use std::string::String;
    use std::vector;
    use rooch_framework::transaction;
    use rooch_framework::transaction::TransactionSequenceInfo;
    use bitcoin_move::types;
    use bitcoin_move::bitcoin;
    use moveos_std::timestamp::now_milliseconds;
    use bitcoin_move::types::Header;
    use moveos_std::hash;
    use moveos_std::timestamp;
    use moveos_std::tx_context;
    use moveos_std::bcs;
    use moveos_std::object;
    use moveos_std::account;
    use moveos_std::table_vec;
    use moveos_std::table_vec::TableVec;
    use moveos_std::tx_context::sender;
    use moveos_std::object::{transfer, new_named_object, Object, to_shared, ObjectID, new};


    const U64MAX: u64 = 18446744073709551615;
    const DEPLOYER: address = @luck_draw;

    const ErrorWrongClaimTime: u64 = 1;
    const ErrorBitcoinClientError: u64 = 2;
    const ErrorBoxCannotClaim: u64 = 3;
    const ErrorWrongOpenTime: u64 = 4;



    struct Box has key, store {
        reward_info: String,
        total_amount: u64,
        reward_amount: u64,
        start_time: u64,
        end_time: u64,
        is_end: bool,
        // If there is too much data here, it needs to be changed to TableVec
        claimed_address: vector<address>,
        reward_address: vector<address>
    }

    struct BoxTable has key, store {
        box: TableVec<ObjectID>
    }

    struct AdminCap has key, store {}

    fun init(owner: &signer) {
        transfer(new_named_object(AdminCap{}), sender());
        account::move_resource_to(owner, BoxTable{box: table_vec::new()});
    }

    public fun create_box(
        _admin: &mut Object<AdminCap>,
        reward_info: String,
        total_amount: u64,
        reward_amount: u64,
        start_time: u64,
        end_time: u64,
    ) {
        if (end_time <= start_time) {
            end_time = U64MAX;
        };
        let box_obj = new(Box{
            reward_info,
            total_amount,
            reward_amount,
            start_time,
            end_time,
            is_end: false,
            // If there is too much data here, it needs to be changed to TableVec
            claimed_address: vector[],
            reward_address: vector[]
        });
        let box_id = object::id(&box_obj);
        let box_table = account::borrow_mut_resource<BoxTable>(DEPLOYER);
        table_vec::push_back(&mut box_table.box, box_id);
        to_shared(box_obj);
    }

    public fun claim_box(
        box_id: ObjectID,
    ){
        let box_obj = object::borrow_mut_object_shared<Box>(box_id);
        let box = object::borrow_mut(box_obj);
        let now_time = now_milliseconds();
        assert!(box.start_time <= now_time, ErrorWrongClaimTime);
        let is_end = check_box_is_end(box);
        assert!(!is_end, ErrorBoxCannotClaim);
        vector::push_back(&mut box.claimed_address, sender())
    }

    public fun open_box(
        box_id: ObjectID,
    ){
        let box_obj = object::borrow_mut_object_shared<Box>(box_id);
        let box = object::borrow_mut(box_obj);
        let now_time = now_milliseconds();
        assert!(box.start_time <= now_time, ErrorWrongClaimTime);
        let is_end = check_box_is_end(box);
        assert!(is_end, ErrorWrongOpenTime);
        if (!box.is_end) {
            // claim over but box not open, now we open box
            box.is_end == true;
            let index = 0;
            let magic_number = generate_magic_number();
            while (index < box.reward_amount) {
                let max_value = vector::length(&box.claimed_address);
                let reward_index = generate_index(magic_number, max_value, index);
                let reward_address = vector::swap_remove(&mut box.claimed_address, reward_index);
                vector::push_back(&mut box.reward_address, reward_address);
            };
        }
    }

    public fun check_box_is_end(
        box: &Box
    ): bool{
        if (box.is_end == true || now_milliseconds() > box.end_time || vector::length(&box.claimed_address) >= box.total_amount) {
            return true
        };
        return false
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

    fun generate_index(magic_number: u64, max_value: u64, index: u64): u64 {
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
        vector::append(&mut bytes, bcs::to_bytes(&index));

        let seed = hash::sha3_256(bytes);
        let value = bytes_to_u64(seed);

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

}
