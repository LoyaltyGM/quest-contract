#[test_only]
module holasui_quest::quest_test {
    use std::string::utf8;

    use sui::coin;
    use sui::object_table;
    use sui::sui::SUI;
    use sui::test_scenario as ts;

    use holasui_quest::quest::{Self, Space, SpaceAdminCap};

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
    fun create_space() {
        let spaces_amount = 10;

        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let admin_cap = quest::test_new_admin_cap(ts::ctx(&mut test));
        let hub = ts::take_shared<quest::SpaceHub>(&test);

        quest::add_space_creator(&admin_cap, &mut hub, CREATOR, spaces_amount);

        assert!(quest::available_spaces_to_create(&hub, CREATOR) == spaces_amount, 0);

        ts::next_tx(&mut test, CREATOR);

        quest::create_space(&mut hub,
            utf8(b"Space"),
            utf8(b"Space description"),
            utf8(b"ipfs://space"),
            utf8(b"https://space.com"),
            utf8(b"https://x.com/space"),
            ts::ctx(&mut test),
        );

        assert!(quest::available_spaces_to_create(&hub, CREATOR) == spaces_amount - 1, 0);

        quest::test_destroy_admin_cap(admin_cap);
        ts::return_shared(hub);
        ts::end(test);
    }

    #[test]
    #[expected_failure(abort_code = quest::ENotSpaceCreator)]
    fun create_space_not_creator() {
        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let hub = ts::take_shared<quest::SpaceHub>(&test);

        assert!(quest::available_spaces_to_create(&hub, CREATOR) == 0, 0);

        ts::next_tx(&mut test, CREATOR);

        quest::create_space(&mut hub,
            utf8(b"Space"),
            utf8(b"Space description"),
            utf8(b"ipfs://space"),
            utf8(b"https://space.com"),
            utf8(b"https://x.com/space"),
            ts::ctx(&mut test),
        );

        ts::return_shared(hub);
        ts::end(test);
    }

    #[test]
    fun create_journey() {
        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let admin_cap = quest::test_new_admin_cap(ts::ctx(&mut test));
        let hub = ts::take_shared<quest::SpaceHub>(&test);

        quest::add_space_creator(&admin_cap, &mut hub, CREATOR, 1);

        ts::next_tx(&mut test, CREATOR);

        quest::create_space(&mut hub,
            utf8(b"Space"),
            utf8(b"Space description"),
            utf8(b"ipfs://space"),
            utf8(b"https://space.com"),
            utf8(b"https://x.com/space"),
            ts::ctx(&mut test),
        );

        ts::next_tx(&mut test, CREATOR);

        let space = ts::take_shared<Space>(&test);
        let space_admin_cap = ts::take_from_sender<SpaceAdminCap>(&test);

        let coin_to_pay = coin::mint_for_testing<SUI>(
            quest::fee_for_creating_journey(&hub),
            ts::ctx(&mut test)
        );

        quest::create_journey(
            &mut hub,
            coin_to_pay,
            &space_admin_cap,
            &mut space,
            1,
            utf8(b"ipfs://reward"),
            100,
            utf8(b"Journey"),
            utf8(b"Journey description"),
            100,
            200,
            ts::ctx(&mut test),
        );

        assert!(object_table::length(quest::space_journeys(&space)) == 1, 0);

        quest::test_destroy_admin_cap(admin_cap);
        ts::return_shared(hub);
        ts::return_shared(space);
        ts::return_to_sender(&test, space_admin_cap);
        ts::end(test);
    }
}
