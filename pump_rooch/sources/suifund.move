module pump_rooch::suifund {

    use std::ascii::{String, string};
    use std::option;
    use std::type_name;
    use std::vector;
    use std::vector::pop_back;
    use pump_rooch::comment;
    use rooch_framework::coin;
    use moveos_std::event::emit;
    use moveos_std::table_vec;
    use moveos_std::timestamp::now_milliseconds;
    use rooch_framework::coin::Coin;
    use rooch_framework::account_coin_store;
    use pump_rooch::utils::{mul_div, get_remain_value};
    use moveos_std::display;
    use moveos_std::object;
    use rooch_framework::coin_store;
    use moveos_std::table;
    use moveos_std::tx_context::sender;
    use pump_rooch::comment::Comment;
    use moveos_std::table_vec::TableVec;
    use rooch_framework::gas_coin::GasCoin;
    use rooch_framework::coin_store::CoinStore;
    use moveos_std::object::{ObjectID, Object, to_shared, new_named_object, transfer};
    use moveos_std::table::Table;

    friend pump_rooch::swap;

    // ======== Constants =========
    const VERSION: u64 = 1;
    const THREE_DAYS_IN_MS: u64 = 259_200_000;
    const SUI_BASE: u64 = 1_000_000_000;
    const BASE_FEE: u64 = 20_000_000_000; // 20 SUI

    // ======== Errors =========
    const EInvalidStartTime: u64 = 1;
    const EInvalidTimeInterval: u64 = 2;
    const EInvalidRatio: u64 = 3;
    const EInvalidSuiValue: u64 = 4;
    const ETooLittle: u64 = 5;
    const ENotStarted: u64 = 6;
    // const EEnded: u64 = 7;
    const ECapMismatch: u64 = 8;
    const EAlreadyMax: u64 = 9;
    const ENotSameProject: u64 = 10;
    const ErrorAttachDFExists: u64 = 11;
    const EInvalidAmount: u64 = 12;
    const ENotSplitable: u64 = 13;
    const EProjectCanceled: u64 = 14;
    const ENotBurnable: u64 = 15;
    const EVersionMismatch: u64 = 16;
    const EImproperRatio: u64 = 17;
    const EProjectNotCanceled: u64 = 18;
    const ETakeAwayNotCompleted: u64 = 19;
    const EInvalidThresholdRatio: u64 = 20;
    const ENotBegin: u64 = 21;
    const EAlreadyBegin: u64 = 22;
    const ENotCanceled: u64 = 23;
    const ENoRemain: u64 = 24;

    // ======== Types =========
    struct SUIFUND has drop {}

    struct DeployRecord has key {
        version: u64,
        record: Table<std::ascii::String, ObjectID>,
        categorys: Table<std::ascii::String, Table<std::ascii::String, ObjectID>>,
        balance: Object<CoinStore<GasCoin>>,
        base_fee: u64,
        ratio: u64,
    }

    struct TablePlaceholder has key {
        _placeholder: bool,
    }

    struct ProjectRecord has key {
        id: Object<TablePlaceholder>,
        version: u64,
        creator: address,
        name: std::ascii::String,
        description: std::string::String,
        category: std::ascii::String,
        image_url: String,
        linktree: String,
        x: String,
        telegram: String,
        discord: String,
        website: String,
        github: String,
        cancel: bool,
        balance: Object<CoinStore<GasCoin>>,
        ratio: u64,
        start_time_ms: u64,
        end_time_ms: u64,
        total_supply: u64,
        amount_per_sui: u64, 
        remain: u64,
        current_supply: u64,
        total_transactions: u64,
        threshold_ratio: u64,
        begin: bool,
        min_value_sui: u64,
        max_value_sui: u64,
        participants: TableVec<address>, 
        minted_per_user: Table<address, u64>,
        thread: TableVec<Comment>,
    }

    struct ProjectAdminCap has key, store {
        to: ObjectID,
    }

    struct AdminCap has key, store {}

    struct SupporterReward has key, store {
        id: Object<TablePlaceholder>,
        name: std::ascii::String,
        project_id: ObjectID,
        image: String,
        amount: u64,
        balance: Object<CoinStore<GasCoin>>,
        start: u64,
        end: u64,
        attach_df: u8,
    }

    // ======== Events =========
    struct DeployEvent has copy, drop {
        project_id: ObjectID,
        project_name: std::ascii::String,
        deployer: address,
        deploy_fee: u64,
    }

    struct EditProject has copy, drop {
        project_name: std::ascii::String,
        editor: address,
    }

    struct MintEvent has copy, drop {
        project_name: std::ascii::String,
        project_id: ObjectID,
        sender: address,
        amount: u64,
    }

    struct BurnEvent has copy, drop {
        project_name: std::ascii::String,
        project_id: ObjectID,
        sender: address,
        amount: u64,
        withdraw_value: u64,
        inside_value: u256,
    }

    struct ReferenceReward has copy, drop {
        sender: address,
        recipient: address,
        value: u256,
        project: ObjectID,
    }

    struct ClaimStreamPayment has copy, drop {
        project_name: std::ascii::String,
        sender: address,
        value: u256,
    }

    struct CancelProjectEvent has copy, drop {
        project_name: std::ascii::String,
        project_id: ObjectID,
        sender: address,
    }


    // ======== Functions =========
    fun init() {
        let deployer = sender();
        let deploy_record = DeployRecord {version: VERSION, record: table::new(), categorys: table::new(), balance: coin_store::create_coin_store<GasCoin>(), base_fee: BASE_FEE, ratio: 1 };
        to_shared(new_named_object(deploy_record));
        let admin_cap = object::new_named_object(AdminCap{});
        transfer(admin_cap, deployer);

        let keys = vector[
            std::string::utf8(b"name"),
            std::string::utf8(b"image_url"),
            std::string::utf8(b"project_url"),
            std::string::utf8(b"market_url"),
            std::string::utf8(b"coinswap_url"),
            std::string::utf8(b"start"),
            std::string::utf8(b"end"),
            std::string::utf8(b"alert"),
        ];
        let image_url: vector<u8> = b"https://pumpsuiapi.com/objectId/";
        vector::append(&mut image_url, b"{id}");
        let project_url: vector<u8> = b"https://pumpsui.com/project/";
        vector::append(&mut project_url, b"{project_id}");
        let market_url: vector<u8> = b"https://pumpsui.com/market/";
        vector::append(&mut market_url, b"{project_id}");
        let coinswap_url: vector<u8> = b"https://pumpsui.com/coinswap/";
        vector::append(&mut coinswap_url, b"{project_id}");
        let values = vector[
            std::string::utf8(b"Supporter Ticket"),
            std::string::utf8(image_url),
            std::string::utf8(project_url),
            std::string::utf8(market_url),
            std::string::utf8(coinswap_url),
            std::string::utf8(b"{start}"),
            std::string::utf8(b"{end}"),
            std::string::utf8(b"!!!Do not visit any links in the pictures, as they may be SCAMs."),
        ];
        while (vector::length(&keys) > 0){
            display::set_value<SupporterReward>(
                display::display(), pop_back(&mut keys), pop_back(&mut values)
            );
        };
    }

    // ======= Deploy functions ========

    public fun get_deploy_fee(
        total_deposit: u64,
        base_fee: u64,
        project_ratio: u64,
        deploy_ratio: u64
    ): u64 {
        assert!(deploy_ratio <= 5, EImproperRatio);
        let cal_value: u64 = mul_div(total_deposit, project_ratio, 100);
        cal_value = mul_div(cal_value, deploy_ratio, 100);
        let fee_value: u64 =  if (cal_value > base_fee) {
            cal_value
        } else { base_fee };
        fee_value
    }

    public entry fun deploy(
        account: &signer,
        deploy_record_obj: &mut Object<DeployRecord>,
        name: vector<u8>,
        description: vector<u8>,
        category: vector<u8>,
        image_url: vector<u8>,
        linktree: vector<u8>,
        x: vector<u8>,
        telegram: vector<u8>,
        discord: vector<u8>,
        website: vector<u8>,
        github: vector<u8>,
        start_time_ms: u64,
        time_interval: u64,
        total_deposit_sui: u64,
        ratio: u64,
        amount_per_sui: u64,
        threshold_ratio: u64,
        min_value_sui: u64, 
        max_value_sui: u64,
    ) {
        let deploy_record = object::borrow_mut(deploy_record_obj);
        let project_admin_cap = deploy_non_entry(
            account,
            deploy_record,
            name,
            description,
            category,
            image_url,
            linktree,
            x,
            telegram,
            discord,
            website,
            github,
            start_time_ms,
            time_interval,
            total_deposit_sui,
            ratio,
            amount_per_sui,
            threshold_ratio,
            min_value_sui, 
            max_value_sui,
        );
        transfer(project_admin_cap, sender());
    }

    public fun deploy_non_entry(
        account: &signer,
        deploy_record: &mut DeployRecord,
        name: vector<u8>,
        description: vector<u8>,
        category: vector<u8>,
        image_url: vector<u8>,
        linktree: vector<u8>,
        x: vector<u8>,
        telegram: vector<u8>,
        discord: vector<u8>,
        website: vector<u8>,
        github: vector<u8>,
        start_time_ms: u64,
        time_interval: u64,
        total_deposit_sui: u64,
        ratio: u64,
        amount_per_sui: u64,
        threshold_ratio: u64,
        min_value_sui: u64, 
        max_value_sui: u64,
    ): Object<ProjectAdminCap> {
        assert!(deploy_record.version == VERSION, EVersionMismatch);
        let sender = sender();
        let now = now_milliseconds();
        assert!(start_time_ms >= now, EInvalidStartTime);
        assert!(time_interval >= THREE_DAYS_IN_MS, EInvalidTimeInterval);
        assert!(ratio <= 100, EInvalidRatio);
        assert!(threshold_ratio <= 100, EInvalidThresholdRatio);
        assert!(min_value_sui >= SUI_BASE, ETooLittle);
        assert!(amount_per_sui >= 1, ETooLittle);
        if (max_value_sui != 0) {
            assert!(min_value_sui <= max_value_sui, EInvalidSuiValue);
        };

        let deploy_fee = get_deploy_fee(total_deposit_sui, deploy_record.base_fee, ratio, deploy_record.ratio);
        let deploy_coin = account_coin_store::withdraw<GasCoin>(account, (deploy_fee as u256));
        coin_store::deposit(&mut deploy_record.balance, deploy_coin);

        let category = std::ascii::string(category);

        let total_supply = total_deposit_sui / SUI_BASE * amount_per_sui;
        let project_name = std::ascii::string(name); 
        let project_record = object::new(ProjectRecord {
            id: object::new(TablePlaceholder{_placeholder: false}),
            version: VERSION,
            creator: sender,
            name: project_name,
            description: std::string::utf8(description),
            category,
            image_url: string(image_url),
            linktree: string(linktree),
            x: string(x),
            telegram: string(telegram),
            discord: string(discord),
            website: string(website),
            github: string(github),
            cancel: false,
            balance: coin_store::create_coin_store<GasCoin>(),
            ratio,
            start_time_ms,
            end_time_ms: start_time_ms + time_interval,
            total_supply,
            amount_per_sui,
            remain: total_supply,
            current_supply: 0,
            total_transactions: 0,
            threshold_ratio,
            begin: false,
            min_value_sui,
            max_value_sui,
            participants: table_vec::new<address>(),
            minted_per_user: table::new<address, u64>(),
            thread: table_vec::new<Comment>(),
        });

        let project_id = object::id(&project_record);
        let project_admin_cap = object::new(ProjectAdminCap {
            to: project_id,
        });

        table::add<std::ascii::String, ObjectID>(&mut deploy_record.record, project_name, project_id);

        if (std::ascii::length(&category) > 0) {
            if (table::contains<std::ascii::String, Table<std::ascii::String, ObjectID>>(&deploy_record.categorys, category)) {
                table::add<std::ascii::String, ObjectID>(table::borrow_mut(&mut deploy_record.categorys, category), project_name, project_id);
            } else {
                let category_record = table::new<std::ascii::String, ObjectID>();
                table::add<std::ascii::String, ObjectID>(&mut category_record, project_name, project_id);
                table::add<std::ascii::String, Table<std::ascii::String, ObjectID>>(&mut deploy_record.categorys, category, category_record);
            };
        };

        to_shared(project_record);
        emit(DeployEvent {
            project_id,
            project_name,
            deployer: sender,
            deploy_fee,
        });

        project_admin_cap
    }

    // ======= Claim functions ========

    public fun do_claim(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
    ): Coin<GasCoin> {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);

        assert!(project_record.version == VERSION, EVersionMismatch);
        assert!(project_record.begin, ENotBegin);
        assert!(!project_record.cancel, EProjectCanceled);

        let now = now_milliseconds();
        let init_value = mul_div(project_record.current_supply, SUI_BASE, project_record.amount_per_sui);
        init_value = init_value * project_record.ratio / 100;
        let remain_value = get_remain_value(init_value, project_record.start_time_ms, project_record.end_time_ms, now);
        let claim_value = coin_store::balance(&project_record.balance) - (remain_value as u256);

        emit(ClaimStreamPayment {
            project_name: project_record.name,
            sender: sender(),
            value: claim_value,
        });
        coin_store::withdraw(&mut project_record.balance, claim_value)
    }

    public entry fun claim(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
    ) {
        let claim_coin = do_claim(project_record_obj, project_admin_cap_obj);
        account_coin_store::deposit(sender(), claim_coin);
    }

    // ======= Mint functions ========

    public entry fun mint(
        account: &signer,
        project_record_obj: &mut Object<ProjectRecord>,
        fee: u64
    ) {
        let supporter_reward = do_mint(account, project_record_obj, fee);
        transfer(supporter_reward, sender());
    }

    public fun do_mint(
        account: &signer,
        project_record_obj: &mut Object<ProjectRecord>,
        fee: u64
    ): Object<SupporterReward> {
        let project_id = object::id(project_record_obj);

        let sender = sender();
        let now = now_milliseconds();
        let project_record = object::borrow_mut(project_record_obj);
        assert!(now >= project_record.start_time_ms, ENotStarted);
        // assert!(now <= project_record.end_time_ms, EEnded);
        assert!(project_record.version == VERSION, EVersionMismatch);
        assert!(!project_record.cancel, EProjectCanceled);
        assert!(project_record.remain > 0, ENoRemain);

        assert!(fee >= project_record.min_value_sui, ETooLittle);

        if (table::contains<address, u64>(&project_record.minted_per_user, sender)) {
            let minted_value = table::borrow_mut(&mut project_record.minted_per_user, sender);
            if (project_record.max_value_sui > 0 && fee + *minted_value > project_record.max_value_sui) {
                fee = project_record.max_value_sui - *minted_value;
            };
            assert!(fee > 0, EAlreadyMax);
            *minted_value = *minted_value + fee;
        } else {
            if (project_record.max_value_sui > 0 && fee > project_record.max_value_sui) {
                fee = project_record.max_value_sui;
            };
            table::add<address, u64>(&mut project_record.minted_per_user, sender, fee);
            table_vec::push_back<address>(&mut project_record.participants, sender);
        };

        let amount: u64 = mul_div(fee, project_record.amount_per_sui, SUI_BASE);

        if (amount >= project_record.remain) {
            amount = project_record.remain;
            fee = mul_div(amount, SUI_BASE, project_record.amount_per_sui);
        };

        project_record.remain = project_record.remain - amount;
        project_record.current_supply = project_record.current_supply + amount;
        project_record.total_transactions = project_record.total_transactions + 1;

        let project_sui_value = fee * project_record.ratio / 100;
        let locked_sui_value = fee * (100 - project_record.ratio) / 100;
        let project_fee = account_coin_store::withdraw<GasCoin>(account, (project_sui_value as u256));
        coin_store::deposit(&mut project_record.balance, project_fee);

        if (!project_record.begin && 
            project_record.current_supply >= mul_div(project_record.total_supply, project_record.threshold_ratio, 100)
        ) {
            project_record.begin = true;
        };


        emit(MintEvent {
            project_name: project_record.name,
            project_id,
            sender,
            amount,
        });
        let locked_sui = account_coin_store::withdraw<GasCoin>(account, (locked_sui_value as u256));
        object::new(new_supporter_reward(
            project_record.name,
            project_id,
            project_record.image_url,
            amount,
            locked_sui,
            project_record.start_time_ms,
            project_record.end_time_ms
        ))
    }

    public fun reference_reward(reward: Coin<GasCoin>, sender: address, recipient: address, project_record_obj: &Object<ProjectRecord>) {
        emit(ReferenceReward {
            sender,
            recipient,
            value: coin::value(&reward),
            project: object::id(project_record_obj),
        });
        account_coin_store::deposit(recipient, reward);
    }

    // ======= Merge functions ========

    public fun do_merge(
        sp_rwd_1_obj: &mut Object<SupporterReward>,
        sp_rwd_2_obj: Object<SupporterReward>
    ) {
        let sp_rwd_1 = object::borrow_mut(sp_rwd_1_obj);
        let sp_rwd_2 = object::remove(sp_rwd_2_obj);
        assert!(sp_rwd_1.name == sp_rwd_2.name, ENotSameProject);
        assert!(sp_rwd_2.attach_df == 0, ErrorAttachDFExists);
        let SupporterReward { id, name: _, project_id: _, image: _, amount, balance, start: _, end: _, attach_df: _ } = sp_rwd_2;
        let TablePlaceholder{
            _placeholder: _
        } = object::remove(id);
        sp_rwd_1.amount = sp_rwd_1.amount + amount;
        let rwd_2_coin = coin_store::remove_coin_store(balance);
        coin_store::deposit(&mut sp_rwd_1.balance, rwd_2_coin);
    }

    public entry fun merge(
        sp_rwd_1_obj: &mut Object<SupporterReward>,
        sp_rwd_2_obj: Object<SupporterReward>
    ) {
        do_merge(sp_rwd_1_obj, sp_rwd_2_obj);
    }

    // ======= Split functions ========

    public fun is_splitable(sp_rwd: &SupporterReward): bool {
        sp_rwd.amount > 1 && sp_rwd.attach_df == 0
    }

    public fun do_split(
        sp_rwd_obj: &mut Object<SupporterReward>,
        amount: u64,
    ): Object<SupporterReward> {
        let sp_rwd = object::borrow_mut(sp_rwd_obj);
        assert!(0 < amount && amount < sp_rwd.amount, EInvalidAmount);
        assert!(is_splitable(sp_rwd), ENotSplitable);

        let sui_value = coin_store::balance(&sp_rwd.balance);

        let new_sui_value = mul_div((sui_value as u64), amount, sp_rwd.amount);
        if (new_sui_value == 0) {
            new_sui_value = 1;
        };

        let new_sui_balance = coin_store::withdraw(&mut sp_rwd.balance, (new_sui_value as u256));
        sp_rwd.amount = sp_rwd.amount - amount;

        object::new(new_supporter_reward(
            sp_rwd.name,
            sp_rwd.project_id,
            sp_rwd.image,
            amount,
            new_sui_balance,
            sp_rwd.start,
            sp_rwd.end,
        ))
    }

    public entry fun split(
        sp_rwd_obj: &mut Object<SupporterReward>,
        amount: u64,
    ) {
        let new_sp_rwd = do_split(sp_rwd_obj, amount);
        transfer(new_sp_rwd, sender());
    }

    // ======= Burn functions ========

    public fun do_burn(
        project_record_obj: &mut Object<ProjectRecord>,
        sp_rwd_obj: Object<SupporterReward>,
    ): Coin<GasCoin> {
        let sp_rwd = object::remove(sp_rwd_obj);
        let id = object::id(project_record_obj);
        let project_record = object::borrow_mut(project_record_obj);
        assert!( id == sp_rwd.project_id, ENotSameProject);
        assert!(project_record.version == VERSION, EVersionMismatch);
        assert!(sp_rwd.attach_df == 0, ENotBurnable);

        let sender = sender();
        let now = now_milliseconds();

        let total_value = if (project_record.cancel || !project_record.begin) {
            coin_store::balance(&project_record.balance)
        } else {
            (get_remain_value(
                mul_div(project_record.current_supply, SUI_BASE, project_record.amount_per_sui),
                project_record.start_time_ms,
                project_record.end_time_ms,
                now
            ) * project_record.ratio / 100 as u256)
        };

        let withdraw_value = mul_div((total_value as u64), sp_rwd.amount, project_record.current_supply);
        let inside_value = coin_store::balance(&sp_rwd.balance);

        project_record.current_supply = project_record.current_supply - sp_rwd.amount;
        project_record.remain = project_record.remain + sp_rwd.amount;
        let sender_minted = table::borrow_mut(&mut project_record.minted_per_user, sender);
        if (*sender_minted >= sp_rwd.amount) {
            *sender_minted = *sender_minted - sp_rwd.amount;
        };

        let SupporterReward {
            id,
            name,
            project_id,
            image: _,
            amount,
            balance,
            start: _,
            end: _,
            attach_df: _,
        } = sp_rwd;
        let TablePlaceholder{
            _placeholder: _
        } = object::remove(id);
        let withdraw_coin = coin_store::withdraw(&mut project_record.balance, (withdraw_value as u256));
        let inside_coin = coin_store::remove_coin_store(balance);
        coin::merge(&mut withdraw_coin, inside_coin);

        emit(BurnEvent {
            project_name: name,
            project_id,
            sender,
            amount,
            withdraw_value,
            inside_value,
        });

        withdraw_coin
    }

    public entry fun burn(
        project_record_obj: &mut Object<ProjectRecord>,
        sp_rwd_obj: Object<SupporterReward>,

    ) {
        let withdraw_coin = do_burn(project_record_obj, sp_rwd_obj);
        account_coin_store::deposit(sender(), withdraw_coin);
    }

    // ======= Native Stake functions ========


    // ======= Edit ProjectRecord functions ========

    public entry fun add_comment(
        project_record_obj: &mut Object<ProjectRecord>,
        reply: ObjectID,
        media_link: vector<u8>, 
        content: vector<u8>, 

    ) {
        let project_record = object::borrow_mut(project_record_obj);
        let comment = comment::new_comment(option::some(reply), media_link, content);
        table_vec::push_back<Comment>(&mut project_record.thread, comment);
    }

    public entry fun like_comment(
        project_record_obj: &mut Object<ProjectRecord>,
        idx: u64,
    ) {
        let project_record = object::borrow_mut(project_record_obj);
        let comment_bm = table_vec::borrow_mut(&mut project_record.thread, idx);
        comment::like_comment(comment_bm);
    }

    public entry fun unlike_comment(
        project_record_obj: &mut Object<ProjectRecord>,
        idx: u64,
    ) {
        let project_record = object::borrow_mut(project_record_obj);
        let comment_bm = table_vec::borrow_mut(&mut project_record.thread, idx);
        comment::unlike_comment(comment_bm);
    }

    public entry fun edit_description(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        description: vector<u8>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);
        project_record.description = std::string::utf8(description);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public entry fun edit_image_url(
        account: &signer,
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        image_url: vector<u8>,
        deploy_record_obj: &mut Object<DeployRecord>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);
        let deploy_record = object::borrow_mut(deploy_record_obj);
        let edit_coin = account_coin_store::withdraw<GasCoin>(account, (SUI_BASE / 10 as u256));
        coin_store::deposit(&mut deploy_record.balance, edit_coin);

        project_record.image_url = string(image_url);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public entry fun edit_linktree_url(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        linktree: vector<u8>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);
        project_record.linktree = string(linktree);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public entry fun edit_x_url(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        x_url: vector<u8>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);
        project_record.x = string(x_url);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public entry fun edit_telegram_url(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        telegram_url: vector<u8>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);

        project_record.telegram = string(telegram_url);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public entry fun edit_discord_url(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        discord_url: vector<u8>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);

        project_record.discord = string(discord_url);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public entry fun edit_website_url(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        website_url: vector<u8>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);

        project_record.website = string(website_url);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public entry fun edit_github_url(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        github_url: vector<u8>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);

        project_record.github = string(github_url);
        emit(EditProject {
            project_name: project_record.name,
            editor: sender(),
        });
    }

    public fun cancel_project_by_team(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
        deploy_record_obj: &mut Object<DeployRecord>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        let deploy_record = object::borrow_mut(deploy_record_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);

        cancel_project(deploy_record, project_record);
    }

    public fun burn_project_admin_cap(
        project_record_obj: &mut Object<ProjectRecord>,
        project_admin_cap_obj: &mut Object<ProjectAdminCap>,
    ) {
        let project_admin_cap = object::borrow(project_admin_cap_obj);
        check_project_cap(project_record_obj, project_admin_cap);
        let project_record = object::borrow_mut(project_record_obj);

        assert!(project_record.cancel, ENotCanceled);
        let ProjectAdminCap {
            to: _,
        } = project_admin_cap;
    }

    // ======= ProjectRecord Get functions ========

    public fun project_name(project_record: &Object<ProjectRecord>): std::ascii::String {
        object::borrow(project_record).name
    }

    public fun project_description(project_record: &Object<ProjectRecord>): std::string::String {
        object::borrow(project_record).description
    }

    public fun project_image_url(project_record: &Object<ProjectRecord>): String {
        object::borrow(project_record).image_url
    }

    public fun project_linktree_url(project_record: &Object<ProjectRecord>): String {
        object::borrow(project_record).linktree
    }

    public fun project_x_url(project_record: &Object<ProjectRecord>): String {
        object::borrow(project_record).x
    }

    public fun project_telegram_url(project_record: &Object<ProjectRecord>): String {
        object::borrow(project_record).telegram
    }

    public fun project_discord_url(project_record: &Object<ProjectRecord>): String {
        object::borrow(project_record).discord
    }

    public fun project_website_url(project_record: &Object<ProjectRecord>): String {
        object::borrow(project_record).website
    }

    public fun project_github_url(project_record: &Object<ProjectRecord>): String {
        object::borrow(project_record).github
    }

    public fun project_balance_value(project_record: &Object<ProjectRecord>): u256 {
        coin_store::balance(&object::borrow(project_record).balance)
    }

    public fun project_ratio(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).ratio
    }

    public fun project_start_time_ms(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).start_time_ms
    }

    public fun project_end_time_ms(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).end_time_ms
    }

    public fun project_total_supply(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).total_supply
    }

    public fun project_amount_per_sui(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).amount_per_sui
    }

    public fun project_remain(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).remain
    }

    public fun project_current_supply(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).current_supply
    }

    public fun project_total_transactions(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).total_transactions
    }

    public fun project_begin_status(project_record: &Object<ProjectRecord>): bool {
        object::borrow(project_record).begin
    }

    public fun project_threshold_ratio(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).threshold_ratio
    }

    public fun project_min_value_sui(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).min_value_sui
    }

    public fun project_max_value_sui(project_record: &Object<ProjectRecord>): u64 {
        object::borrow(project_record).max_value_sui
    }

    public fun project_participants_number(project_record: &Object<ProjectRecord>): u64 {
        table_vec::length<address>(&object::borrow(project_record).participants)
    }

    public fun project_participants(project_record: &Object<ProjectRecord>): &TableVec<address> {
        &object::borrow(project_record).participants
    }

    public fun project_minted_per_user(project_record: &Object<ProjectRecord>): &Table<address, u64> {
        &object::borrow(project_record).minted_per_user
    }

    public fun project_thread(project_record: &Object<ProjectRecord>): &TableVec<Comment> {
        &object::borrow(project_record).thread
    }

    public fun project_admin_cap_to(project_admin_cap: &Object<ProjectAdminCap>): ObjectID {
        object::borrow(project_admin_cap).to
    }

    // ======= Admin functions ========
    // In case of ProjectAdminCap is lost
    public fun cancel_project_by_admin(
        _: &mut Object<AdminCap>,
        deploy_record_obj: &mut Object<DeployRecord>,
        project_record_obj: &mut Object<ProjectRecord>,
    ) {
        let deploy_record = object::borrow_mut(deploy_record_obj);
        let project_record = object::borrow_mut(project_record_obj);
        cancel_project(deploy_record, project_record);
    }

    public fun take_remain(
        _: &mut Object<AdminCap>,
        project_record_obj: &mut Object<ProjectRecord>,
    ) {
        let project_record = object::borrow_mut(project_record_obj);
        assert!(project_record.cancel, EProjectNotCanceled);
        assert!(project_record.current_supply == 0, ETakeAwayNotCompleted);
        let sui_value = coin_store::balance(&project_record.balance);
        let remain = coin_store::withdraw(&mut project_record.balance, sui_value);
        account_coin_store::deposit(sender(), remain);
    }

    public fun set_base_fee(_: &mut Object<AdminCap>, deploy_record_obj: &mut Object<DeployRecord>, base_fee: u64) {
        object::borrow_mut(deploy_record_obj).base_fee = base_fee;
    }

    public fun set_ratio(_: &mut Object<AdminCap>, deploy_record_obj: &mut Object<DeployRecord>, ratio: u64) {
        assert!(ratio <= 5, EImproperRatio);
        object::borrow_mut(deploy_record_obj).ratio = ratio;
    }

    public fun withdraw_balance(_: &mut Object<AdminCap>, deploy_record_obj: &mut Object<DeployRecord>) {
        let deploy_record = object::borrow_mut(deploy_record_obj);
        let sui_value = coin_store::balance(&deploy_record.balance);
        let coin = coin_store::withdraw(&mut deploy_record.balance, sui_value);
        account_coin_store::deposit(sender(), coin);
    }

    // ======= SupporterReward Get functions ========
    public fun sr_name(sp_rwd: &Object<SupporterReward>): std::ascii::String {
        object::borrow(sp_rwd).name
    }

    public fun sr_project_id(sp_rwd: &Object<SupporterReward>): ObjectID {
        object::borrow(sp_rwd).project_id
    }

    public fun sr_image(sp_rwd: &Object<SupporterReward>): String {
        object::borrow(sp_rwd).image
    }

    public fun sr_amount(sp_rwd: &Object<SupporterReward>): u64 {
        object::borrow(sp_rwd).amount
    }

    public fun sr_balance_value(sp_rwd: &Object<SupporterReward>): u256 {
        coin_store::balance(&object::borrow(sp_rwd).balance)
    }

    public fun sr_start_time_ms(sp_rwd: &Object<SupporterReward>): u64 {
        object::borrow(sp_rwd).start
    }

    public fun sr_end_time_ms(sp_rwd: &Object<SupporterReward>): u64 {
        object::borrow(sp_rwd).end
    }

    public fun sr_attach_df_num(sp_rwd: &Object<SupporterReward>): u8 {
        object::borrow(sp_rwd).attach_df
    }

    public fun update_image(project_record_obj: &Object<ProjectRecord>, supporter_reward_obj: &mut Object<SupporterReward>) {
        let project_record = object::borrow(project_record_obj);
        let supporter_reward = object::borrow_mut(supporter_reward_obj);
        assert!(project_record.name == supporter_reward.name, ENotSameProject);
        supporter_reward.image = project_record.image_url;
    }

    public fun check_project_cap(project_record: &Object<ProjectRecord>, project_admin_cap: &ProjectAdminCap) {
        assert!(object::id(project_record)==project_admin_cap.to, ECapMismatch);
    }

    public(friend) fun add_df_in_project<Name: copy + drop + store, Value: store>(
        project_record_obj: &mut Object<ProjectRecord>,
        name: Name,
        value: Value
    ) {
        let project_record = object::borrow_mut(project_record_obj);
        assert!(project_record.version == VERSION, EVersionMismatch);
        object::add_field<TablePlaceholder, Name, Value>(&mut project_record.id, name, value);
    }

    public(friend) fun remove_df_in_project<Name: copy + drop + store, Value: store>(
        project_record_obj: &mut Object<ProjectRecord>,
        name: Name
    ): Value {
        let project_record = object::borrow_mut(project_record_obj);
        assert!(project_record.version == VERSION, EVersionMismatch);
        object::remove_field<TablePlaceholder, Name, Value>(&mut project_record.id, name)
    }

    public(friend) fun borrow_in_project<Name: copy + drop + store, Value: store>(
        project_record_obj: &Object<ProjectRecord>,
        name: Name
    ): &Value {
        let project_record = object::borrow(project_record_obj);
        assert!(project_record.version == VERSION, EVersionMismatch);
        object::borrow_field<TablePlaceholder, Name, Value>(&project_record.id, name)
    }

    public(friend) fun borrow_mut_in_project<Name: copy + drop + store, Value: store>(
        project_record_obj: &mut Object<ProjectRecord>,
        name: Name
    ): &mut Value {
        let project_record = object::borrow_mut(project_record_obj);
        assert!(project_record.version == VERSION, EVersionMismatch);
        object::borrow_mut_field<TablePlaceholder, Name, Value>(&mut project_record.id, name)
    }

    public(friend) fun exists_in_project<Name: copy + drop + store>(
        project_record_obj: &Object<ProjectRecord>,
        name: Name
    ): bool {
        let project_record = object::borrow(project_record_obj);
        assert!(project_record.version == VERSION, EVersionMismatch);
        object::contains_field<TablePlaceholder, Name>(&project_record.id, name)
    }

    fun add_df_with_attach<Value: store>(
        sp_rwd_obj: &mut Object<SupporterReward>,
        value: Value
    ) {
        let sp_rwd = object::borrow_mut(sp_rwd_obj);
        let name = type_name::into_string(type_name::get<Value>());
        assert!(sp_rwd.attach_df == 0, 0);
        sp_rwd.attach_df = sp_rwd.attach_df + 1;
        object::add_field(&mut sp_rwd.id, name, value);
    }

    fun remove_df_with_attach<Value: store>(
        sp_rwd_obj: &mut Object<SupporterReward>,
    ): Value {
        let sp_rwd = object::borrow_mut(sp_rwd_obj);
        let name = type_name::into_string(type_name::get<Value>());
        // assert attach_df > 0
        sp_rwd.attach_df = sp_rwd.attach_df - 1;
        let value: Value = object::remove_field(&mut sp_rwd.id, name);
        value
    }

    fun new_supporter_reward(
        name: std::ascii::String,
        project_id: ObjectID,
        image: String,
        amount: u64,
        balance: Coin<GasCoin>,
        start: u64,
        end: u64,
    ): SupporterReward {
        let store = coin_store::create_coin_store<GasCoin>();
        coin_store::deposit(&mut store, balance);
        SupporterReward {
            id: object::new(TablePlaceholder{_placeholder: false}),
            name,
            project_id,
            image,
            amount,
            balance: store,
            start,
            end,
            attach_df: 0,
        }
    }

    fun cancel_project(
        deploy_record: &mut DeployRecord,
        project_record: &mut ProjectRecord, 
    ) {
        assert!(!project_record.begin, EAlreadyBegin);
        project_record.cancel = true;

        let project_id = table::remove<std::ascii::String, ObjectID>(&mut deploy_record.record, project_record.name);
        if (std::ascii::length(&project_record.category) > 0) {
            let category_record_bm = table::borrow_mut(&mut deploy_record.categorys, project_record.category);
            table::remove<std::ascii::String, ObjectID>(category_record_bm, project_record.name);
            if (table::is_empty(category_record_bm)) {
                let category_record = table::remove<std::ascii::String, Table<std::ascii::String, ObjectID>>(&mut deploy_record.categorys, project_record.category);
                table::destroy_empty<std::ascii::String, ObjectID>(category_record);
            };
        };

        emit(
            CancelProjectEvent {
                project_name: project_record.name,
                project_id,
                sender: sender(),
            }
        );
    }

}

