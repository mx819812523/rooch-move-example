module pump_rooch::comment {
    use std::option::Option;
    use std::string::{String, utf8};
    use moveos_std::timestamp::now_milliseconds;
    use pump_rooch::vec_set;
    use moveos_std::tx_context::sender;
    use pump_rooch::vec_set::VecSet;
    use moveos_std::object::{ObjectID};

    struct Comment has key, store {
        reply: Option<ObjectID>,
        creator: address,
        media_link: String,
        content: String,
        timestamp: u64,
        likes: VecSet<address>,
    }

    public fun new_comment(
        reply: Option<ObjectID>,
        media_link: vector<u8>,
        content: vector<u8>,
    ): Comment {
        Comment {
            reply,
            creator: sender(),
            media_link: utf8(media_link),
            content: utf8(content),
            timestamp: now_milliseconds(),
            likes: vec_set::empty<address>(),
        }
    }

    public fun drop_comment(comment: Comment) {
        let Comment {
            reply: _,
            creator: _,
            media_link: _,
            content: _,
            timestamp: _,
            likes: _,
        } = comment;
    }

    public fun like_comment(comment: &mut Comment) {
        vec_set::insert<address>(&mut comment.likes, sender());
    }

    public fun unlike_comment(comment: &mut Comment) {
        vec_set::remove<address>(&mut comment.likes, &sender());
    }

    public fun like_count(comment: &Comment): u64 {
        vec_set::size(&comment.likes)
    }
}