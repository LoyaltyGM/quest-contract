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

    use holasui_quest::utils::{handle_payment, withdraw_balance};

    // ======== Constants =========

    const VERSION: u64 = 1;
    const FEE_FOR_CREATING_CAMPAIGN: u64 = 1000000000;

    // ======== Errors =========

    const EWrongVersion: u64 = 0;
    const ENotUpgrade: u64 = 1;
    const ENotSpaceCreator: u64 = 2;
    const ENotSpaceAdmin: u64 = 3;
    const EInvalidTime: u64 = 4;
    const EQuestAlreadyDone: u64 = 5;
    const EQuestNotDone: u64 = 6;
    const EJourneyAlreadyDone: u64 = 7;
    const EJourneyNotDone: u64 = 8;


    // ======== Types =========

    struct QUEST has drop {}

    struct AdminCap has key, store {
        id: UID,
    }

    struct Verifier has key, store {
        id: UID,
    }

    struct SpaceHub has key {
        id: UID,
        version: u64,
        balance: Balance<SUI>,
        fee_for_creating_journey: u64,
        /// The amount of spaces that can be created by a single address
        space_creators_allowlist: Table<address, u64>,
        spaces: TableVec<ID>
    }

    struct Space has key {
        id: UID,
        version: u64,
        name: String,
        description: String,
        image_url: Url,
        website_url: Url,
        twitter_url: Url,
        journeys: ObjectTable<ID, Journey>,
        points: Table<address, u64>
    }

    struct SpaceAdminCap has key, store {
        id: UID,
        name: String,
        space_id: ID,
    }

    // todo: add field total_completed
    // todo: add completed quests per user
    struct Journey has key, store {
        id: UID,
        name: String,
        description: String,
        start_time: u64,
        end_time: u64,
        reward_image_url: Url,
        reward_points: u64,
        quests: ObjectTable<ID, Quest>,
        done: Table<address, bool>,
        points: Table<address, u64>
    }

    // todo: add field total_completed
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

        done: Table<address, bool>
    }

    struct Reward has key, store {
        id: UID,
        name: String,
        description: String,
        image_url: Url,
        space_id: ID,
        journey_id: ID,
    }

    // ======== Events =========

    struct JourneyCreated has copy, drop {
        space_id: ID,
        journey_id: ID,
    }

    struct JourneyRemoved has copy, drop {
        space_id: ID,
        journey_id: ID,
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

    struct QuestVerified has copy, drop {
        space_id: ID,
        journey_id: ID,
        quest_id: ID,
    }

    struct JourneyDone has copy, drop {
        space_id: ID,
        journey_id: ID,
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
        let reward_display = display::new_with_fields<Reward>(
            &publisher, reward_keys, reward_values, ctx
        );
        display::update_version(&mut reward_display);

        public_transfer(publisher, sender(ctx));
        public_transfer(reward_display, sender(ctx));
        public_transfer(AdminCap {
            id: object::new(ctx),
        }, sender(ctx));
        public_transfer(Verifier {
            id: object::new(ctx),
        }, sender(ctx));
        share_object(SpaceHub {
            id: object::new(ctx),
            version: VERSION,
            balance: balance::zero(),
            fee_for_creating_journey: FEE_FOR_CREATING_CAMPAIGN,
            space_creators_allowlist: table::new(ctx),
            spaces: table_vec::empty<ID>(ctx),
        })
    }

    // ======== Admin functions =========

    entry fun add_space_creator(
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
            *current_allowed_spaces_amount = allowed_spaces_amount;
        }
    }

    entry fun update_fee_for_creating_journey(_: &AdminCap, hub: &mut SpaceHub, fee: u64) {
        check_hub_version(hub);

        hub.fee_for_creating_journey = fee;
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

    entry fun create_space(
        hub: &mut SpaceHub,
        name: String,
        description: String,
        image_url: String,
        website_url: String,
        twitter_url: String,
        ctx: &mut TxContext
    ) {
        check_hub_version(hub);
        handle_space_create(hub, sender(ctx));

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

    entry fun create_journey(
        hub: &mut SpaceHub,
        coin: Coin<SUI>,
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        name: String,
        description: String,
        start_time: u64,
        end_time: u64,
        reward_image_url: String,
        reward_points: u64,
        ctx: &mut TxContext
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        handle_payment(&mut hub.balance, coin, hub.fee_for_creating_journey, ctx);

        let journey = Journey {
            id: object::new(ctx),
            name,
            description,
            start_time,
            end_time,
            reward_image_url: url::new_unsafe(string::to_ascii(reward_image_url)),
            reward_points,
            quests: object_table::new(ctx),
            done: table::new(ctx),
            points: table::new(ctx)
        };

        emit(JourneyCreated {
            space_id: object::uid_to_inner(&space.id),
            journey_id: object::uid_to_inner(&journey.id)
        });

        object_table::add(&mut space.journeys, object::id(&journey), journey);
    }

    entry fun remove_journey(admin_cap: &SpaceAdminCap, space: &mut Space, journey_id: ID) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let Journey {
            id,
            name: _,
            description: _,
            start_time: _,
            end_time: _,
            reward_image_url: _,
            reward_points: _,
            quests,
            done,
            points,
        } = object_table::remove(&mut space.journeys, journey_id);

        emit(JourneyRemoved {
            space_id: object::uid_to_inner(&space.id),
            journey_id: object::uid_to_inner(&id)
        });

        object_table::destroy_empty(quests);
        table::drop(done);
        table::drop(points);
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

    entry fun create_quest(
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
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);

        let quest = Quest {
            id: object::new(ctx),
            points_amount,
            name,
            description,
            call_to_action_url: url::new_unsafe(string::to_ascii(call_to_action_url)),
            package_id,
            module_name,
            function_name,
            arguments,
            done: table::new(ctx)
        };

        emit(QuestCreated {
            space_id: object::uid_to_inner(&space.id),
            journey_id,
            quest_id: object::uid_to_inner(&quest.id)
        });

        object_table::add(&mut journey.quests, object::id(&quest), quest);
    }

    entry fun remove_quest(admin_cap: &SpaceAdminCap, space: &mut Space, journey_id: ID, quest_id: ID) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        let Quest {
            id,
            name: _,
            description: _,
            call_to_action_url: _,
            package_id: _,
            module_name: _,
            function_name: _,
            arguments: _,
            points_amount: _,
            done,
        } = object_table::remove(&mut journey.quests, quest_id);

        emit(QuestRemoved {
            space_id: object::uid_to_inner(&space.id),
            journey_id,
            quest_id: object::uid_to_inner(&id)
        });

        object::delete(id);
        table::drop(done);
    }

    // ======== Verifier functions =========

    entry fun verify_quest(
        _: &Verifier,
        space: &mut Space,
        journey_id: ID,
        quest_id: ID,
        user: address,
        clock: &Clock,
    ) {
        check_space_version(space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);
        assert!(clock::timestamp_ms(clock) >= journey.start_time, EInvalidTime);
        assert!(clock::timestamp_ms(clock) <= journey.end_time, EInvalidTime);

        let quest = object_table::borrow_mut(&mut journey.quests, quest_id);
        assert!(!table::contains(&quest.done, user), EQuestAlreadyDone);

        emit(QuestVerified {
            space_id: object::uid_to_inner(&space.id),
            journey_id,
            quest_id
        });

        table::add(&mut quest.done, user, true);
        update_points_table(&mut journey.points, user, quest.points_amount);
        update_points_table(&mut space.points, user, quest.points_amount);
    }

    // ======== User functions =========

    entry fun claim_reward(
        space: &mut Space,
        journey_id: ID,
        ctx: &mut TxContext
    ) {
        check_space_version(space);

        let journey = object_table::borrow_mut(&mut space.journeys, journey_id);

        assert!(!table::contains(&journey.done, sender(ctx)), EJourneyAlreadyDone);
        let address_points = *table::borrow(&journey.points, sender(ctx));
        assert!(address_points >= journey.reward_points, EJourneyNotDone);

        emit(JourneyDone {
            space_id: object::uid_to_inner(&space.id),
            journey_id
        });

        table::add(&mut journey.done, sender(ctx), true);
        transfer(Reward {
            id: object::new(ctx),
            name: journey.name,
            description: journey.description,
            image_url: journey.reward_image_url,
            space_id: object::id(space),
            journey_id
        }, sender(ctx));
    }


    // ======== Utility functions =========

    fun handle_space_create(hub: &mut SpaceHub, creator: address) {
        assert!(table::contains(&hub.space_creators_allowlist, creator) &&
            *table::borrow(&hub.space_creators_allowlist, creator) > 0,
            ENotSpaceCreator
        );

        let current_allowed_spaces_amount = table::borrow_mut(&mut hub.space_creators_allowlist, creator);
        *current_allowed_spaces_amount = *current_allowed_spaces_amount - 1;
    }

    fun update_points_table(points: &mut Table<address, u64>, address: address, points_amount: u64) {
        if (!table::contains(points, address)) {
            table::add(points, address, points_amount);
        } else {
            let current_points_amount = table::borrow_mut(points, address);
            *current_points_amount = *current_points_amount + points_amount;
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
}
