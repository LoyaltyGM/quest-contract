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
    const ECampaignAlreadyDone: u64 = 7;


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
        fee_for_creating_campaign: u64,
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
        campaigns: ObjectTable<ID, Campaign>,
    }

    struct SpaceAdminCap has key, store {
        id: UID,
        name: String,
        space_id: ID,
    }

    struct Campaign has key, store {
        id: UID,
        name: String,
        description: String,
        reward_image_url: Url,
        start_time: u64,
        end_time: u64,
        quests: ObjectTable<ID, Quest>,
        done: Table<address, bool>
    }

    struct Quest has key, store {
        id: UID,
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
        campaign_id: ID,
    }

    // ======== Events =========

    struct QuestDone has copy, drop {
        space_id: ID,
        campaign_id: ID,
        quest_id: ID,
    }

    struct CampaignDone has copy, drop {
        space_id: ID,
        campaign_id: ID,
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
            fee_for_creating_campaign: FEE_FOR_CREATING_CAMPAIGN,
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

    entry fun update_fee_for_creating_campaign(_: &AdminCap, hub: &mut SpaceHub, fee: u64) {
        check_hub_version(hub);

        hub.fee_for_creating_campaign = fee;
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
            campaigns: object_table::new(ctx),
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

    // ======== Campaign functions

    entry fun create_campaign(
        hub: &mut SpaceHub,
        coin: Coin<SUI>,
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        name: String,
        description: String,
        image_url: String,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        handle_payment(&mut hub.balance, coin, hub.fee_for_creating_campaign, ctx);

        let campaign = Campaign {
            id: object::new(ctx),
            name,
            description,
            reward_image_url: url::new_unsafe(string::to_ascii(image_url)),
            start_time,
            end_time,
            quests: object_table::new(ctx),
            done: table::new(ctx)
        };

        object_table::add(&mut space.campaigns, object::id(&campaign), campaign);
    }

    entry fun remove_campaign(admin_cap: &SpaceAdminCap, space: &mut Space, campaign_id: ID) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let Campaign {
            id,
            name: _,
            description: _,
            reward_image_url: _,
            start_time: _,
            end_time: _,
            quests,
            done
        } = object_table::remove(&mut space.campaigns, campaign_id);

        object_table::destroy_empty(quests);
        table::drop(done);
        object::delete(id)
    }

    entry fun update_campaign_name(admin_cap: &SpaceAdminCap, space: &mut Space, campaign_id: ID, name: String) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);
        campaign.name = name;
    }

    entry fun update_campaign_description(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        campaign_id: ID,
        description: String
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);
        campaign.description = description;
    }

    entry fun update_campaign_reward_image_url(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        campaign_id: ID,
        image_url: String
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);
        campaign.reward_image_url = url::new_unsafe(string::to_ascii(image_url));
    }

    entry fun update_campaign_end_time(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        campaign_id: ID,
        end_time: u64
    ) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);

        campaign.end_time = end_time;
    }

    entry fun create_quest(
        admin_cap: &SpaceAdminCap,
        space: &mut Space,
        campaign_id: ID,
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

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);

        // todo: add event for quest creation
        let quest = Quest {
            id: object::new(ctx),
            name,
            description,
            call_to_action_url: url::new_unsafe(string::to_ascii(call_to_action_url)),
            package_id,
            module_name,
            function_name,
            arguments,
            done: table::new(ctx)
        };

        object_table::add(&mut campaign.quests, object::id(&quest), quest);
    }

    entry fun remove_quest(admin_cap: &SpaceAdminCap, space: &mut Space, campaign_id: ID, quest_id: ID) {
        check_space_version(space);
        check_space_admin(admin_cap, space);

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);
        let Quest {
            id,
            name: _,
            description: _,
            call_to_action_url: _,
            package_id: _,
            module_name: _,
            function_name: _,
            arguments: _,
            done,
        } = object_table::remove(&mut campaign.quests, quest_id);

        object::delete(id);
        table::drop(done);
    }

    // ======== Verifier functions =========

    entry fun verify_campaign_quest(
        _: &Verifier,
        space: &mut Space,
        campaign_id: ID,
        quest_id: ID,
        user: address,
        clock: &Clock,
    ) {
        check_space_version(space);

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);
        assert!(clock::timestamp_ms(clock) >= campaign.start_time, EInvalidTime);
        assert!(clock::timestamp_ms(clock) <= campaign.end_time, EInvalidTime);

        let quest = object_table::borrow_mut(&mut campaign.quests, quest_id);
        assert!(!table::contains(&quest.done, user), EQuestAlreadyDone);

        emit(QuestDone {
            space_id: object::uid_to_inner(&space.id),
            campaign_id,
            quest_id
        });

        table::add(&mut quest.done, user, true);
    }

    // ======== User functions =========

    entry fun claim_campaign_reward(
        space: &mut Space,
        campaign_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        check_space_version(space);

        let campaign = object_table::borrow_mut(&mut space.campaigns, campaign_id);

        assert!(clock::timestamp_ms(clock) <= campaign.end_time, EInvalidTime);
        assert!(!table::contains(&campaign.done, sender(ctx)), ECampaignAlreadyDone);
        check_campaign_quests_done(campaign, sender(ctx));

        emit(CampaignDone {
            space_id: object::uid_to_inner(&space.id),
            campaign_id
        });

        table::add(&mut campaign.done, sender(ctx), true);
        transfer(Reward {
            id: object::new(ctx),
            name: campaign.name,
            description: campaign.description,
            image_url: campaign.reward_image_url,
            space_id: object::id(space),
            campaign_id
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

    // todo: change way to check if all quests are done
    fun check_campaign_quests_done(campaign: &Campaign, address: address) {
        let quests = &campaign.quests;

        let i = 0;
        // while (i < vector::length(quests)) {
        //     let quest = vector::borrow(quests, i);
        //     assert!(table::contains(&quest.done, address), EQuestNotDone);
        //     i = i + 1;
        // }
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
