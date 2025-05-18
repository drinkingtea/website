---
title: "Ox Preloader"
author: Gary Talent
description: "Using ROM as RAM"
categories: ["Tech", "Programming"]
images:
- /dt-logo.png
tags: ["cpp", "programming", "serialization", "nostalgia", "ox", "preloader", "preloading"]
date: 2023-02-27
showtoc: true
---

Note: While this was originally published on 2023-02-27, it was updated to
reflect later changes to the codebase on 2025-05-18.

Note: this is based on the following revision in the [Nostalgia repo](https://git.drinkingtea.net/drinkingtea/nostalgia):
[d6e4ab7a24a0a4b035c6578dfa30ef35170b5a01](https://git.drinkingtea.net/drinkingtea/nostalgia/src/commit/d6e4ab7a24a0a4b035c6578dfa30ef35170b5a01)

This might be the most insane piece of software I have ever written.
That's probably mostly because I have never heard such a system as this, which
should usually be a deterrent when you think you have come up with a brilliant
new idea.
But questions of whether or not I *should* proceed with this idea never stood a
chance against my firm conviction that it *could* be done.
Those questions were in fact mercilessly slaughtered by my unrelenting will to
make this beautiful abomination a reality.

## About
The GBA, compared to your PC or phone, has an absolutely paltry amount of
memory.
The whole system has 288KB of standard work RAM, and that is not contiguous.
WRAM on the GBA exists in two segments: a 32KB segment with a 32 bit bus and a
256KB segment with a 16 bit bus.
With such a small amount of memory, heap usage must be strictly managed.
The use of vectors and allocating strings is not generally a good idea.
Allocations in general are not a good idea, unless they will exist for the life
of the program, lest you fragment memory.

ROM on the other hand, has a whopping 32MB!
And on the GBA, the ROM reads at the same speed as the 256KB segment with the
16 bit bus, meaning the distinction between storage and memory becomes less
stark on the GBA.
Insofar as you do not need your memory to be writable, the GBA actually has as
much memory as the PS2 (or slightly more if you count the actual RAM).

The only downside of ROM is in the name: it is read only.
All data in ROM must be written at the time that you application is packaged.
You cannot simply load data into ROM at runtime, which is why we want to
*preload* the data at build time.
And this is not some hard to use format that limits you from doing anything
resembling normal programming.
The preloaded data will actually map to your data structures so you can use
them as you would if you had simply read it from
[MetalClaw](/posts/metal-claw/) or JSON at runtime.
It will also let you use types like ```ox::Vector``` and ```ox::String```,
which actually allocate.
Pointer sizes and alignments get translated to the appropriate architecture.

There are of course some limitations:
* No virtual functions on preloaded types
* No use of STL types (which GBA the build of *Nostalgia* does not have access to anyway)
* All types must have a [model](/posts/model-system/) defined for them
* Integrals *must* have a standard size between the host and target platforms
  (e.g. use ```int64_t``` instead of ```long long```)
* All pointers are considered separate allocations, even if they are repeats or
  point to members of the same object
* Floats are not currently supported, but that is likely to change

With that in mind, here is an example of how *Nostalgia* is using the Ox
Preloader in an early iteration of its scene system.

Note: while this segment is written with an SOA structure, that is not a
requirement for the preloader.
```cpp
struct TileStatic {
	static constexpr auto TypeName = "net.drinkingtea.jasper.world.TileStatic";
	static constexpr auto TypeVersion = 1;
	uint8_t objIdxRefSet{};
	uint8_t tileType{};
	uint8_t layerAttachments{};
};

OX_MODEL_BEGIN(TileStatic)
	OX_MODEL_FIELD(objIdxRefSet)
	OX_MODEL_FIELD(tileType)
	OX_MODEL_FIELD(layerAttachments)
OX_MODEL_END()


struct BgLayer {
	static constexpr auto TypeName = "net.drinkingtea.jasper.world.BgLayer";
	static constexpr auto TypeVersion = 1;
	uint8_t cbb{};
	ox::Vector<TileStatic> tiles;
};

OX_MODEL_BEGIN(BgLayer)
	OX_MODEL_FIELD(cbb)
	OX_MODEL_FIELD(tiles)
OX_MODEL_END()


struct ObjTileRefSet {
	static constexpr auto TypeName = "net.drinkingtea.jasper.world.ObjTileRefSet";
	static constexpr auto TypeVersion = 1;
	uint16_t tilesheetIdx{};
	uint16_t cbbIdx{};
	uint8_t cbb{};
	uint8_t palBank{};
	// which tilesheet to use
	uint8_t tilesheetId{};
	uint8_t tileCnt{};
	// each successive frame will use tileIdx[i] + tileCnt * frameNo for the tileIdx
	uint8_t frameSets{};
	uint8_t frames{};
	uint16_t intervalMs{};
};

OX_MODEL_BEGIN(ObjTileRefSet)
	OX_MODEL_FIELD(tilesheetIdx)
	OX_MODEL_FIELD(cbbIdx)
	OX_MODEL_FIELD(cbb)
	OX_MODEL_FIELD(palBank)
	OX_MODEL_FIELD(tilesheetId)
	OX_MODEL_FIELD(tileCnt)
	OX_MODEL_FIELD(frameSets)
	OX_MODEL_FIELD(frames)
	OX_MODEL_FIELD(intervalMs)
OX_MODEL_END()

[[nodiscard]]
constexpr bool operator==(ObjTileRefSet const&a, ObjTileRefSet const&b) noexcept {
	return
		a.tilesheetIdx == b.tilesheetIdx &&
		a.cbbIdx == b.cbbIdx &&
		a.cbb == b.cbb &&
		a.palBank == b.palBank &&
		a.tilesheetId == b.tilesheetId &&
		a.tileCnt == b.tileCnt &&
		a.frameSets == b.frameSets &&
		a.frames == b.frames &&
		a.intervalMs == b.intervalMs;
}


struct WorldStatic {
	static constexpr auto TypeName = "net.drinkingtea.jasper.world.WorldStatic";
	static constexpr auto TypeVersion = 1;
	static constexpr auto Preloadable = true;
	ox::Vector<ObjTileRefSet> objTileRefSets;
	ox::Vector<ox::FileAddress> tilesheets;
	ox::Vector<ox::FileAddress> palettes;
	int16_t columns{};
	int16_t rows{};
	ox::Array<BgLayer, 3> map;
};

OX_MODEL_BEGIN(WorldStatic)
	OX_MODEL_FIELD(objTileRefSets)
	OX_MODEL_FIELD(tilesheets)
	OX_MODEL_FIELD(palettes)
	OX_MODEL_FIELD(columns)
	OX_MODEL_FIELD(rows)
	OX_MODEL_FIELD(map)
OX_MODEL_END()
```

Notice that in addition to the TypeName and TypeVersion values, which are a
standard part of Ox models, ```WorldStatic``` also has a Preloadable field,
which is set to true.
If Preloadable is not set to true or does not exist, ```Keel Pack``` will not
preload files of this type.
Only the highest level type in the composition must be marked Preloadable.
Types of member variables can leave it unmarked or false.

This object, along with all of the allocations in its Vectors, exists entirely
in ROM on the GBA.
Pointers to the allocations are correct, and not counting spacing for
alignment, all data is contiguous.

There is no special function that must be written just for ```WorldStatic``` to
allow it to preload.
Only the standard Ox model is necessary.

## How does it work?

Through the [Ox Model system](/posts/model-system), we know the structure of
any struct with a model defined.
Assuming we use consistently sized primitive types, like int64_t, we know the
size and alignment our structs have on other platforms.
Pointer sizes do vary, but in a predictable manner.
We also know the endianness of the target platform.

### Setup

To support different platforms in the future, the preloader system takes a
platform spec as a type argument.
These platform specs provide the following information:

* Appropriately sized unsigned int to handle platform pointers
* Appropriately sized size_t type (probably universally the same as the pointer
  type, but the C++ standard says it is decltype(alignof(int)) and not
  uintptr_t)
* The location in memory of ROM
* Alignof functions for all primitive types (generally predictable, but
  configurable just in case on platform decides to be weird)
* A function to convert integers from the native byte order to the target byte
  order

Here is the GBA platform spec:
```cpp
struct GbaPlatSpec {
	using PtrType = uint32_t;
	using size_t = uint32_t;

	static constexpr PtrType RomStart = 0x08000000;

	[[nodiscard]]
	static constexpr std::size_t alignOf(bool) noexcept {
		return 1;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(uint8_t) noexcept {
		return 1;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(uint16_t) noexcept {
		return 2;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(uint32_t) noexcept {
		return 4;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(uint64_t) noexcept {
		return 8;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(int8_t)  noexcept {
		return 1;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(int16_t) noexcept {
		return 2;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(int32_t) noexcept {
		return 4;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(int64_t) noexcept {
		return 8;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(auto*) noexcept {
		return 4;
	}

	[[nodiscard]]
	static constexpr auto correctEndianness(auto v) noexcept {
		return ox::toLittleEndian(v);
	}
};
```


### Preloading a Struct

As stated earlier, the preloader uses the Ox model system to get the structure
of the types it preloads.
Using Ox type descriptors, it could actually preload types that are not
included in the preloading program.
```Keel Pack```, using Ox type descriptors, creates the types dynamically using
```ModelValue```.

The preloader starts by creating a preload buffer, which is where the preloaded
data will live.

Leveraging the model system, the preloader has its own ```alignOf``` and
```sizeOf``` functions to get the alignment and size of types on the target
platform.
Using those functions, the preloader will allocate enough space in the buffer
for the type of the struct on the target platform at the alignment-appropriate
offset from the current write location of the buffer.

So, now we look at loading various different member types within the struct.

#### Loading Primitives

This is the most basic component of the preloader.
As stated earlier, you need to use fixed size integers (use int64_t instead of
long long).

The only thing done here is to fetch the alignment from the plat spec and use
the plat spec to ensure the correct endianness.

The C++ standard does not actually specify that bools are 1 byte and no major
compiler makes them any other size.
Accordingly, plat specs currently do no supply a way to specify a different
size for bools.

#### Loading Member Structs

For member variables that are other structs, the solution is to basically
recurse into the preload function for the child data.

#### Loading Pointers

This is the tricky part.
Pointers vary in size between platforms, and you cannot simply require fixed
sizes as with integers.
Also, the locations that the pointers point to will not be valid for the
preload buffer.

Pointers are the main reason we needed the custom ```sizeOf``` and
```alignOf``` functions.
Really, pointers are the main reason this whole thing is not a totally trivial
problem when targeting a platform with the same endianness as your build
machine.

With the plat spec, we know the size of pointers on the target system, so we
can write out the pointer itself as an appropriately sized unsigned integer.

The size is taken care of, but not the location of the data pointed to.
When loading the data of the child allocation, the preloader jumps to the
current end of the buffer and extend it to have enough space for the child
allocation.
Once the separate allocation has been written at the end of the buffer, the
preloader will set the buffer write location back to the location of the
pointer once the pointed to data has been loaded, and from there continue
loading the original parent struct.
Once the parent struct has finished loading, the preloader will set the write
point in the buffer to the end to allow preloading more data.

Pointers are currently assumed to be unique in preloaded data, so if you have
two pointers to the same address, the data at that address will get duplicated.

Now, the pointer is the right size and the data is getting loaded, but the
pointer itself is still garbage.
Instead of writing the address of the original pointer, we write the offset of
the pointed data from the start of the preload buffer, or 0 if the original
pointer was null.
That is still not going to be correct on the target system.
To deal with this, we save the location of the pointer to a separate list for
use later.

We now need to iterate over all the pointers written to the preload buffer, and
add the location of ROM (provided by the plat spec) plus the size of all data
preceding the preload buffer in memory to every non-null pointer. In the case
of the GBA, this means, the location of ROM + the size of the executable +
alignment padding + the size of the Ox FS image + alignment padding.

## Accessing Preloaded Data

Now we just need a way to find the data we have preloaded.
The way you do this could vary and the preloader does not provide for this.
The ```Keel Pack``` Pack utility does provide for this though, and we will
cover that here.

Every root parent struct preloaded will replace the data of the preloaded files
in the Ox FS image shipped in ROM with the offset of the desired struct from
the start of the preload buffer.
Do note that this means the size of the FS image will change throughout the
building of the preload buffer.
This means that the final correction of all the pointers actually takes place
after this step.

After all of this, the preload buffer is appended to the end of the ROM file
and will show up in ROM when the program is run on a GBA.

Using the asset loading API within Nostalgia that uses the preloader, the
loaded structs come back as const references regardless of whether the data was
loaded at runtime or at the time of the data packing.
This means that accessing the data from application code will still look like
it is being loaded at runtime, so using the preloader is totally transparent
and does not require platform specific application code.

The following snippet shows how to load an asset:
```cpp
// AssetRef serves as a reference counting pointer on non-ROM platforms, and is
// merely a pointer wrapper on ROM platforms.
keel::AssetRef<world::WorldStatic> scn =
    keel::readObj<world::WorldStatic>(ctx, "/Worlds/Chester.jwld").unwrap();
```

On the GBA, that data already exists in ROM at the time the program starts, and
the ```readObj``` call merely finds it.
On PC, the ```readObj``` actually reads the data from storage and deserializes
it to a usable form.
Regardless of platform or loading mechanism, the application code is the same.
