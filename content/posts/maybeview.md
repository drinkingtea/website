---
title: "MaybeView"
author: Gary Talent
description: "Avoiding Unnecessary Temporaries"
categories: ["Tech", "Programming"]
images:
- /dt-logo.png
tags: ["cpp", "programming", "string", "MaybeView", "Ox", "hash map", "vector"]
date: 2024-04-24
showtoc: false
---

Note: this is based on the version of Ox in following revision in the
[Nostalgia repo](https://git.drinkingtea.net/drinkingtea/nostalgia):
[1b629da8fc658a85f07b5209f2791a5ebdf79fa1](https://git.drinkingtea.net/drinkingtea/nostalgia/src/commit/1b629da8fc658a85f07b5209f2791a5ebdf79fa1)

## Problem

In C++, hash maps are often used with strings as keys.
This would typically look something like this.

```cpp
std::unordered_map<std::string, int> ages;
ages["Jerry Smith"] = 54;
```

And here is an example of a lookup:
```cpp
int age = ages["Jerry Smith"];
```

There is a hidden inefficiency here.
The lookup operator does not take a ```std::string_view``` or a C string.
The lookup operator takes a ```std::string```.
That means, even though we are passing in a C string that has all the necessary
data, we are implicitly calling the ```std::string``` constructor, which will
allocate space on the heap for the string data, then copy the existing C string
into the buffer it allocated.
Then, as soon as the lookup call is finished, the temporary ```std::string```
is destroyed.


We usually use ```std::string_view``` to avoid this, but the
```std::unordered_map``` lookup operator (and other functions that take the
key) naively uses the key type parameter for lookups.

## Solution: MaybeView

Unfortunately, we really cannot fix ```std::unordered_map``` without amending
the C++ standard.
However, we can fix ```ox::HashMap```.

This is where ```ox::MaybeView``` comes in.

```cpp
// these are actually spread out across a few different files in Ox

template<typename T>
struct MaybeView {
	using type = T;
};

template<typename T>
using MaybeView_t = typename MaybeView<T>::type;

template<size_t sz>
struct MaybeView<ox::IString<sz>> {
	using type = ox::StringView;
};

template<size_t sz>
struct MaybeView<ox::BasicString<sz>> {
	using type = ox::StringView;
};

```

```ox::MaybeView_t``` allows us to easily get the view form of certain types,
while simply using the actual type passed in for types that do not have
corresponding view types.
This would mean that ```ox::MaybeView_t<int>``` would evaluate to ```int```,
and ```ox::MaybeView_t<ox::String>``` would evaluate to ```ox::StringView```.

```ox::HashMap``` uses ```ox::MaybeView_t``` as so:

```cpp
template<typename K, typename T>
class HashMap {
    // note: many HashMap members have been removed from this excerpt for the
    // sake of brevity

	public:
		constexpr T &operator[](MaybeView_t<K> const&key);

		constexpr Result<T*> at(MaybeView_t<K> const&key) noexcept;

		constexpr Result<const T*> at(MaybeView_t<K> const&key) const noexcept;

		constexpr void erase(MaybeView_t<K> const&key);

		[[nodiscard]]
		constexpr bool contains(MaybeView_t<K> const&key) const noexcept;

};
```

```ox::Vector``` similarly takes advantage of ```ox::MaybeView_t``` for its ```contains``` function:

```cpp
template<
    typename T, std::size_t SmallVectorSize = 0,
    typename Allocator = std::allocator<T>>
class Vector: detail::VectorAllocator<T, Allocator, SmallVectorSize> {

	public:
		[[nodiscard]]
		constexpr bool contains(MaybeView_t<T> const&) const noexcept;

};
```
