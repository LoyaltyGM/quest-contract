module holasui_quest::quest {
    use std::string::{Self, String, utf8};

    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::Coin;
    use sui::display;
    use sui::event::emit;
    use sui::object::{Self, ID, UID};
    use sui::object_table::{Self, ObjectTable};
    use sui::package;
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::transfer::{public_transfer, share_object, transfer};
    use sui::tx_context::{sender, TxContext};
    use sui::url::{Self, Url};

    use holasui_quest::utils::{handle_payment, handle_transfer, withdraw_balance};

    // ======== Constants =========

    const VERSION: u64 = 0;

    const VERIFIER: address = @0xfa40dda8beaf0bee40130a32df04bc74bb8a4bc85b2d27c54289fe8676d5f977;

    const REWARD_TYPE_NFT: u64 = 0;
    const REWARD_TYPE_SOULBOUND: u64 = 1;

    const FEE_FOR_CREATING_JOURNEY: u64 = 1000000000;
    const FEE_FOR_START_QUEST: u64 = 10000000;

    // ======== Errors =========

    const EWrongVersion: u64 = 0;
    const ENotUpgrade: u64 = 1;
    const ENotSpaceCreator: u64 = 2;
    const ENotSpaceAdmin: u64 = 3;
    const EInvalidTime: u64 = 4;
    const EQuestAlreadyCompleted: u64 = 5;
    const EQuestNotStarted: u64 = 6;
    const EQuestAlreadyStarted: u64 = 7;
    const EJourneyAlreadyCompleted: u64 = 8;
    const EJourneyNotCompleted: u64 = 9;
    const EInvalidRewardType: u64 = 10;

    // ======== Types =========

    struct QUEST has drop {}

    struct AdminCap has key, store {
        id: UID,
    }

    struct VerifierCap has key, store {
        id: UID,
    }

    struct SpaceHub has key {
        id: UID,
        /// The version of the hub
        version: u64,
        /// The amount of SUI that needs to be paid to create a journey
        fee_for_creating_journey: u64,
        /// The amount of SUI that needs to be paid to start a quest
        fee_for_start_quest: u64,
        /// The address of the verifier that receives the fee for starting a quest
        verifier_address: address,
        /// The balance of the hub
        balance: Balance<SUI>,
        /// The amount of spaces that can be created by a single address
        space_creators_allowlist: Table<address, u64>,
        /// The spaces that have been created
        spaces: TableVec<ID>
    }

    struct Space has key {
        id: UID,
        /// The version of the space
        version: u64,
        /// The name of the space
        name: String,
        /// The description of the space
        description: String,
        /// Link to the image of the space
        image_url: Url,
        /// Link to the website of the space
        website_url: Url,
        /// Link to the twitter of the space
        twitter_url: Url,
        /// The journeys that are part of the space
        journeys: ObjectTable<ID, Journey>,
        /// The amount of points that each user has earned in the space
        points: Table<address, u64>
    }

    struct SpaceAdminCap has key, store {
        id: UID,
        name: String,
        space_id: ID,
    }

    struct Journey has key, store {
        id: UID,
        /// Type of the reward that the user gets for completing the journey. NFT or Soulbound
        reward_type: u64,
        /// The amount of points that the user gets for completing the journey and claiming the reward
        reward_required_points: u64,
        /// Link to the image of the reward
        reward_image_url: Url,
        /// The name of the journey
        name: String,
        /// The description of the journey
        description: String,
        /// The time when the journey starts
        start_time: u64,
        /// The time when the journey ends
        end_time: u64,

        /// The amount of users that have completed the journey
        total_completed: u64,
        /// Quests that are part of the journey
        quests: ObjectTable<ID, Quest>,
        /// The addresses of the users that have completed the journey
        completed_users: Table<address, bool>,
        /// The amount of points that each user has earned in the journey
        users_points: Table<address, u64>,
        /// The amount of quests that each user has completed in the journey
        users_completed_quests: Table<address, u64>
    }

    struct Quest has key, store {
        id: UID,
        /// The amount of points that the user gets for completing the quest
        points_amount: u64,
        /// The name of the quest
        name: String,
        /// The description of the quest
        description: String,
        /// Link to information about the quest
        call_to_action_url: Url,
        /// The ID of the package that contains the function that needs to be executed
        package_id: ID,
        /// The name of the module that contains the function that needs to be executed
        module_name: String,
        /// The name of the function that needs to be executed
        function_name: String,
        /// The arguments that need to be passed to the function
        arguments: vector<String>,

        /// The amount of users that have completed the quest
        total_completed: u64,

        /// The addresses of the users that have completed the quest
        completed_users: Table<address, bool>
    }

    struct NftReward has key, store {
        id: UID,
        name: String,
        description: String,
        image_url: Url,
        space_id: ID,
        journey_id: ID,
        claimer: address,
    }

    struct SoulboundReward has key {
        id: UID,
        name: String,
        description: String,
        image_url: Url,
        space_id: ID,
        journey_id: ID,
        claimer: address,
    }

    // ======== Events =========

    struct SpaceCreated has copy, drop {
        space_id: ID,
    }

    struct JourneyCreated has copy, drop {
        space_id: ID,
        journey_id: ID,
    }

    struct JourneyRemoved has copy, drop {
        space_id: ID,
        journey_id: ID,
    }

    struct JourneyCompleted has copy, drop {
        space_id: ID,
        journey_id: ID,
        user: address,
    }

    struct QuestCreated has copy, drop {
        space_id: ID,
        journey_id: ID,
        quest_id: ID,
    }

    struct QuestRemoved has copy, drop {
        space_id: ID,
        journey_id: ID,
        quest_id: ID,
    }

    struct QuestCompleted has copy, drop {
        space_id: ID,
        journey_id: ID,
        quest_id: ID,
        user: address,
    }

    // ======== Functions =========

    fun init(otw: QUEST, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);

        // Reward display
        let reward_keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url"),
            utf8(b"project_url"),
        ];
        let reward_values = vector[
            utf8(b"{name}"),
            utf8(b"{description}"),
            utf8(b"{image_url}"),
            utf8(b"https://www.holasui.app")
        ];

        let nft_reward_display = display::new_with_fields<NftReward>(
            &publisher, *&reward_keys, *&reward_values, ctx
        );
        display::update_version(&mut nft_reward_display);

        let soulbound_reward_display = display::new_with_fields<SoulboundReward>(
            &publisher, *&reward_keys, *&reward_values, ctx
        );
        display::update_version(&mut soulbound_reward_display);

        public_transfer(publisher, sender(ctx));
        public_transfer(nft_reward_display, sender(ctx));
        public_transfer(soulbound_reward_display, sender(ctx));
        public_transfer(AdminCap {
            id: object::new(ctx),
        }, sender(ctx));
        public_transfer(VerifierCap {
            id: object::new(ctx),
        }, sender(ctx));
        share_object(SpaceHub {
            id: object::new(ctx),
            version: VERSION,
            fee_for_creating_journey: FEE_FOR_CREATING_JOURNEY,
            fee_for_start_quest: FEE_FOR_START_QUEST,
            verifier_address: VERIFIER,
            balance: balance::zero(),
            space_creators_allowlist: table::new(ctx),
            spaces: table_vec::empty<ID>(ctx),
        })
    }

    // ======== Admin functions =========

    public entry fun add_space_creator(
        _: &AdminCap,
        hub: &mut SpaceHub,
        creator: address,
        allowed_spaces_amount: u64
    ) {
        check_hub_version(hub);

        if (!table::contains(&hub.space_creators_allowlist, creator)) {
            table::add(&mut hub.space_creators_allowlist, creator, allowed_spaces_amount);
        } else {
            let current_allowed_spaces_amount = table::borrow_mut(&mut hub.space_creators_allowlist, creator);
            *current_allowed_spaces_amount = *current_allowed_spaces_amount + allowed_spaces_amount;
        }
    }

    entry fun update_fee_for_creating_journey(_: &AdminCap, hub: &mut SpaceHub, fee: u64) {
        check_hub_version(hub);

        hub.fee_for_creating_journey = fee;
    }

    entry fun update_fee_for_start_quest(_: &AdminCap, hub: &mut SpaceHub, fee: u64) {
        check_hub_version(hub);

        hub.fee_for_start_quest = fee;
    }

    entry fun update_verifier_address(_: &AdminCap, hub: &mut SpaceHub, verifier: address) {
        check_hub_version(hub);

        hub.verifier_address = verifier;
    }

    entry fun withdraw(_: &AdminCap, hub: &mut SpaceHub, ctx: &mut TxContext) {
        check_hub_version(hub);

        withdraw_balance(&mut hub.balance, ctx);
    }

    entry fun migrate_hub(_: &AdminCap, hub: &mut SpaceHub) {
        assert!(hub.version < VERSION, ENotUpgrade);

        hub.version = VERSION;
    }

    entry fun migrate_space(_: &AdminCap, space: &mut Space) {
        assert!(space.version < VERSION, ENotUpgrade);

        space.version = VERSION;
    }

    // ======== SpaceAdmin functions =========

    // ======== Space functions

    public fun create_space(
        hub: &mut SpaceHub,
        name: String,
        description: String,
        image_url: String,
        website_url: String,
        twitter_url: String,
        ctx: &mut TxContext
    ) {
        check_hub_version(hub);

        assert!(table::contains(&hub.space_creators_allowlist, sender(ctx)) &&
            *table::borrow(&hub.space_creators_allowlist, sender(ctx)) > 0,
            ENotSpaceCreator
        );

        let space = Space {
            id: object::new(ctx),
            version: VERSION,
            name,
            description,
            image_url: url::new_unsafe(string::to_ascii(image_url)),
            website_url: url::new_unsafe(string::to_ascii(website_url)),
            twitter_url: url::new_unsafe(string::to_ascii(twitter_url)),
            journeys: object_table::new(ctx),
            points: table::new(ctx)
        };

        let admin_cap = SpaceAdminCap {
            id: object::new(ctx),
            name: space.name,
            space_id: object::id(&space),
        };

        emit(SpaceCreated {
            space_id: object::uid_to_inner(&space.id)
        });

        let current_allowed_spaces_amount = table::borrow_mut(&mut hub.space_creators_allowlist, sender(ctx));
        *current_allowed_spaces_amount = *current_allowed_spaces_amount - 1;

        table_vec::push_back(&mut hub.spaces, object::id(&space));
        share_object(space);
        public_transfer(admin_cap, sender(ctx));
    }

    entry fun update_space_name(admin_cap: &SpaceAdminCap, space: &mut Space, name: String) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        space.name = name;
    }

    entry fun update_space_description(admin_cap: &SpaceAdminCap, space: &mut Space, description: String) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        space.description = description;
    }

    entry fun update_space_image_url(admin_cap: &SpaceAdminCap, space: &mut Space, image_url: String) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        space.image_url = url::new_unsafe(string::to_ascii(image_url));
    }

    entry fun update_space_website_url(admin_cap: &SpaceAdminCap, space: &mut Space, website_url: String) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        space.website_url = url::new_unsafe(string::to_ascii(website_url));
    }

    entry fun update_space_twitter_url(admin_cap: &SpaceAdminCap, space: &mut Space, twitter_url: String) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        space.twitter_url = url::new_unsafe(string::to_ascii(twitter_url));
    }

    // ======== Journey functions

    public fun create_journey(
        hub: &mut SpaceHub,
        coin: Coin<SUI>,
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        reward_type: u64,
        reward_image_url: String,
        reward_required_points: u64,
        name: String,
        description: String,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ): ID {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        assert!(reward_type == REWARD_TYPE_NFT || reward_type == REWARD_TYPE_SOULBOUND, EInvalidRewardType);

        handle_payment(&mut hub.balance, coin, hub.fee_for_creating_journey, ctx);

        let journey = Journey {
            id: object::new(ctx),
            reward_type,
            reward_required_points,
            reward_image_url: url::new_unsafe(string::to_ascii(reward_image_url)),
            name,
            description,
            start_time,
            end_time,
            total_completed: 0,
            quests: object_table::new(ctx),
            completed_users: table::new(ctx),
            users_points: table::new(ctx),
            users_completed_quests: table::new(ctx)
        };

        emit(JourneyCreated {
            space_id: object::uid_to_inner(&space.id),
            journey_id: object::uid_to_inner(&journey.id)
        });

        let id = object::id(&journey);
        object_table::add(&mut space.journeys, id, journey);
        id
    }

    public fun remove_journey(admin_cap: &SpaceAdminCap, space: &mut Space, journey_id: ID) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let Journey {
            id,
            reward_type: _,
            reward_required_points: _,
            reward_image_url: _,
            name: _,
            description: _,
            start_time: _,
            end_time: _,
            total_completed: _,
            quests,
            completed_users,
            users_points,
            users_completed_quests
        } = object_table::remove(&mut space.journeys, journey_id);

        emit(JourneyRemoved {
            space_id: object::uid_to_inner(&space.id),
            journey_id: object::uid_to_inner(&id)
        });

        object_table::destroy_empty(quests);
        table::drop(completed_users);
        table::drop(users_points);
        table::drop(users_completed_quests);
        object::delete(id)
    }

    entry fun update_journey_name(admin_cap: &SpaceAdminCap, space: &mut Space, journey_id: ID, name: String) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        journey.name = name;
    }

    entry fun update_journey_description(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        journey_id: ID,
        description: String
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        journey.description = description;
    }

    entry fun update_journey_reward_image_url(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        journey_id: ID,
        image_url: String
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        journey.reward_image_url = url::new_unsafe(string::to_ascii(image_url));
    }

    entry fun update_journey_start_time(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        journey_id: ID,
        start_time: u64
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);

        journey.start_time = start_time;
    }

    entry fun update_journey_end_time(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        journey_id: ID,
        end_time: u64
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);

        journey.end_time = end_time;
    }

    public fun create_quest(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        journey_id: ID,
        points_amount: u64,
        name: String,
        description: String,
        call_to_action_url: String,
        package_id: ID,
        module_name: String,
        function_name: String,
        arguments: vector<String>,
        ctx: &mut TxContext
    ): ID {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);

        let quest = Quest {
            id: object::new(ctx),
            total_completed: 0,
            points_amount,
            name,
            description,
            call_to_action_url: url::new_unsafe(string::to_ascii(call_to_action_url)),
            package_id,
            module_name,
            function_name,
            arguments,
            completed_users: table::new(ctx)
        };

        emit(QuestCreated {
            space_id: object::uid_to_inner(&space.id),
            journey_id,
            quest_id: object::uid_to_inner(&quest.id)
        });

        let id = object::id(&quest);
        object_table::add(&mut journey.quests, id, quest);
        id
    }

    public fun remove_quest(admin_cap: &SpaceAdminCap, space: &mut Space, journey_id: ID, quest_id: ID) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        let Quest {
            id,
            total_completed: _,
            points_amount: _,
            name: _,
            description: _,
            call_to_action_url: _,
            package_id: _,
            module_name: _,
            function_name: _,
            arguments: _,
            completed_users,
        } = object_table::remove(&mut journey.quests, quest_id);

        emit(QuestRemoved {
            space_id: object::uid_to_inner(&space.id),
            journey_id,
            quest_id: object::uid_to_inner(&id)
        });

        object::delete(id);
        table::drop(completed_users);
    }

    // ======== Verifier functions =========

    public fun complete_quest(
        _: &VerifierCap,
        space: &mut Space,
        journey_id: ID,
        quest_id: ID,
        user: address,
        clock: &Clock,
    ) {
        check_space_version(space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        assert!(
            clock::timestamp_ms(clock) >= journey.start_time && clock::timestamp_ms(clock) <= journey.end_time,
            EInvalidTime
        );

        let quest = object_table::borrow_mut(&mut journey.quests, quest_id);
        assert!(table::contains(&quest.completed_users, user), EQuestNotStarted);
        assert!(*table::borrow(&quest.completed_users, user) == false, EQuestAlreadyCompleted);

        emit(QuestCompleted {
            space_id: object::uid_to_inner(&space.id),
            journey_id,
            quest_id,
            user
        });

        quest.total_completed = quest.total_completed + 1;

        let completed = table::borrow_mut(&mut quest.completed_users, user);
        *completed = true;

        update_address_to_u64_table(&mut journey.users_points, user, quest.points_amount);
        update_address_to_u64_table(&mut journey.users_completed_quests, user, 1);
        update_address_to_u64_table(&mut space.points, user, quest.points_amount);
    }

    // ======== User functions =========

    public fun start_quest(
        hub: &mut SpaceHub,
        coin: Coin<SUI>,
        space: &mut Space,
        journey_id: ID,
        quest_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        check_space_version(space);

        handle_transfer(VERIFIER, coin, hub.fee_for_start_quest, ctx);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        assert!(
            clock::timestamp_ms(clock) >= journey.start_time && clock::timestamp_ms(clock) <= journey.end_time,
            EInvalidTime
        );

        let quest = object_table::borrow_mut(&mut journey.quests, quest_id);
        assert!(!table::contains(&quest.completed_users, sender(ctx)), EQuestAlreadyStarted);

        table::add(&mut quest.completed_users, sender(ctx), false);
    }

    public fun complete_journey(
        space: &mut Space,
        journey_id: ID,
        ctx: &mut TxContext
    ) {
        check_space_version(space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);

        assert!(!table::contains(&journey.completed_users, sender(ctx)), EJourneyAlreadyCompleted);
        assert!(table::contains(&journey.users_points, sender(ctx)), EJourneyNotCompleted);
        let address_points = *table::borrow(&journey.users_points, sender(ctx));
        assert!(address_points >= journey.reward_required_points, EJourneyNotCompleted);

        emit(JourneyCompleted {
            space_id: object::uid_to_inner(&space.id),
            journey_id,
            user: sender(ctx)
        });

        journey.total_completed = journey.total_completed + 1;
        table::add(&mut journey.completed_users, sender(ctx), true);


        if (journey.reward_type == REWARD_TYPE_NFT) {
            transfer(NftReward {
                id: object::new(ctx),
                name: journey.name,
                description: journey.description,
                image_url: journey.reward_image_url,
                space_id: object::id(space),
                journey_id,
                claimer: sender(ctx),
            }, sender(ctx));
        }
        else if (journey.reward_type == REWARD_TYPE_SOULBOUND) {
            transfer(SoulboundReward {
                id: object::new(ctx),
                name: journey.name,
                description: journey.description,
                image_url: journey.reward_image_url,
                space_id: object::id(space),
                journey_id,
                claimer: sender(ctx),
            }, sender(ctx));
        }
    }

    // ======== View functions =========

    // ======== View functions: SpaceHub

    public fun available_spaces_to_create(hub: &SpaceHub, user: address): u64 {
        if (table::contains(&hub.space_creators_allowlist, user)) {
            return *table::borrow(&hub.space_creators_allowlist, user)
        };
        0
    }

    public fun fee_for_creating_journey(hub: &SpaceHub): u64 {
        hub.fee_for_creating_journey
    }

    public fun fee_for_starting_quest(hub: &SpaceHub): u64 {
        hub.fee_for_start_quest
    }

    public fun verifier_address(hub: &SpaceHub): address {
        hub.verifier_address
    }

    public fun spaces(hub: &SpaceHub): &TableVec<ID> {
        &hub.spaces
    }

    // ======== View functions: Space

    public fun space(space: &Space): &Space {
        space
    }

    public fun space_name(space: &Space): String {
        space.name
    }

    public fun space_description(space: &Space): String {
        space.description
    }

    public fun space_image_url(space: &Space): Url {
        space.image_url
    }

    public fun space_website_url(space: &Space): Url {
        space.website_url
    }

    public fun space_twitter_url(space: &Space): Url {
        space.twitter_url
    }

    public fun space_journeys(space: &Space): &ObjectTable<ID, Journey> {
        &space.journeys
    }

    public fun space_points(space: &Space): &Table<address, u64> {
        &space.points
    }

    // ======== View functions: Journey

    public fun journey(space: &Space, journey_id: ID): &Journey {
        object_table::borrow(&space.journeys, journey_id)
    }

    public fun journey_reward_type(space: &Space, journey_id: ID): u64 {
        journey(space, journey_id).reward_type
    }

    public fun journey_reward_required_points(space: &Space, journey_id: ID): u64 {
        journey(space, journey_id).reward_required_points
    }

    public fun journey_reward_image_url(space: &Space, journey_id: ID): Url {
        journey(space, journey_id).reward_image_url
    }

    public fun journey_name(space: &Space, journey_id: ID): String {
        journey(space, journey_id).name
    }

    public fun journey_description(space: &Space, journey_id: ID): String {
        journey(space, journey_id).description
    }

    public fun journey_start_time(space: &Space, journey_id: ID): u64 {
        journey(space, journey_id).start_time
    }

    public fun journey_end_time(space: &Space, journey_id: ID): u64 {
        journey(space, journey_id).end_time
    }

    public fun journey_total_completed(space: &Space, journey_id: ID): u64 {
        journey(space, journey_id).total_completed
    }

    public fun journey_quests(space: &Space, journey_id: ID): &ObjectTable<ID, Quest> {
        &journey(space, journey_id).quests
    }

    public fun journey_completed_users(space: &Space, journey_id: ID): &Table<address, bool> {
        &journey(space, journey_id).completed_users
    }

    public fun journey_users_points(space: &Space, journey_id: ID): &Table<address, u64> {
        &journey(space, journey_id).users_points
    }

    public fun journey_users_completed_quests(space: &Space, journey_id: ID): &Table<address, u64> {
        &journey(space, journey_id).users_completed_quests
    }

    // ======== View functions: Quest

    public fun quest(space: &Space, journey_id: ID, quest_id: ID): &Quest {
        let journey = object_table::borrow(&space.journeys, journey_id);
        object_table::borrow(&journey.quests, quest_id)
    }

    public fun quest_points_amount(space: &Space, journey_id: ID, quest_id: ID): u64 {
        quest(space, journey_id, quest_id).points_amount
    }

    public fun quest_name(space: &Space, journey_id: ID, quest_id: ID): String {
        quest(space, journey_id, quest_id).name
    }

    public fun quest_description(space: &Space, journey_id: ID, quest_id: ID): String {
        quest(space, journey_id, quest_id).description
    }

    public fun quest_call_to_action_url(space: &Space, journey_id: ID, quest_id: ID): Url {
        quest(space, journey_id, quest_id).call_to_action_url
    }

    public fun quest_package_id(space: &Space, journey_id: ID, quest_id: ID): ID {
        quest(space, journey_id, quest_id).package_id
    }

    public fun quest_module_name(space: &Space, journey_id: ID, quest_id: ID): String {
        quest(space, journey_id, quest_id).module_name
    }

    public fun quest_function_name(space: &Space, journey_id: ID, quest_id: ID): String {
        quest(space, journey_id, quest_id).function_name
    }

    public fun quest_arguments(space: &Space, journey_id: ID, quest_id: ID): &vector<String> {
        &quest(space, journey_id, quest_id).arguments
    }

    public fun quest_total_completed(space: &Space, journey_id: ID, quest_id: ID): u64 {
        quest(space, journey_id, quest_id).total_completed
    }

    public fun quest_completed_users(space: &Space, journey_id: ID, quest_id: ID): &Table<address, bool> {
        &quest(space, journey_id, quest_id).completed_users
    }

    public fun quest_started_user(space: &Space, journey_id: ID, quest_id: ID, user: address): bool {
        table::contains(quest_completed_users(space, journey_id, quest_id), user)
    }

    public fun quest_completed_user(space: &Space, journey_id: ID, quest_id: ID, user: address): bool {
        let completed_users = quest_completed_users(space, journey_id, quest_id);
        if (table::contains(completed_users, user)) {
            return *table::borrow(completed_users, user)
        };
        false
    }

    // ======== Utility functions =========

    fun update_address_to_u64_table(table: &mut Table<address, u64>, address: address, amount: u64) {
        if (!table::contains(table, address)) {
            table::add(table, address, amount);
        } else {
            let current_points_amount = table::borrow_mut(table, address);
            *current_points_amount = *current_points_amount + amount;
        }
    }

    fun check_hub_version(hub: &SpaceHub) {
        assert!(hub.version == VERSION, EWrongVersion);
    }

    fun check_space_version(space: &Space) {
        assert!(space.version == VERSION, EWrongVersion);
    }

    fun check_space_admin(admin_cap: &SpaceAdminCap, space: &Space) {
        assert!(admin_cap.space_id == object::id(space), ENotSpaceAdmin);
    }

    // ======== Test functions =========
    #[test_only]
    public fun test_new_space_hub(ctx: &mut TxContext) {
        share_object(SpaceHub {
            id: object::new(ctx),
            version: VERSION,
            fee_for_creating_journey: FEE_FOR_CREATING_JOURNEY,
            fee_for_start_quest: FEE_FOR_START_QUEST,
            verifier_address: VERIFIER,
            balance: balance::zero(),
            space_creators_allowlist: table::new(ctx),
            spaces: table_vec::empty<ID>(ctx),
        })
    }

    #[test_only]
    public fun test_new_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap { id: object::new(ctx) }
    }

    #[test_only]
    public fun test_destroy_admin_cap(cap: AdminCap) {
        let AdminCap { id } = cap;
        object::delete(id)
    }

    #[test_only]
    public fun test_new_verifier_cap(ctx: &mut TxContext): VerifierCap {
        VerifierCap { id: object::new(ctx) }
    }

    #[test_only]
    public fun test_destroy_verifier_cap(cap: VerifierCap) {
        let VerifierCap { id } = cap;
        object::delete(id)
    }
}
