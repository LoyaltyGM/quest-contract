#[test_only]
module holasui_quest::quest_test {
    use std::debug::print;
    use std::string::utf8;
    use sui::clock::{Self, Clock};
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_scenario as ts;

    use holasui_quest::quest::{Self};

    const ADMIN: address = @0xA11CE;
    const USER: address = @0x923E;

    #[test]
    fun add_space_creator(){
        let spaces_amount = 10;
        
        let test = ts::begin(ADMIN);

        quest::test_new_space_hub(ts::ctx(&mut test));
        ts::next_tx(&mut test, ADMIN);

        let admin_cap = quest::test_new_admin_cap(ts::ctx(&mut test));
        let hub=  ts::take_shared<quest::SpaceHub>(&test);

        quest::add_space_creator(&admin_cap, &mut hub, USER, spaces_amount);

        assert!(quest::get_available_spaces(&hub, USER) == spaces_amount, 0);

        quest::test_destroy_admin_cap(admin_cap);
        ts::return_shared(hub);
        ts::end(test);
    }

}
