#[test_only]
module holasui_quest::quest_test {
    use std::string::utf8;

    use sui::coin;
    use sui::object::ID;
    use sui::object_table;
    use sui::sui::SUI;
    use sui::test_scenario as ts;
    use sui::test_scenario::Scenario;

    use holasui_quest::quest::{Self, Space, SpaceAdminCap, SpaceHub};

    const ADMIN: address = @0xA11CE;
    const CREATOR: address = @0x923E;
    const USER: address = @0x228E;

    #[test]
    fun add_space_creator() {
        let spaces_amount = 10;

        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let admin_cap = quest::test_new_admin_cap(ts::ctx(&mut test));
        let hub = ts::take_shared<quest::SpaceHub>(&test);

        quest::add_space_creator(&admin_cap, &mut hub, CREATOR, spaces_amount);

        assert!(quest::available_spaces_to_create(&hub, CREATOR) == spaces_amount, 0);

        quest::test_destroy_admin_cap(admin_cap);
        ts::return_shared(hub);
        ts::end(test);
    }

    #[test]
    fun create_space_by_creator() {
        let spaces_amount = 10;

        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let admin_cap = quest::test_new_admin_cap(ts::ctx(&mut test));
        let hub = ts::take_shared<quest::SpaceHub>(&test);

        quest::add_space_creator(&admin_cap, &mut hub, CREATOR, spaces_amount);

        assert!(quest::available_spaces_to_create(&hub, CREATOR) == spaces_amount, 0);

        create_space(&mut test, &mut hub);

        assert!(quest::available_spaces_to_create(&hub, CREATOR) == spaces_amount - 1, 0);

        quest::test_destroy_admin_cap(admin_cap);
        ts::return_shared(hub);
        ts::end(test);
    }

    #[test]
    #[expected_failure(abort_code = quest::ENotSpaceCreator)]
    fun create_space_by_not_creator() {
        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let hub = ts::take_shared<quest::SpaceHub>(&test);

        assert!(quest::available_spaces_to_create(&hub, CREATOR) == 0, 0);

        create_space(&mut test, &mut hub);

        ts::return_shared(hub);
        ts::end(test);
    }

    #[test]
    fun create_journey_by_creator() {
        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let admin_cap = quest::test_new_admin_cap(ts::ctx(&mut test));
        let hub = ts::take_shared<quest::SpaceHub>(&test);

        quest::add_space_creator(&admin_cap, &mut hub, CREATOR, 1);

        create_space(&mut test, &mut hub);

        ts::next_tx(&mut test, CREATOR);

        let space = ts::take_shared<Space>(&test);
        let space_admin_cap = ts::take_from_sender<SpaceAdminCap>(&test);

        create_journey(&mut test, &mut hub, &mut space, &mut space_admin_cap);

        assert!(object_table::length(quest::space_journeys(&space)) == 1, 0);

        quest::test_destroy_admin_cap(admin_cap);
        ts::return_shared(hub);
        ts::return_shared(space);
        ts::return_to_sender(&test, space_admin_cap);
        ts::end(test);
    }

    // ====== Utility functions ======

    fun create_space(scenario: &mut Scenario, hub: &mut SpaceHub) {
        ts::next_tx(scenario, CREATOR);

        quest::create_space(hub,
            utf8(b"Space"),
            utf8(b"Space description"),
            utf8(b"ipfs://space"),
            utf8(b"https://space.com"),
            utf8(b"https://x.com/space"),
            ts::ctx(scenario),
        );
    }

    fun create_journey(
        scenario: &mut Scenario,
        hub: &mut SpaceHub,
        space: &mut Space,
        space_admin_cap: &mut SpaceAdminCap,
    ): ID {
        ts::next_tx(scenario, CREATOR);

        let coin = coin::mint_for_testing<SUI>(
            quest::fee_for_creating_journey(hub),
            ts::ctx(scenario)
        );

        quest::create_journey(
            hub,
            coin,
            space_admin_cap,
            space,
            1,
            utf8(b"ipfs://reward"),
            100,
            utf8(b"Journey"),
            utf8(b"Journey description"),
            100,
            200,
            ts::ctx(scenario),
        )
    }
}
