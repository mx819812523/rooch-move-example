module pump_rooch::swap {
    use std::type_name;
    use std::vector;
    use rooch_framework::account_coin_store;
    use moveos_std::tx_context::sender;
    use rooch_framework::coin::{CoinInfo, Coin};
    use rooch_framework::coin;
    use moveos_std::object;
    use pump_rooch::suifund;
    use moveos_std::object::{Object, transfer};
    use pump_rooch::suifund::{ProjectAdminCap, ProjectRecord, AdminCap, SupporterReward};

    const COIN_TYPE: vector<u8> = b"coin_type";
    const TREASURY: vector<u8> = b"treasury";
    const STORAGE: vector<u8> = b"storage_sr";

    const EAlreadyInit: u64         = 100;
    const EExpectZeroDecimals: u64  = 101;
    const EInvalidTreasuryCap: u64  = 102;
    const ENotInit: u64             = 103;
    const ENotSameProject: u64      = 104;
    const EZeroCoin: u64            = 105;
    const ENotBegin: u64            = 106;

    public entry fun init_swap_by_project_admin<T: key+store>(
        project_admin_cap_obj: &Object<ProjectAdminCap>,
        project_record_obj: &mut Object<ProjectRecord>,
        coin_info_obj: Object<CoinInfo<T>>
    ) {
        let project_admin_cap= object::borrow(project_admin_cap_obj);
        suifund::check_project_cap(project_record_obj, project_admin_cap);
        init_swap<T>(project_record_obj, coin_info_obj);
    }

    public entry fun init_swap_by_admin<T: key+store>(
        _: &mut Object<AdminCap>,
        project_record_obj: &mut Object<ProjectRecord>,
        coin_info_obj: Object<CoinInfo<T>>

    ) {
        init_swap<T>(project_record_obj, coin_info_obj);
    }

    fun init_swap<T: key+store>(
        project_record_obj: &mut Object<ProjectRecord>,
        coin_info_obj: Object<CoinInfo<T>>
    ) {
        let coin_info = coin::coin_info<T>();
        assert!(!suifund::exists_in_project<std::ascii::String>(project_record_obj, std::ascii::string(COIN_TYPE)), EAlreadyInit);
        assert!(suifund::project_begin_status(project_record_obj), ENotBegin);
        assert!(coin::supply<T>(coin_info) == 0, EInvalidTreasuryCap);
        assert!(coin::decimals<T>(coin_info) == 0, EExpectZeroDecimals);

        let coin_type = type_name::into_string(type_name::get<T>());
        suifund::add_df_in_project<std::ascii::String, std::ascii::String>(project_record_obj, std::ascii::string(COIN_TYPE), coin_type);
        suifund::add_df_in_project<std::ascii::String, Object<CoinInfo<T>>>(project_record_obj, std::ascii::string(TREASURY), coin_info_obj);
        suifund::add_df_in_project<std::ascii::String, vector<SupporterReward>>(project_record_obj, std::ascii::string(STORAGE), vector::empty<SupporterReward>());
    }

    public fun sr_to_coin<T: key+store>(
        project_record_obj: &mut Object<ProjectRecord>,
        supporter_reward_obj: Object<SupporterReward>,
    ): Coin<T> {
        assert!(suifund::exists_in_project<std::ascii::String>(project_record_obj, std::ascii::string(COIN_TYPE)), ENotInit);
        assert!(suifund::project_name(project_record_obj) == suifund::sr_name(&supporter_reward_obj), ENotSameProject);
        let value = suifund::sr_amount(&supporter_reward_obj);
        let storage_sr = suifund::borrow_mut_in_project<std::ascii::String, vector<Object<SupporterReward>>>(project_record_obj, std::ascii::string(STORAGE));

        if (vector::is_empty(storage_sr)) {
            vector::push_back(storage_sr, supporter_reward_obj);
        } else {
            let sr_mut = vector::borrow_mut(storage_sr, 0);
            suifund::do_merge(sr_mut, supporter_reward_obj);
        };

        let treasury = suifund::borrow_mut_in_project<std::ascii::String, Object<CoinInfo<T>>>(project_record_obj, std::ascii::string(TREASURY));
        coin::mint<T>(treasury, (value as u256))
    }

    public entry fun sr_to_coin_swap<T: key+store>(
        project_record_obj: &mut Object<ProjectRecord>,
        supporter_reward_obj: Object<SupporterReward>,
    ) {
        let coin = sr_to_coin<T>(project_record_obj, supporter_reward_obj);
        account_coin_store::deposit(sender(), coin);
    }

    public fun coin_to_sr<T: key+store>(
        project_record_obj: &mut Object<ProjectRecord>,
        sr_coin: Coin<T>,
    ): Object<SupporterReward> {
        assert!(suifund::exists_in_project<std::ascii::String>(project_record_obj, std::ascii::string(COIN_TYPE)), ENotInit);
        let treasury = suifund::borrow_mut_in_project<std::ascii::String, Object<CoinInfo<T>>>(project_record_obj, std::ascii::string(TREASURY));
        let value = coin::value(&sr_coin);
        assert!( value> 0, EZeroCoin);
        coin::burn<T>(treasury, sr_coin);

        let storage_sr = suifund::borrow_mut_in_project<std::ascii::String, vector<Object<SupporterReward>>>(project_record_obj, std::ascii::string(STORAGE));
        let sr_b = vector::borrow(storage_sr, 0);
        let sr_tsv = suifund::sr_amount(sr_b);

        if ((sr_tsv as u256) == value) {
            vector::pop_back(storage_sr)
        } else {
            let sr_bm = vector::borrow_mut(storage_sr, 0);
            suifund::do_split(sr_bm, (value as u64))
        }
    }

    public entry fun coin_to_sr_swap<T: key+store>(
        account: &signer,
        project_record: &mut Object<ProjectRecord>,
        sr_coin_amount: u256,
    ) {
        let sr_coin = account_coin_store::withdraw<T>(account, sr_coin_amount);
        let sr = coin_to_sr<T>(project_record, sr_coin);
        transfer(sr, sender());
    }


    // ======== Read Functions =========

    public fun get_coin_type(project_record: &Object<ProjectRecord>): &std::ascii::String {
        suifund::borrow_in_project<std::ascii::String, std::ascii::String>(project_record, std::ascii::string(COIN_TYPE))
    }
}