// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module pump_rooch::vec_set {

    use std::option;
    use std::option::{Option, is_some, destroy_some};
    use std::vector;
    use std::vector::{reverse, push_back, length, pop_back};

    /// This key already exists in the map
    const ErrorKeyAlreadyExists: u64 = 0;

    /// This key does not exist in the map
    const ErrorKeyDoesNotExist: u64 = 1;

    /// A set data structure backed by a vector. The set is guaranteed not to
    /// contain duplicate keys. All operations are O(N) in the size of the set
    /// - the intention of this data structure is only to provide the convenience
    /// of programming against a set API. Sets that need sorted iteration rather
    /// than insertion order iteration should be handwritten.
    struct VecSet<K: copy + drop> has copy, drop, store {
        contents: vector<K>,
    }

    /// Create an empty `VecSet`
    public fun empty<K: copy + drop>(): VecSet<K> {
        VecSet { contents: vector[] }
    }

    /// Create a singleton `VecSet` that only contains one element.
    public fun singleton<K: copy + drop>(key: K): VecSet<K> {
        VecSet { contents: vector[key] }
    }

    /// Insert a `key` into self.
    /// Aborts if `key` is already present in `self`.
    public fun insert<K: copy + drop>(self: &mut VecSet<K>, key: K) {
        assert!(!contains(self, &key), ErrorKeyAlreadyExists);
        push_back(&mut self.contents, key)
    }

    /// Remove the entry `key` from self. Aborts if `key` is not present in `self`.
    public fun remove<K: copy + drop>(self: &mut VecSet<K>, key: &K) {
        let idx = get_idx(self, key);
        vector::remove(&mut self.contents, idx);
    }

    /// Return true if `self` contains an entry for `key`, false otherwise
    public fun contains<K: copy + drop>(self: &VecSet<K>, key: &K): bool {
        is_some(&get_idx_opt(self, key))
    }

    /// Return the number of entries in `self`
    public fun size<K: copy + drop>(self: &VecSet<K>): u64 {
        length(&self.contents)
    }

    /// Return true if `self` has 0 elements, false otherwise
    public fun is_empty<K: copy + drop>(self: &VecSet<K>): bool {
        size(self) == 0
    }

    /// Unpack `self` into vectors of keys.
    /// The output keys are stored in insertion order, *not* sorted.
    public fun into_keys<K: copy + drop>(self: VecSet<K>): vector<K> {
        let VecSet { contents } = self;
        contents
    }

    /// Construct a new `VecSet` from a vector of keys.
    /// The keys are stored in insertion order (the original `keys` ordering)
    /// and are *not* sorted.
    public fun from_keys<K: copy + drop>(keys: vector<K>): VecSet<K> {
        reverse(&mut keys);
        let set = empty();
        while (!vector::is_empty(&keys)) insert(&mut set, pop_back(&mut keys));
        set
    }

    /// Borrow the `contents` of the `VecSet` to access content by index
    /// without unpacking. The contents are stored in insertion order,
    /// *not* sorted.
    public fun keys<K: copy + drop>(self: &VecSet<K>): &vector<K> {
        &self.contents
    }

    // == Helper functions ==

    /// Find the index of `key` in `self`. Return `None` if `key` is not in `self`.
    /// Note that keys are stored in insertion order, *not* sorted.
    fun get_idx_opt<K: copy + drop>(self: &VecSet<K>, key: &K): Option<u64> {
        let i = 0;
        let n = size(self);
        while (i < n) {
        if (vector::borrow(&self.contents, i) == key) {
        return option::some(i)
        };
        i = i + 1;
        };
        option::none()
    }

    /// Find the index of `key` in `self`. Aborts if `key` is not in `self`.
    /// Note that map entries are stored in insertion order, *not* sorted.
    fun get_idx<K: copy + drop>(self: &VecSet<K>, key: &K): u64 {
        let idx_opt = get_idx_opt(self, key);
        assert!(is_some(&idx_opt), ErrorKeyDoesNotExist);
        destroy_some(idx_opt)
    }
}
