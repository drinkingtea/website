---
title:  "Ox Preloader"
author: Gary Talent
description: "Using ROM as RAM"
categories: ["Tech", "Programming"]
images:
- /dt-logo.png
tags: ["cpp", "programming", "serialization", "nostalgia", "ox", "preloader", "preloading"]
date: 2023-02-27
showtoc: true
---

Note: this is based on the following commit in the [Nostalgia repo](https://git.drinkingtea.net/drinkingtea/nostalgia):
[e9965a63ce6a8df6427052b5464f0525c61b65fc](https://git.drinkingtea.net/drinkingtea/nostalgia/src/commit/e9965a63ce6a8df6427052b5464f0525c61b65fc)

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
256KB with 16 bit bus.
With such a small amount of memory, heap usage must be strictly managed.
The use of vectors and allocating strings is not generally a good idea.
Allocations in general are not a good idea, unless they will exist for the life
of the program, lest you fragment memory.

ROM on the other hand, has a whopping 32MB!
And on the GBA, the ROM reads at the same speed as the 256KB segment with the
16 bit bus, meaning the distinction between storage and memory becomes less
stark on the GBA.
Insofar as the you do not need your memory to be writable, the GBA actually has
as much memory as the PS2 (or slightly more if you actually count RAM).

The only downside of ROM is in the name: it is read only.
All data in ROM must be written at the time that you application is packaged.
You cannot simply load data into ROM at runtime, which is why we want to
*preload* the data at build time.
And this is not some hard to use format that limits you from doing anything
resembling normal programming.
The preloaded data will actually map to your data structures so you can use
them as you would if you had simply read it from Metal Claw or JSON at runtime.
It will also let you use types like ox::Vector and ox::String, which actually
allocate.
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
struct SceneStatic {

	constexpr static auto TypeName = "net.drinkingtea.nostalgia.scene.SceneStatic";
	constexpr static auto TypeVersion = 1;
	constexpr static auto Preloadable = true;

	struct Tile {
		uint16_t &tileMapIdx;
		uint8_t &tileType;
		constexpr Tile(uint16_t *pTileMapIdx, uint8_t *pTileType) noexcept:
			tileMapIdx(*pTileMapIdx),
			tileType(*pTileType) {
		}
	};
	struct Layer {
		uint16_t &columns;
		uint16_t &rows;
		ox::Vector<uint16_t> &tileMapIdx;
		ox::Vector<uint8_t> &tileType;
		constexpr Layer(
				uint16_t *pColumns,
				uint16_t *pRows,
				ox::Vector<uint16_t> *pTileMapIdx,
				ox::Vector<uint8_t> *pTileType) noexcept:
			columns(*pColumns),
			rows(*pRows),
			tileMapIdx(*pTileMapIdx),
			tileType(*pTileType) {
		}
		[[nodiscard]]
		constexpr Tile tile(std::size_t i) noexcept {
			return {&tileMapIdx[i], &tileType[i]};
		}
		constexpr auto setDimensions(geo::Size dim) noexcept {
			columns = dim.width;
			rows = dim.height;
			const auto tileCnt = static_cast<unsigned>(columns * rows);
			tileMapIdx.resize(tileCnt);
			tileType.resize(tileCnt);
		}
	};

	ox::FileAddress tilesheet;
	ox::Vector<ox::FileAddress> palettes;
	// tile layer data
	ox::Vector<uint16_t> columns;
	ox::Vector<uint16_t> rows;
	ox::Vector<ox::Vector<uint16_t>> tileMapIdx;
	ox::Vector<ox::Vector<uint8_t>>  tileType;

	[[nodiscard]]
	constexpr Layer layer(std::size_t i) noexcept {
		return {&columns[i], &rows[i], &tileMapIdx[i], &tileType[i]};
	}

	constexpr auto setLayerCnt(std::size_t layerCnt) noexcept {
		this->columns.resize(layerCnt);
		this->rows.resize(layerCnt);
		this->tileMapIdx.resize(layerCnt);
		this->tileType.resize(layerCnt);
	}

};

oxModelBegin(SceneStatic)
	oxModelField(tilesheet)
	oxModelField(palettes)
	oxModelField(columns)
	oxModelField(rows)
	oxModelFieldRename(tile_map_idx, tileMapIdx)
	oxModelFieldRename(tile_type, tileType)
oxModelEnd()
```

Notice that in addition to the TypeName and TypeVersion values, which are a
standard part of Ox models, SceneStatic also has a Preloadable field, which is
set to true.
If Preloadable is not set to true or does not exist, ```nost-pack``` will not
preload files of this type.
Only the highest level type in the composition must be marked Preloadable.
Types of member variables can leave it unmarked or false.

This object, along with all of the allocations in its Vectors, exists entirely
in ROM on the GBA.
Pointers to the allocations are correct, and not counting spacing for
alignment, all data is contiguous.

There is no special function that must be written just for SceneStatic to allow
it to preload.
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
	static constexpr std::size_t alignOf(const bool) noexcept {
		return 1;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const uint8_t) noexcept {
		return 1;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const uint16_t) noexcept {
		return 2;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const uint32_t) noexcept {
		return 4;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const uint64_t) noexcept {
		return 8;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const int8_t)  noexcept {
		return 1;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const int16_t) noexcept {
		return 2;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const int32_t) noexcept {
		return 4;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const int64_t) noexcept {
		return 8;
	}

	[[nodiscard]]
	static constexpr std::size_t alignOf(const auto*) noexcept {
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
```nost-pack```, using Ox type descriptors, creates the types dynamically using
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
Still, the plat spec will allow you specify a size for them.

#### Loading Member Structs

For member variables that are other structs, the solution is to basically
recurse into the preload function for the child data.

#### Loading Pointers

This is the tricky part.
Pointers vary in size between platforms, and you cannot simply require fixed
sizes as with integers.
Also, the locations that the pointers point to will not be valid for the
preload buffer.

This is the main reason we needed the custom ```sizeOf``` and ```alignOf```
functions.
Really, pointers are the main reason this whole thing is not a totally trivial
problem when targeting a platform with the same endianness as your build
machine.

With the plat spec, we know the size of pointers on the target system, so we
can write out the pointer itself as an appropriately sized unsigned integer.

The size is taken care of, but not the location of the data pointed to.
When loading the data of the child allocation, the preloader jumps to the
current end of the buffer and extend it to have enough space for the child
struct.
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
the pointed data from the start of the pointer, or 0 if the original pointer
was null.
That is still not going to be correct on the target system.
To deal with this, we save the location of the pointer to a separate list for
use later.

We now need to iterate over all the pointers written to the preload buffer, and
add the location of ROM (provided by the plat spec) plus the size of all data
preceding the preload buffer in memory to every non-null pointer. In the case
of the GBA, this means, the location of ROM + the size of the executable +
padding to make the executable size a multiple of 8 + the size of the Ox FS
image.

## Accessing Preloaded Data

Now we just need a way to find the data we have preloaded.
The way you do this could vary and the preloader does not provide for this.
```nost-pack``` does provide for this though, and we will cover that here.

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
constexpr ox::FileAddress SceneAddr("/Scenes/Chester.nscn");
auto scn = foundation::readObj<scene::SceneStatic>(ctx.get(), SceneAddr).unwrap();
```

On the GBA, that data already exists in ROM at the time the program starts, and
the ```readObj``` call merely finds it.
On PC, the ```readObj``` actually reads the data from storage and deserializes
it to a usable form.
Regardless of platform or loading mechanism, the application code is the same.
