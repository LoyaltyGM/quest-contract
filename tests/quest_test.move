#[test_only]
module holasui_quest::quest_test {
    use std::string::utf8;

    use sui::test_scenario as ts;

    use holasui_quest::quest::Self;

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
}
